import json
from contextlib import closing
import os
from pathlib import Path
import sqlite3
import tempfile
import tarfile
import unittest
from unittest import mock
import release
import prepare_release
import operations


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='ecc-release-test-')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.web=self.root/'web';self.web.mkdir()
        self.binary=self.root/'api';self.binary.write_bytes(b'fake test binary')
        for name in release.ASSETS:
            file=self.web/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('asset '+name)

    def test_rebuilding_invalidates_quality_gate_evidence(self):
        release.build(self.web)
        self.assertFalse(json.loads((self.web/'release.json').read_text())['verified'])
        release.seal(self.web,self.binary)
        sealed=json.loads((self.web/'release.json').read_text())
        self.assertTrue(sealed['verified'])
        self.assertEqual(sealed['backend'],release.digest(self.binary))
        release.build(self.web)
        self.assertFalse(json.loads((self.web/'release.json').read_text())['verified'])

    def test_package_requires_sealed_bytes_and_excludes_runtime_secrets(self):
        release.build(self.web)
        output=self.root/'release.tar.gz'
        with self.assertRaises(ValueError):release.package(self.web,self.binary,output)
        release.seal(self.web,self.binary)
        release.package(self.web,self.binary,output)
        with tarfile.open(output) as archive:
            names=archive.getnames()
            self.assertIn('ecc-crm-api',names)
            self.assertIn('web/dist/release.json',names)
            self.assertEqual(archive.getmember('ecc-crm-api').mode,0o755)
            self.assertFalse(any(name.endswith(('.sqlite3','.env')) for name in names))
        with self.assertRaises(FileExistsError):release.package(self.web,self.binary,output)

    def test_asset_change_during_tests_prevents_sealing(self):
        release.build(self.web)
        (self.web/'main.js').write_text('changed while testing')
        with self.assertRaises(ValueError):release.seal(self.web,self.binary)
        self.assertFalse(json.loads((self.web/'release.json').read_text())['verified'])

    def test_prepare_checks_stopped_writers_and_backup_before_migrating(self):
        database=self.root/'data.sqlite3'
        with closing(sqlite3.connect(database)) as conn, conn:conn.execute('CREATE TABLE example(id INTEGER)')
        events=[]
        def run(arguments):
            events.append(arguments[-1])
            if arguments[0]=='timedatectl':return 'yes'
            return 'loaded' if '--property=LoadState' in arguments else 'inactive'
        def backup(*args,**kwargs):
            self.assertTrue(kwargs['remote']);events.append('verified-remote-restore')
        with mock.patch.dict(os.environ,{'APP_ENV':'production','DATABASE_PATH':str(database)}):
            result=prepare_release.prepare(self.binary,database,self.root/'backups',['ecc-api.service'],run,backup)
        self.assertEqual(events,['verify-release','--value','ecc-api.service','ecc-api.service','verified-remote-restore','migrate'])
        self.assertFalse(result['servicesRestarted'])

    def test_active_writers_or_failed_backup_prevent_migration(self):
        database=self.root/'data.sqlite3'
        with closing(sqlite3.connect(database)) as conn, conn:conn.execute('CREATE TABLE example(id INTEGER)')
        for active in [True,False]:
            events=[]
            def run(arguments):
                events.append(arguments[-1])
                if arguments[0]=='timedatectl':return 'yes'
                return 'loaded' if '--property=LoadState' in arguments else 'active' if active else 'inactive'
            def failed_backup(*args,**kwargs):raise ValueError('Remote verification failed')
            with mock.patch.dict(os.environ,{'APP_ENV':'production','DATABASE_PATH':str(database)}):
                with self.assertRaises(ValueError):prepare_release.prepare(self.binary,database,self.root/'backups',['ecc-api.service'],run,failed_backup)
            self.assertNotIn('migrate',events)

    def test_unsynchronized_clock_prevents_migration(self):
        database=self.root/'data.sqlite3'
        with closing(sqlite3.connect(database)) as conn, conn:conn.execute('CREATE TABLE example(id INTEGER)')
        calls=[]
        def run(arguments):
            calls.append(arguments)
            return 'no' if arguments[0]=='timedatectl' else ''
        backup=mock.Mock()
        with mock.patch.dict(os.environ,{'APP_ENV':'production','DATABASE_PATH':str(database)}):
            with self.assertRaises(ValueError):prepare_release.prepare(self.binary,database,self.root/'backups',['ecc-api.service'],run,backup)
        backup.assert_not_called()
        self.assertFalse(any(command[-1]=='migrate' for command in calls))


class ReadinessTests(unittest.TestCase):
    def test_api_health_checks_contract_and_rejects_bad_urls(self):
        with mock.patch.object(operations.urllib.request,'build_opener') as factory:
            response=factory.return_value.open.return_value.__enter__.return_value
            response.status=200
            response.read.return_value=json.dumps({'status':'ready','contract':release.contract()}).encode()
            self.assertIsNone(operations.readiness_problem('https://crm.test/api/ready'))
            response.read.return_value=b'{"status":"ready","contract":"old"}'
            self.assertEqual(operations.readiness_problem('https://crm.test/api/ready'),'api:incompatible-or-not-ready')
            factory.reset_mock()
            self.assertEqual(operations.readiness_problem('http://crm.test/api/ready'),'api:invalid-health-url')
            factory.assert_not_called()

    def test_api_timeout_becomes_an_alert(self):
        with mock.patch.object(operations.urllib.request,'build_opener') as factory:
            factory.return_value.open.side_effect=TimeoutError('not logged')
            self.assertEqual(operations.readiness_problem('https://crm.test/api/ready'),'api:unavailable')
