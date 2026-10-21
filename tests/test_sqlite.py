from contextlib import closing
import concurrent.futures
import importlib.util
import os
import sys
import json
import pathlib
import re
import sqlite3
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]

def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module

backup = load_script('sqlite_backup')
worker = load_script('mail_worker')
monitor = load_script('monitor')
backup_worker = load_script('backup_worker')
audit_haskell = load_script('audit_haskell')
restore_drill = load_script('restore_drill')


def create_database(path):
    conn = sqlite3.connect(path, timeout=10)
    conn.execute('PRAGMA journal_mode=WAL')
    conn.execute('PRAGMA foreign_keys=ON')
    for migration in sorted((ROOT / 'api/migrations').glob('*.sql')):
        conn.executescript(migration.read_text())
    conn.execute("INSERT INTO users(email,name,role,password_hash) VALUES ('admin@example.com','Admin','admin','private-hash')")
    conn.commit()
    return conn


class SQLiteTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ecc-sqlite-')
        self.path = pathlib.Path(self.temp.name) / 'app.sqlite3'
        self.conn = create_database(self.path)

    def tearDown(self):
        self.conn.close()
        self.temp.cleanup()

    def test_upgrade_preserves_existing_tasks_documents_and_references(self):
        with closing(sqlite3.connect(':memory:')) as legacy:
            legacy.execute('PRAGMA foreign_keys=ON')
            migrations = sorted((ROOT / 'api/migrations').glob('*.sql'))
            for migration in migrations[:3]:
                legacy.executescript(migration.read_text())
            legacy.execute("INSERT INTO users(email,name,role,password_hash) VALUES ('legacy@example.com','Legacy','admin','hash')")
            legacy.execute("INSERT INTO leads(lead_number,full_name) VALUES ('L-2026-12345','Existing contact')")
            legacy.execute("INSERT INTO tasks(lead_id,title) VALUES (1,'Existing task')")
            legacy.execute("INSERT INTO documents(lead_id,filename,content,size) VALUES (1,'legacy.txt',X'616263',3)")
            legacy.commit()
            legacy.executescript('BEGIN IMMEDIATE;\n' + migrations[3].read_text() + '\nCOMMIT;')
            self.assertEqual(legacy.execute('SELECT title FROM tasks').fetchone()[0], 'Existing task')
            self.assertEqual(legacy.execute('SELECT content FROM documents').fetchone()[0], b'abc')
            self.assertEqual(legacy.execute("SELECT value FROM reference_counters WHERE prefix='L' AND year=2026").fetchone()[0], 12345)
            self.assertEqual(legacy.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_concurrent_number_allocation_is_unique_and_durable(self):
        def allocate(_):
            with closing(sqlite3.connect(self.path, timeout=10)) as conn, conn:
                return conn.execute("INSERT INTO reference_counters(prefix,year,value) VALUES ('L',2026,1) ON CONFLICT(prefix,year) DO UPDATE SET value=value+1 RETURNING value").fetchone()[0]
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            numbers = list(pool.map(allocate, range(40)))
        self.assertEqual(sorted(numbers), list(range(1, 41)))
        self.assertEqual(allocate(None), 41)

    def test_audit_records_actor_and_excludes_passwords_and_document_bytes(self):
        with self.conn:
            self.conn.execute("UPDATE request_context SET actor_id=1 WHERE id=1")
            self.conn.execute("INSERT INTO leads(lead_number,full_name) VALUES ('L-2026-0001','Maya')")
            self.conn.execute("INSERT INTO documents(lead_id,filename,content,size) VALUES (1,'proof.txt',?,6)", (b'secret',))
            self.conn.execute("UPDATE users SET password_hash='new-private-hash' WHERE id=1")
        entries = self.conn.execute('SELECT changes,actor_id FROM audit_log').fetchall()
        self.assertTrue(any(actor == 1 for _, actor in entries))
        all_changes = json.dumps([json.loads(change) for change, _ in entries])
        self.assertNotIn('private-hash', all_changes)
        self.assertNotIn('secret', all_changes)
        self.assertNotIn('"content"', all_changes)

    def test_password_and_role_changes_revoke_sessions_and_reset_tokens(self):
        for column, value in [('password_hash', 'changed-hash'), ('role', 'consultant')]:
            with self.conn:
                self.conn.execute("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES ('session',1,'2099-01-01')")
                self.conn.execute("INSERT INTO account_tokens(token_hash,user_id,expires_at) VALUES ('reset',1,'2099-01-01')")
                self.conn.execute(f'UPDATE users SET {column}=? WHERE id=1', (value,))
            self.assertEqual(self.conn.execute('SELECT count(*) FROM sessions').fetchone()[0], 0)
            self.assertEqual(self.conn.execute('SELECT count(*) FROM account_tokens').fetchone()[0], 0)

    def test_online_backup_includes_committed_wal_and_restore_refuses_overwrite(self):
        with self.conn:
            self.conn.execute("INSERT INTO leads(lead_number,full_name) VALUES ('L-2026-0001','Committed in WAL')")
        target = pathlib.Path(self.temp.name) / 'snapshot.sqlite3'
        backup.copy_database(self.path, target)
        with closing(sqlite3.connect(target)) as restored:
            self.assertEqual(restored.execute('SELECT full_name FROM leads').fetchone()[0], 'Committed in WAL')
            self.assertEqual(restored.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
        with self.assertRaises(FileExistsError):
            backup.copy_database(self.path, target)

    def test_mail_lease_commits_before_network_io_and_scrubs_successful_body(self):
        with self.conn:
            self.conn.execute("INSERT INTO mail_outbox(recipient,subject,body) VALUES ('person@example.com','Account','sensitive link')")
        def deliver(_):
            # A separate writer can acquire the lock while SMTP is running.
            with closing(sqlite3.connect(self.path, timeout=.1)) as other, other:
                other.execute("INSERT INTO login_attempts(key,attempts,expires_at) VALUES ('parallel',1,'2099-01-01')")
        with patch.object(worker, 'deliver', side_effect=deliver):
            self.assertTrue(worker.run_once(self.conn))
        body, sent, attempts = self.conn.execute('SELECT body,sent_at,attempts FROM mail_outbox').fetchone()
        self.assertEqual(body, '')
        self.assertIsNotNone(sent)
        self.assertEqual(attempts, 1)

    def test_failed_mail_is_retryable_without_logging_secrets(self):
        with self.conn:
            self.conn.execute("INSERT INTO mail_outbox(recipient,subject,body) VALUES ('person@example.com','Account','sensitive link')")
        with patch.object(worker, 'deliver', side_effect=RuntimeError('secret password')), patch('builtins.print') as log:
            self.assertTrue(worker.run_once(self.conn))
            self.assertNotIn('secret password', str(log.call_args_list))
        self.assertEqual(self.conn.execute('SELECT body,attempts,last_error,claim_token FROM mail_outbox').fetchone(), ('sensitive link', 1, 'RuntimeError', None))

    def test_schema_validates_names_and_document_ownership(self):
        with self.assertRaises(sqlite3.IntegrityError):
            self.conn.execute("INSERT INTO leads(lead_number,full_name) VALUES ('L-2026-0001',' ')")
        with self.assertRaises(sqlite3.IntegrityError):
            self.conn.execute("INSERT INTO documents(filename,content) VALUES ('orphan.txt',X'')")

    def test_monitor_detects_readiness_mail_and_backup_failures(self):
        snapshots = pathlib.Path(self.temp.name) / 'backups'
        snapshots.mkdir()
        snapshot = snapshots / 'ecc-test.sqlite3'
        backup.copy_database(self.path, snapshot)
        from unittest.mock import MagicMock
        response = MagicMock()
        response.__enter__.return_value.status = 200
        env = {'DATABASE_PATH': str(self.path), 'MONITOR_URL': 'http://test/api/ready', 'BACKUP_DIR': str(snapshots), 'MIN_FREE_BYTES': '0'}
        with patch.dict(os.environ, env), patch.object(monitor.urllib.request, 'urlopen', return_value=response):
            self.assertEqual(monitor.problems(), ())
            with self.conn:
                self.conn.execute("INSERT INTO mail_outbox(recipient,subject,body,attempts,created_at) VALUES ('person@example.com','Account','private',5,datetime('now','-1 hour'))")
            issues = monitor.problems()
            self.assertIn('Account email delivery has failed', issues)
            self.assertIn('Account email queue is delayed', issues)
            snapshot.unlink()
            self.assertIn('Verified backups are missing or stale', monitor.problems())
        with patch.dict(os.environ, env), patch.object(monitor.urllib.request, 'urlopen', side_effect=OSError('unavailable')):
            self.assertIn('API readiness failed', monitor.problems())

    def test_restore_drill_records_document_parity_and_refuses_overwrite(self):
        self.conn.execute("INSERT INTO leads(lead_number,full_name) VALUES ('L-drill','Recovery contact')")
        self.conn.execute("INSERT INTO documents(lead_id,filename,mime_type,size,content) VALUES (1,'proof.txt','text/plain',5,?)", (b'proof',))
        self.conn.commit()
        snapshot = pathlib.Path(self.temp.name) / 'snapshot.sqlite3'
        destination = pathlib.Path(self.temp.name) / 'recovered.sqlite3'
        backup.copy_database(self.path, snapshot)
        report = restore_drill.drill(snapshot, destination)
        self.assertEqual(report['tableCounts']['documents'], 1)
        self.assertEqual(report['countsAndDocuments'], 'passed')
        self.assertIn('pending', report['applicationChecks'])
        with self.assertRaises(FileExistsError):
            restore_drill.drill(snapshot, destination)

    def test_security_audit_matches_versions_and_compiler_ranges(self):
        directory = pathlib.Path(self.temp.name) / 'advisories'
        directory.mkdir()
        advisory = directory / 'HSEC-2026-0001.md'
        advisory.write_text('```toml\n[advisory]\nid="HSEC-2026-0001"\n[[affected]]\npackage="example"\n[[affected.versions]]\nintroduced="1.0"\nfixed="1.2"\n[[affected.versions]]\nintroduced="2.0"\n```\n')
        plan = {'compiler-id': 'ghc-9.6.6', 'install-plan': [{'pkg-name': 'example', 'pkg-version': '1.1'}]}
        self.assertEqual(len(audit_haskell.audit(plan, directory)), 1)
        plan['install-plan'][0]['pkg-version'] = '1.2'
        self.assertEqual(audit_haskell.audit(plan, directory), [])
        plan['install-plan'][0]['pkg-version'] = '2.1'
        self.assertEqual(len(audit_haskell.audit(plan, directory)), 1)
        advisory.write_text(advisory.read_text().replace('package="example"', 'ghc-component="rts"').replace('introduced="2.0"','introduced="9.6"'))
        self.assertEqual(len(audit_haskell.audit(plan, directory)), 1)
        with self.assertRaises(ValueError):
            audit_haskell.audit(plan, pathlib.Path(self.temp.name) / 'missing')

    def test_backup_retention_and_offhost_failure_does_not_claim_success(self):
        directory = pathlib.Path(self.temp.name) / 'snapshots'
        directory.mkdir()
        with patch.dict(os.environ, {'RESTIC_REPOSITORY': ''}):
            for _ in range(4):
                backup_worker.backup_once(self.path, directory, 2)
        self.assertEqual(len(list(directory.glob('ecc-*.sqlite3'))), 2)
        with patch.dict(os.environ, {'RESTIC_REPOSITORY': 's3:https://backup.example/ecc', 'RESTIC_PASSWORD_FILE': '/secret'}), patch.object(backup_worker.subprocess, 'run', side_effect=RuntimeError('remote unavailable')):
            with self.assertRaises(RuntimeError):
                backup_worker.backup_once(self.path, directory, 2)
        self.assertFalse((directory / 'offhost-success').exists())
        self.assertEqual(len(list(directory.glob('ecc-*.sqlite3'))), 2)
        env = {'DATABASE_PATH': str(self.path), 'BACKUP_DIR': str(directory), 'MONITOR_URL': 'https://example.test/api/ready', 'REQUIRE_OFFHOST_BACKUP': 'true'}
        with patch.dict(os.environ, env), patch.object(monitor.urllib.request, 'urlopen') as request:
            request.return_value.__enter__.return_value.status = 200
            self.assertIn('Encrypted off-host backups are missing or stale', monitor.problems())

    def test_offhost_success_requires_backup_retention_and_check(self):
        directory = pathlib.Path(self.temp.name)
        env = {'RESTIC_REPOSITORY': 's3:https://backup.example/ecc', 'RESTIC_PASSWORD_FILE': '/secret'}
        with patch.dict(os.environ, env), patch.object(backup_worker.subprocess, 'run') as run:
            self.assertTrue(backup_worker.replicate(self.path, directory))
            self.assertEqual([call.args[0][1] for call in run.call_args_list], ['backup', 'forget', 'check'])
            self.assertIn('--stdin', run.call_args_list[0].args[0])
            self.assertIn('host,tags', run.call_args_list[1].args[0])
        self.assertTrue((directory / 'offhost-success').exists())

    def test_read_context_does_not_block_main_writer_and_audit_uses_main_actor(self):
        reader = sqlite3.connect(self.path, timeout=0.2)
        try:
            reader.execute("CREATE TEMP TABLE request_context AS SELECT * FROM main.request_context")
            self.conn.execute('BEGIN IMMEDIATE')
            reader.execute('BEGIN')
            reader.execute("UPDATE temp.request_context SET actor_id=99,role='viewer'")
            self.assertEqual(reader.execute('SELECT count(*) FROM users').fetchone()[0], 1)
            reader.commit()
            self.conn.execute('UPDATE main.request_context SET actor_id=1')
            self.conn.execute("INSERT INTO leads(lead_number,full_name) VALUES ('L-context','Context test')")
            self.conn.commit()
            self.assertEqual(reader.execute("SELECT actor_id FROM audit_log WHERE entity_name='Context test'").fetchone()[0], 1)
        finally:
            reader.close()
            self.conn.rollback()

    def test_every_complete_static_query_prepares_against_sqlite(self):
        self.conn.execute("CREATE TEMP TABLE request_context (id INTEGER PRIMARY KEY,actor_id INTEGER,role TEXT,assigned_only TEXT)")
        checked = 0
        for path in (ROOT / 'api/src/ECC').glob('*.hs'):
            if path.stem not in ('DB','Routes','Security','Seed','WorkflowSupport','Workflows','Operations','Portal','MFA'):
                continue
            for match in re.finditer(r'"(?:[^"\\]|\\[\s\S])*"', path.read_text()):
                sql = re.sub(r'\\\s*\\', '', match.group()[1:-1]).replace('\\"', '"')
                if not re.match(r'^(SELECT|INSERT|UPDATE|DELETE|WITH|PRAGMA)\b', sql):
                    continue
                if sql.endswith(('WHERE ', 'FROM ', 'SELECT ', ' BY ', 'FROM (', 'UPDATE ', '(')) or ';' in sql:
                    continue
                with self.subTest(file=path.name, query=sql[:70]):
                    self.conn.execute('EXPLAIN ' + sql, [None] * sql.count('?'))
                checked += 1
        self.assertGreaterEqual(checked, 75)
