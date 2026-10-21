from contextlib import closing
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone
import unittest

spec = importlib.util.spec_from_file_location('recovery', Path(__file__).with_name('recovery.py'))
recovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recovery)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='ecc-recovery-test-')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.database = self.root / 'live.sqlite3'
        self.backups = self.root / 'backups'
        self.conn = sqlite3.connect(self.database)
        self.addCleanup(self.conn.close)
        self.conn.execute('PRAGMA journal_mode=WAL')
        self.conn.executescript('''CREATE TABLE parents(id INTEGER PRIMARY KEY);
            CREATE TABLE records(id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parents(id), payload BLOB);
            INSERT INTO parents VALUES(1);''')
        self.conn.execute('INSERT INTO records VALUES (1,1,?)', (b'client attachment\x00\xff',))
        self.conn.commit()

    def backup(self, **kwargs):
        return recovery.backup_once(self.database, self.backups, **kwargs)

    def test_committed_wal_and_exact_document_bytes_are_preserved(self):
        snapshot = self.backup()
        with closing(sqlite3.connect(snapshot)) as conn:
            self.assertEqual(conn.execute('SELECT payload FROM records').fetchone(), (b'client attachment\x00\xff',))
        self.assertEqual(recovery.verify(snapshot)['sha256'], recovery.digest(snapshot))
        self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
        self.assertEqual(recovery.manifest_path(snapshot).stat().st_mode & 0o777, 0o600)

    def test_uncommitted_work_is_not_in_snapshot(self):
        self.conn.execute('INSERT INTO records VALUES (2,1,?)', (b'not committed',))
        snapshot = self.backup()
        with closing(sqlite3.connect(snapshot)) as conn:
            self.assertEqual(conn.execute('SELECT count(*) FROM records').fetchone(), (1,))
        self.conn.rollback()

    def test_roundtrip_restore_and_source_unchanged(self):
        snapshot = self.backup()
        before = recovery.digest(snapshot)
        target = self.root / 'recovered.sqlite3'
        evidence = recovery.restore(snapshot, target)
        with closing(sqlite3.connect(target)) as conn:
            self.assertEqual(conn.execute('SELECT * FROM records').fetchall(), [(1, 1, b'client attachment\x00\xff')])
            self.assertEqual(conn.execute('PRAGMA integrity_check').fetchone(), ('ok',))
        self.assertEqual(evidence['sourceSnapshot'], snapshot.name)
        self.assertEqual(before, recovery.digest(snapshot))

    def test_automatic_restore_drill_records_evidence(self):
        snapshot = self.backup()
        evidence = recovery.drill(snapshot)
        self.assertEqual(evidence['tableCounts']['records'], 1)
        self.assertEqual(evidence['snapshot'], snapshot.name)
        self.assertTrue((self.backups / 'restore-drill-status.json').is_file())
        self.assertEqual(list(self.root.glob('ecc-restore-drill-*')), [])

    def test_restore_drill_checks_document_bytes(self):
        self.conn.execute('CREATE TABLE documents(id INTEGER PRIMARY KEY,content BLOB)')
        self.conn.execute('INSERT INTO documents VALUES(7,?)', (b'\x00\xffA',))
        self.conn.commit()
        snapshot = self.backup()
        evidence = recovery.drill(snapshot)
        self.assertEqual(evidence['tableCounts']['documents'], 1)
        self.assertEqual(evidence['documentBytesSha256'], hashlib.sha256(b'7:3:\x00\xffA').hexdigest())

    def test_drill_rejects_corruption_without_success_marker(self):
        snapshot = self.backup()
        recovery.manifest_path(snapshot).write_text('{}')
        with self.assertRaises(recovery.RecoveryError):
            recovery.drill(snapshot)
        self.assertFalse((self.backups / 'restore-drill-status.json').exists())

    def test_restore_refuses_existing_database(self):
        snapshot = self.backup()
        before = self.database.read_bytes()
        with self.assertRaises(recovery.RecoveryError):
            recovery.restore(snapshot, self.database)
        self.assertEqual(before, self.database.read_bytes())

    def test_restore_refuses_stranded_wal(self):
        snapshot = self.backup()
        destination = self.root / 'stranded.sqlite3'
        Path(str(destination) + '-wal').write_bytes(b'committed recovery evidence')
        with self.assertRaises(recovery.RecoveryError):
            recovery.restore(snapshot, destination)
        self.assertFalse(destination.exists())

    def test_corruption_is_detected_before_destination_creation(self):
        snapshot = self.backup()
        with snapshot.open('r+b') as stream:
            stream.seek(100)
            stream.write(b'corrupt!')
        destination = self.root / 'never-created.sqlite3'
        with self.assertRaises(recovery.RecoveryError):
            recovery.restore(snapshot, destination)
        self.assertFalse(destination.exists())

    def test_missing_or_wrong_manifest_fails_closed(self):
        snapshot = self.backup()
        manifest = recovery.manifest_path(snapshot)
        data = json.loads(manifest.read_text())
        for patch in [{'file': 'wrong.sqlite3'}, {'format': 999}, {'bytes': 0}, {'sha256': '0'*64}]:
            with self.subTest(patch=patch):
                manifest.write_text(json.dumps({**data, **patch}))
                with self.assertRaises(recovery.RecoveryError):
                    recovery.verify(snapshot)
        manifest.unlink()
        with self.assertRaises(FileNotFoundError):
            recovery.verify(snapshot)

    def test_foreign_key_failure_produces_no_snapshot(self):
        self.conn.execute('INSERT INTO records VALUES (2,999,?)', (b'orphan',))
        self.conn.commit()
        with self.assertRaises(recovery.RecoveryError):
            self.backup()
        self.assertEqual(list(self.backups.glob('ecc-*')), [])
        self.assertEqual(list(self.backups.glob('.sqlite-copy-*')), [])

    def test_missing_source_is_not_created(self):
        missing = self.root / 'missing.sqlite3'
        with self.assertRaises(recovery.RecoveryError):
            recovery.backup_once(missing, self.backups)
        self.assertFalse(missing.exists())

    def test_empty_or_invalid_source_is_rejected(self):
        for data in [b'', b'not a database']:
            with self.subTest(data=data):
                source = self.root / 'invalid.sqlite3'
                source.write_bytes(data)
                with self.assertRaises((recovery.RecoveryError, sqlite3.DatabaseError)):
                    recovery.backup_once(source, self.backups)
        self.assertEqual(list(self.backups.glob('ecc-*')), [])

    def test_operation_lock_prevents_overlap(self):
        with recovery.manager_lock(self.backups):
            with self.assertRaises(recovery.RecoveryError):
                self.backup()

    def test_symbolic_source_and_destination_are_rejected(self):
        source = self.root / 'source-link.sqlite3'
        source.symlink_to(self.database)
        with self.assertRaises(recovery.RecoveryError):
            recovery.backup_once(source, self.backups)
        target = self.root / 'target-link.sqlite3'
        target.symlink_to(self.root / 'missing-target')
        with self.assertRaises(recovery.RecoveryError):
            recovery.copy_verified(self.database, target)

    def test_timeout_cleans_partial_files(self):
        with self.assertRaises(TimeoutError):
            recovery.copy_verified(self.database, self.root / 'timed-out.sqlite3', timeout=-1)
        self.assertFalse((self.root / 'timed-out.sqlite3').exists())
        self.assertEqual(list(self.root.glob('.sqlite-copy-*')), [])

    def test_retention_latest_and_calendar_tiers(self):
        now = datetime(2026, 10, 18, tzinfo=timezone.utc)
        snapshots = [self.backup(now=now-timedelta(days=offset)) for offset in range(40)]
        recovery.retain(self.backups, latest=2, daily=3, weekly=2, monthly=2)
        kept = set(self.backups.glob('ecc-*.sqlite3'))
        self.assertIn(snapshots[0], kept)
        self.assertIn(snapshots[1], kept)
        # Every configured calendar tier retains its most recent snapshot.
        self.assertIn(snapshots[2], kept)
        self.assertTrue(any('202609' in path.name for path in kept))
        self.assertLess(len(kept), 10)
        for path in kept:
            recovery.verify(path)
        self.assertEqual(len(list(self.backups.glob('ecc-*.sqlite3.json'))), len(kept))

    def test_invalid_retention_never_deletes(self):
        snapshot = self.backup()
        for args in [dict(latest=0), dict(daily=-1), dict(weekly=-1), dict(monthly=-1)]:
            with self.assertRaises(recovery.RecoveryError):
                recovery.retain(self.backups, **args)
        self.assertTrue(snapshot.exists())

    def test_corrupt_snapshot_stops_retention(self):
        first, second = self.backup(), self.backup()
        recovery.manifest_path(first).write_text('{}')
        with self.assertRaises(recovery.RecoveryError):
            recovery.retain(self.backups, latest=1, daily=0, weekly=0, monthly=0)
        self.assertTrue(first.exists())
        self.assertTrue(second.exists())

    def test_automatic_worker_takes_initial_snapshot_and_stops_cleanly(self):
        process = subprocess.Popen([sys.executable, str(Path(recovery.__file__)), 'run',
            '--database', str(self.database), '--directory', str(self.backups), '--interval', '60'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            # communicate with a deadline; wait only for bounded initial startup.
            import time
            deadline = time.monotonic() + 10
            while not (self.backups / 'restore-drill-status.json').exists() and time.monotonic() < deadline:
                if process.poll() is not None:
                    self.fail(process.communicate(timeout=2))
                time.sleep(0.05)
            self.assertTrue((self.backups / 'restore-drill-status.json').exists())
            process.terminate()
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stderr)
            self.assertIn('backup-success', stdout)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=5)


if __name__ == '__main__':
    unittest.main(verbosity=2)
