#!/usr/bin/env python3
"""Real PostgreSQL recovery acceptance tests; required by the release gate.

ECC_TEST_DATABASE_URL must point to a disposable database named ecc_test, owned
by a test role with CREATEDB. Creates/drops only unique test-owned databases.
Never uses DATABASE_URL or a customer database.
"""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock
import uuid
from urllib.parse import urlsplit, urlunsplit, quote

import postgres_recovery as pg
import recovery
import operations

ROOT = Path(__file__).resolve().parents[1]


def database_url(base, name):
    return urlunsplit(urlsplit(base)._replace(path='/' + quote(name, safe='')))


class PostgresRecoveryIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import psycopg
        from psycopg import sql
        base = os.environ.get('ECC_TEST_DATABASE_URL')
        if not base or urlsplit(base).path != '/ecc_test':
            raise RuntimeError('Use a disposable ECC_TEST_DATABASE_URL with database name ecc_test')
        cls.base = base
        cls.name = 'ecc_backup_source_' + uuid.uuid4().hex
        cls.target_name = 'ecc_restore_' + uuid.uuid4().hex
        cls.source = database_url(base, cls.name)
        cls.target = database_url(base, cls.target_name)
        def remove(name):
            with psycopg.connect(base, autocommit=True) as admin:
                admin.execute(sql.SQL('DROP DATABASE {} WITH (FORCE)').format(sql.Identifier(name)))
        with psycopg.connect(base, autocommit=True) as admin:
            for name in [cls.name, cls.target_name]:
                admin.execute(sql.SQL("CREATE DATABASE {} TEMPLATE template0 ENCODING 'UTF8'").format(sql.Identifier(name)))
                cls.addClassCleanup(remove, name)
        with pg.connect(cls.source) as conn:
            conn.execute("CREATE TABLE schema_migrations(version TEXT PRIMARY KEY,applied_at TEXT NOT NULL DEFAULT(CAST(CURRENT_TIMESTAMP AS TEXT)))")
            for migration in sorted((ROOT / 'migrations/postgresql').glob('*.sql')):
                conn.execute(migration.read_text())
                conn.execute('INSERT INTO schema_migrations(version) VALUES(%s)', (migration.name,))
            conn.execute("INSERT INTO users(email,password_hash,name,role) VALUES('restore@example.invalid','fixture','Recovery test','admin')")
            conn.execute("INSERT INTO clients(client_number,full_name) VALUES('BACKUP-1','Recovery student')")
            conn.execute("INSERT INTO documents(client_id,filename,content,uploaded_by) VALUES(1,'profile.png',%s,1)", (b'\x00\xffPG-photo',))
            conn.execute('INSERT INTO client_photos(client_id,document_id) VALUES(1,1)')
            conn.execute("INSERT INTO cases(client_id,service_category,stage,institution,program) VALUES(1,'Student Visa','Submitted','Recovery College','Nursing')")
            conn.execute("INSERT INTO invoices(client_id,description,currency,amount_minor,due_date,status) VALUES(1,'Tuition','PHP',10000,'2020-01-01','Issued')")
            conn.execute("INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_id,actor_name) VALUES(1,4000,'2020-01-01','Cash',1,'Recovery test')")
            conn.execute("INSERT INTO expenses(supplier,description,category,currency,amount_minor,expense_on,created_by,created_name) VALUES('School','Fee','Education','PHP',500,'2020-01-01',1,'Recovery test')")
            conn.execute("INSERT INTO financial_files(expense_id,filename,content,size,uploaded_by,uploaded_name) VALUES(1,'receipt.pdf',%s,4,1,'Recovery test')", (b'\x00\xff\x01\x02',))

    def setUp(self):
        self.work = tempfile.TemporaryDirectory(prefix='ecc-pg-integration-')
        self.addCleanup(self.work.cleanup)
        self.directory = Path(self.work.name)
        self.addCleanup(self.reset_target)

    def reset_target(self):
        with pg.connect(self.target) as conn:
            conn.execute('DROP SCHEMA public CASCADE')
            conn.execute('CREATE SCHEMA public')

    def backup(self):
        return recovery.backup_once(self.source, self.directory, timeout=120)

    def test_complete_roundtrip_checks_every_row_and_binary_and_keeps_source(self):
        snapshot = self.backup()
        result = pg.restore(snapshot, self.target, timeout=120)
        self.assertTrue(result['logicalRecoveryVerified'])
        with pg.connect(self.target) as conn:
            self.assertEqual(bytes(conn.execute('SELECT content FROM documents WHERE id=1').fetchone()[0]), b'\x00\xffPG-photo')
            self.assertEqual(bytes(conn.execute('SELECT content FROM financial_files WHERE id=1').fetchone()[0]), b'\x00\xff\x01\x02')
            self.assertEqual(conn.execute('SELECT balance_minor FROM invoice_balances WHERE id=1').fetchone()[0], 6000)
            self.assertEqual(conn.execute('SELECT document_id FROM client_photos WHERE client_id=1').fetchone()[0], 1)
            self.assertEqual(conn.execute("SELECT program FROM cases WHERE id=1").fetchone()[0], 'Nursing')
        with pg.connect(self.source) as conn:
            self.assertEqual(bytes(conn.execute('SELECT content FROM documents WHERE id=1').fetchone()[0]), b'\x00\xffPG-photo')

    def test_sequence_restoration_and_audit_triggers_work_after_restore(self):
        snapshot = self.backup()
        pg.restore(snapshot, self.target, timeout=120)
        with pg.connect(self.target) as conn:
            previous = conn.execute('SELECT max(id) FROM clients').fetchone()[0]
            ident = conn.execute("INSERT INTO clients(client_number,full_name) VALUES('AFTER-RESTORE','New student') RETURNING id").fetchone()[0]
            self.assertGreater(ident, previous)
            self.assertEqual(conn.execute("SELECT count(*) FROM audit_log WHERE entity_type='client' AND entity_id=%s", (ident,)).fetchone()[0], 1)

    def test_restore_drill_is_verified_then_leaves_test_database_empty(self):
        snapshot = self.backup()
        with mock.patch.dict(os.environ, {'RESTORE_TEST_DATABASE_URL': self.target}):
            evidence = recovery.drill(snapshot)
        self.assertTrue(evidence['logicalRecoveryVerified'])
        self.assertTrue(json.loads((self.directory / 'restore-drill-status.json').read_text())['logicalRecoveryVerified'])
        with pg.connect(self.target) as conn:
            pg.require_empty(conn)

    def test_concurrent_commits_do_not_break_snapshot_consistency(self):
        original = pg.run_tool
        changed = []
        def tool(name, args, *rest, **kwargs):
            if name == 'pg_dump' and not changed:
                with pg.connect(self.source) as conn:
                    conn.execute("INSERT INTO clients(client_number,full_name) VALUES(%s,'After exported snapshot')", ('CONCURRENT-' + uuid.uuid4().hex,))
                changed.append(True)
            return original(name, args, *rest, **kwargs)
        with mock.patch.object(pg, 'run_tool', side_effect=tool):
            snapshot = self.backup()
        pg.restore(snapshot, self.target, timeout=120)
        with pg.connect(self.target) as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM clients WHERE full_name='After exported snapshot'").fetchone()[0], 0)
        with pg.connect(self.source) as conn:
            conn.execute("DELETE FROM clients WHERE full_name='After exported snapshot'")

    def test_uncommitted_writes_are_excluded(self):
        with pg.connect(self.source) as writer:
            try:
                writer.execute('BEGIN')
                writer.execute("INSERT INTO clients(client_number,full_name) VALUES('UNCOMMITTED','Not committed')")
                snapshot = self.backup()
            finally:
                writer.execute('ROLLBACK')
        pg.restore(snapshot, self.target, timeout=120)
        with pg.connect(self.target) as conn:
            self.assertEqual(conn.execute("SELECT count(*) FROM clients WHERE client_number='UNCOMMITTED'").fetchone()[0], 0)

    def test_occupied_target_is_preserved(self):
        snapshot = self.backup()
        with pg.connect(self.target) as conn:
            conn.execute('CREATE TABLE public.keep_me(value text)')
            conn.execute("INSERT INTO keep_me VALUES('keep')")
        with self.assertRaises(recovery.RecoveryError): pg.restore(snapshot, self.target)
        with pg.connect(self.target) as conn:
            self.assertEqual(conn.execute('SELECT value FROM keep_me').fetchone()[0], 'keep')

    def test_source_cannot_be_the_drill_or_restore_target(self):
        snapshot = self.backup()
        for cleanup in [False, True]:
            with self.assertRaises(recovery.RecoveryError): pg.restore(snapshot, self.source, cleanup=cleanup)
        with pg.connect(self.source) as conn:
            self.assertEqual(conn.execute('SELECT full_name FROM clients WHERE id=1').fetchone()[0], 'Recovery student')

    def test_corruption_is_rejected_before_writing_destination(self):
        snapshot = self.backup()
        with snapshot.open('r+b') as stream:
            stream.seek(20)
            stream.write(b'broken')
        with self.assertRaises(recovery.RecoveryError): pg.restore(snapshot, self.target)
        with pg.connect(self.target) as conn:
            pg.require_empty(conn)
        self.assertFalse((self.directory / 'restore-drill-status.json').exists())

    def test_changed_logical_manifest_never_records_success(self):
        snapshot = self.backup()
        path = recovery.manifest_path(snapshot)
        manifest = json.loads(path.read_text())
        manifest['evidence']['tableRowsSha256']['documents'] = 'incorrect'
        recovery.atomic_json(path, manifest)
        with self.assertRaises(recovery.RecoveryError): pg.drill(snapshot, self.target)
        self.assertFalse((self.directory / 'restore-drill-status.json').exists())
        with pg.connect(self.target) as conn:
            pg.require_empty(conn)

    def test_operations_orchestration_records_real_drill_and_offsite_validation(self):
        uploaded = []
        def restic(args):
            if args[0] == 'backup':
                uploaded[:] = [Path(path) for path in args[args.index('--')+1:]]
                return json.dumps({'message_type':'summary', 'snapshot_id':'b'*64})
            if args[0] == 'restore':
                import shutil
                for path in uploaded:
                    dest = Path(args[args.index('--target')+1]) / str(path).lstrip('/')
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(path, dest)
                return ''
            if args[0] == 'forget': return ''
            raise AssertionError('Unexpected restic operation')
        with mock.patch.dict(os.environ, {'RESTORE_TEST_DATABASE_URL': self.target}):
            operations.backup(self.source, self.directory, runner=restic)
        self.assertTrue(json.loads((self.directory / 'offsite-status.json').read_text())['restoreVerified'])
        self.assertTrue(json.loads((self.directory / 'restore-drill-status.json').read_text())['logicalRecoveryVerified'])


if __name__ == '__main__':
    # Missing infrastructure is a failure, never a passing/skipped release check.
    unittest.main(verbosity=2)
