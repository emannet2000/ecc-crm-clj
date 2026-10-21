from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock

import database
import operations
import postgres_recovery as pg
import recovery


class ArchiveFixture:
    def __enter__(self):
        self.directory = tempfile.TemporaryDirectory(prefix='ecc-pg-recovery-test-')
        self.root = Path(self.directory.name)
        self.tool = mock.patch.object(pg, 'run_tool', return_value=b'archive listing')
        self.tool.start()
        return self

    def __exit__(self, *args):
        self.tool.stop()
        self.directory.cleanup()

    def snapshot(self, payload=b'PGDMP-fixture', age=0):
        stamp = datetime(2026, 10, 22, tzinfo=timezone.utc) - timedelta(days=age)
        path = self.root / ('ecc-' + stamp.strftime('%Y%m%d') + '-' + str(len(list(self.root.glob('*.pgdump')))) + '.pgdump')
        path.write_bytes(payload)
        path.chmod(0o600)
        metadata = {'format': 2, 'engine': 'postgresql', 'file': path.name,
                    'createdAt': stamp.isoformat(), 'bytes': len(payload),
                    'sha256': hashlib.sha256(payload).hexdigest(), 'sourceIdentity': 'a' * 64,
                    'evidence': {'tableCounts': {'documents': 1}, 'tableRowsSha256': {'documents': 'b' * 64}, 'columns': {'documents': ['content']}}}
        recovery.atomic_json(recovery.manifest_path(path), metadata)
        return path


class FakeConnection:
    def __init__(self, name='ecc_restore_test', objects=0):
        self.name, self.objects, self.statements = name, objects, []

    def execute(self, statement, parameters=None):
        self.statements.append(str(statement))
        if str(statement) == 'SELECT current_database()':
            value = self.name
        elif 'pg_class' in str(statement):
            value = self.objects
        else:
            value = 0
        return mock.Mock(fetchone=lambda: (value,))

    @contextmanager
    def transaction(self):
        yield self


@contextmanager
def connection(value):
    yield value


class PostgresRecoveryTests(unittest.TestCase):
    def test_archive_checksum_is_checked_before_tools_or_database_access(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            snapshot.write_bytes(b'changed bytes')
            with mock.patch.object(pg, 'connect') as connect, self.assertRaises(recovery.RecoveryError):
                recovery.restore(snapshot, 'postgresql://unused.invalid/test')
            connect.assert_not_called()

    def test_source_destination_is_rejected_without_restore_or_cleanup(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            conn = FakeConnection()
            with mock.patch.object(pg, 'connect', return_value=connection(conn)), mock.patch.object(pg, 'database_identity', return_value='a' * 64), self.assertRaises(recovery.RecoveryError):
                pg.restore(snapshot, 'postgresql://unused.invalid/test', cleanup=True)
            self.assertFalse(any('DROP' in item for item in conn.statements))
            self.assertFalse((f.root / 'restore-drill-status.json').exists())

    def test_nonempty_destination_is_never_cleaned_or_overwritten(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            conn = FakeConnection(objects=1)
            with mock.patch.object(pg, 'connect', return_value=connection(conn)), mock.patch.object(pg, 'database_identity', return_value='different'), self.assertRaises(recovery.RecoveryError):
                pg.restore(snapshot, 'postgresql://unused.invalid/test', cleanup=True)
            self.assertFalse(any('DROP' in item for item in conn.statements))

    def test_drill_requires_dedicated_database_name_before_any_cleanup(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            conn = FakeConnection(name='live_crm')
            with mock.patch.object(pg, 'connect', return_value=connection(conn)), mock.patch.object(pg, 'database_identity', return_value='different'), self.assertRaises(recovery.RecoveryError):
                pg.restore(snapshot, 'postgresql://unused.invalid/test', cleanup=True)
            self.assertFalse(any('DROP' in item for item in conn.statements))

    def test_drill_cannot_claim_success_without_a_test_database(self):
        with mock.patch.dict(os.environ, {}, clear=True), self.assertRaises(recovery.RecoveryError):
            pg.drill('/not-opened.pgdump')

    def test_no_credentials_or_inherited_pg_overrides_in_tool_arguments(self):
        url = 'postgresql://fixture-user:private-test-password@example.invalid/crm'
        with mock.patch.dict(os.environ, {'PGOPTIONS': '-c evil=1', 'PGSERVICE': 'unexpected', 'JWT_SECRET': 'private-jwt'}), mock.patch.object(subprocess, 'run', return_value=mock.Mock(returncode=0, stdout=b'')) as run:
            pg.run_tool('pg_restore', ['--dbname=', '--single-transaction'], url)
        args, kwargs = run.call_args
        self.assertNotIn('private-test-password', str(args))
        self.assertNotIn('PGOPTIONS', kwargs['env'])
        self.assertNotIn('PGSERVICE', kwargs['env'])
        self.assertNotIn('JWT_SECRET', kwargs['env'])
        self.assertIn('sslmode=require', kwargs['env']['PGDATABASE'])

    def test_tool_errors_do_not_expose_server_stderr(self):
        with mock.patch.object(subprocess, 'run', return_value=mock.Mock(returncode=1, stdout=b'', stderr=b'private-user password')):
            with self.assertRaises(recovery.RecoveryError) as raised:
                pg.run_tool('pg_dump', [], 'postgresql://unused.invalid/test')
        self.assertNotIn('private-user', str(raised.exception))

    def test_failed_pg_restore_records_no_drill_success_and_cleans_only_test_database(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            conn = FakeConnection()
            def tool(_name, args, *_rest, **_kwargs):
                if '--single-transaction' in args:
                    raise recovery.RecoveryError('simulated restore failure')
                return b'1; 2615 2200 SCHEMA - public owner\n2; 1259 12 TABLE public clients owner\n'
            with mock.patch.object(pg, 'run_tool', side_effect=tool), mock.patch.object(pg, 'connect', return_value=connection(conn)), mock.patch.object(pg, 'database_identity', return_value='different'), self.assertRaises(recovery.RecoveryError):
                pg.drill(snapshot, 'postgresql://unused.invalid/test')
            self.assertIn('DROP SCHEMA public CASCADE', conn.statements)
            self.assertFalse((f.root / 'restore-drill-status.json').exists())

    def test_logical_data_mismatch_rejects_restore(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            conn = FakeConnection()
            with mock.patch.object(pg, 'connect', return_value=connection(conn)), mock.patch.object(pg, 'database_identity', return_value='different'), mock.patch.object(pg, 'summary', return_value={'changed': True}), self.assertRaises(recovery.RecoveryError):
                pg.restore(snapshot, 'postgresql://unused.invalid/test')
            self.assertFalse(any('DROP' in item for item in conn.statements))

    def test_restore_keeps_verified_records_and_uses_atomic_restore(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            conn = FakeConnection(name='recovered_crm')
            evidence = recovery.verify(snapshot)['evidence']
            calls = []
            def tool(_tool, args, *_rest, **_kwargs):
                calls.append(args)
                if '--single-transaction' in args:
                    plan = next(str(arg).split('=', 1)[1] for arg in args if str(arg).startswith('--use-list='))
                    content = Path(plan).read_text()
                    self.assertNotIn('SCHEMA - public', content)
                    self.assertIn('TABLE public clients', content)
                return b'1; 2615 2200 SCHEMA - public owner\n2; 1259 12 TABLE public clients owner\n'
            with mock.patch.object(pg, 'run_tool', side_effect=tool), mock.patch.object(pg, 'connect', return_value=connection(conn)), mock.patch.object(pg, 'database_identity', return_value='different'), mock.patch.object(pg, 'summary', return_value=evidence), mock.patch.object(pg, 'validate_sequences'):
                result = pg.restore(snapshot, 'postgresql://unused.invalid/test')
            self.assertTrue(result['logicalRecoveryVerified'])
            self.assertFalse(any('DROP' in item for item in conn.statements))
            self.assertTrue(any('--single-transaction' in args and '--exit-on-error' in args for args in calls))
            self.assertFalse(any('--clean' in args or '--create' in args for args in calls))

    def test_symlink_archive_and_manifest_are_rejected(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            alias = f.root / 'alias.pgdump'
            alias.symlink_to(snapshot)
            with self.assertRaises(recovery.RecoveryError): pg.verify(alias)
            manifest = recovery.manifest_path(snapshot)
            content = manifest.read_bytes()
            manifest.unlink()
            destination = f.root / 'other.json'
            destination.write_bytes(content)
            manifest.symlink_to(destination)
            with self.assertRaises(recovery.RecoveryError): pg.verify(snapshot)

    def test_overlapping_retention_never_deletes_backups(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            with recovery.manager_lock(f.root), self.assertRaises(recovery.RecoveryError):
                recovery.retain(f.root)
            self.assertTrue(snapshot.exists())

    def test_canonical_binary_hash_distinguishes_zero_bytes_and_text(self):
        samples = [b'', b'\x00', b'\xff', '00', None]
        encoded = [json.dumps([item], default=pg.canonical) for item in samples]
        self.assertEqual(len(set(encoded)), len(samples))

    def test_postgres_health_reports_failure_without_connection_string(self):
        with tempfile.TemporaryDirectory() as work, mock.patch.object(pg, 'connect', side_effect=RuntimeError('secret connection string')):
            problems = operations.health('postgresql://private:secret@example.invalid/crm', work, False)
        self.assertIn('database:health-query-failed', problems)
        self.assertNotIn('secret', json.dumps(problems))
        self.assertFalse(any(item.startswith('database-storage') for item in problems))

    def test_offsite_restore_detects_tampering_and_never_prunes_on_failure(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            calls = []
            def runner(args):
                calls.append(args)
                if args[0] == 'backup':
                    return json.dumps({'message_type': 'summary', 'snapshot_id': 'a' * 64})
                if args[0] == 'restore':
                    target = Path(args[args.index('--target') + 1]) / str(snapshot).lstrip('/')
                    target.parent.mkdir(parents=True)
                    target.write_bytes(b'corrupt')
                    shutil.copyfile(recovery.manifest_path(snapshot), recovery.manifest_path(target))
                    return ''
                self.fail('Retention must not run after failed off-site validation')
            with self.assertRaises(recovery.RecoveryError): operations.offsite(snapshot, f.root, runner)
            self.assertFalse((f.root / 'offsite-status.json').exists())

    def test_retention_preserves_last_drilled_recovery_point_when_newer_drills_fail(self):
        with ArchiveFixture() as f:
            good = f.snapshot(age=40)
            newer = f.snapshot(age=0)
            recovery.atomic_json(f.root / 'restore-drill-status.json', {'snapshot': good.name})
            recovery.retain(f.root, latest=1, daily=0, weekly=0, monthly=0)
            self.assertTrue(good.exists())
            self.assertTrue(newer.exists())

    def test_connection_failure_cleans_unpublished_dump_and_never_marks_success(self):
        with tempfile.TemporaryDirectory() as work, mock.patch.object(pg, 'connect', side_effect=TimeoutError('test')):
            with self.assertRaises(TimeoutError):
                pg.backup_once('postgresql://unused.invalid/crm', work)
            self.assertFalse(list(Path(work).glob('.postgres-copy-*')))
            self.assertFalse(list(Path(work).glob('*.pgdump')))
            self.assertFalse((Path(work) / 'backup-status.json').exists())

    def test_sqlite_release_preparation_refuses_postgres_to_avoid_wrong_database_backup(self):
        import prepare_release
        runner = mock.Mock()
        with mock.patch.dict(os.environ, {'DATABASE_URL': 'postgresql://unused.invalid/crm'}), self.assertRaises(ValueError):
            prepare_release.prepare('/unused/binary', '/unused/sqlite', '/unused/backups', [], runner=runner)
        runner.assert_not_called()

    def test_private_manifest_permissions_and_backend_dispatch(self):
        with ArchiveFixture() as f:
            snapshot = f.snapshot()
            self.assertEqual(recovery.verify(snapshot)['engine'], 'postgresql')
            self.assertEqual(recovery.manifest_path(snapshot).stat().st_mode & 0o077, 0)
            self.assertEqual(recovery.database_summary(snapshot)['tableCounts']['documents'], 1)


# A reproducible property corpus: 1,000 independently named cases across five
# failure families. Archive-format/SQL behavior is tested by the real PG suite,
# not claimed by these controlled-tool unit/property checks.
def property_case(family, seed):
    rng = random.Random(129705 + seed)
    with ArchiveFixture() as f:
        if family == 'binary-corruption':
            payload = rng.randbytes(rng.randint(1, 1024))
            snapshot = f.snapshot(payload)
            corrupted = bytearray(payload)
            corrupted[rng.randrange(len(payload))] ^= rng.randint(1, 255)
            snapshot.write_bytes(corrupted)
            with unittest.TestCase().assertRaises(recovery.RecoveryError): pg.verify(snapshot)
        elif family == 'manifest-binding':
            snapshot = f.snapshot(rng.randbytes(rng.randint(1, 256)))
            manifest = recovery.manifest_path(snapshot)
            metadata = json.loads(manifest.read_text())
            key, value = rng.choice([('file', 'wrong.pgdump'), ('format', 1), ('engine', 'sqlite'), ('bytes', -1), ('sha256', 'invalid'), ('sourceIdentity', '')])
            metadata[key] = value
            manifest.write_text(json.dumps(metadata))
            with unittest.TestCase().assertRaises(recovery.RecoveryError): pg.verify(snapshot)
        elif family == 'retention-invariants':
            ages = sorted(rng.sample(range(1, 400), 12))
            snapshots = [f.snapshot(age=age) for age in ages]
            latest = rng.randint(1, 4)
            recovery.retain(f.root, latest=latest, daily=rng.randint(0, 5), weekly=rng.randint(0, 4), monthly=rng.randint(0, 3))
            unittest.TestCase().assertTrue(all(path.exists() for path in snapshots[:latest]), 'Newest recoverable backups were pruned')
            for path in f.root.glob('*.pgdump'):
                pg.verify(path)
                unittest.TestCase().assertTrue(recovery.manifest_path(path).is_file(), 'Retained archive lost its manifest')
        elif family == 'production-tls':
            unsafe = rng.choice(['disable', 'allow', 'prefer', '', 'unknown'])
            suffix = rng.choice(['', '&application_name=backup', '&sslmode=require'])
            with unittest.TestCase().assertRaises(ValueError):
                database.secure_url('postgresql://fixture:private@example.invalid/crm?sslmode=' + unsafe + suffix, True)
        elif family == 'wrong-restore-target':
            snapshot = f.snapshot(rng.randbytes(20))
            same = bool(rng.randrange(2))
            conn = FakeConnection(name='production_' + str(seed), objects=0 if same else rng.randint(1, 99))
            with mock.patch.object(pg, 'connect', return_value=connection(conn)), mock.patch.object(pg, 'database_identity', return_value='a' * 64 if same else 'different'), unittest.TestCase().assertRaises(recovery.RecoveryError):
                pg.restore(snapshot, 'postgresql://fixture.invalid/crm', cleanup=True)
            unittest.TestCase().assertFalse(any('DROP' in text for text in conn.statements), 'Unsafe target cleanup')


def load_tests(loader, tests, _pattern):
    suite = unittest.TestSuite([tests])
    for family in ['binary-corruption', 'manifest-binding', 'retention-invariants', 'production-tls', 'wrong-restore-target']:
        for seed in range(200):
            suite.addTest(unittest.FunctionTestCase(lambda family=family, seed=seed: property_case(family, seed),
                                                  description=f'postgres-recovery/property/{family}/{seed:03d}'))
    return suite


if __name__ == '__main__':
    unittest.main()
