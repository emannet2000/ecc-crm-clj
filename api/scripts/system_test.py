#!/usr/bin/env python3
"""Real process/HTTP tests. All databases, accounts and ports are disposable."""
from contextlib import closing
import concurrent.futures
import gzip
import http.client
import json
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import tempfile
import time
import unittest
import recovery
import release

ROOT = Path(__file__).resolve().parents[1]
BINARY = os.environ.get('ECC_API_BIN')
if not BINARY:
    raise SystemExit('Set ECC_API_BIN to the output of cabal list-bin exe:ecc-crm-api')


def environment(database, **overrides):
    env = os.environ.copy()
    for key in ('APP_ENV', 'DATABASE_URL', 'DATABASE_PATH', 'JWT_SECRET', 'PUBLIC_URL', 'SEED_DEMO',
                'DB_POOL_SIZE', 'PORT', 'ASSIGNED_ONLY', 'REQUIRE_ADMIN_MFA'):
        env.pop(key, None)
    env.update(DATABASE_PATH=str(database), APP_ENV='production',
               JWT_SECRET='system-test-secret-is-at-least-32-bytes',
               PUBLIC_URL='https://crm.example.test', SEED_DEMO='false',
               WEB_DIST=str(ROOT / 'web/dist'), GHCRTS='-N2')
    env.update(overrides)
    return env


class StartupTests(unittest.TestCase):
    def test_production_configuration_boundaries(self):
        with tempfile.TemporaryDirectory(prefix='ecc-startup-') as directory:
            for key, value in [('JWT_SECRET', ''), ('JWT_SECRET', 'short'),
                               ('JWT_SECRET', 'local-development-secret-only-0000'),
                               ('DATABASE_PATH', ':memory:'), ('DATABASE_PATH', ''),
                               ('PUBLIC_URL', 'http://insecure.test'),
                               ('SEED_DEMO', 'true'), ('PORT', '0'), ('PORT', '65536'),
                               ('PORT', 'abc'), ('DB_POOL_SIZE', '0'), ('DB_POOL_SIZE', '17')]:
                with self.subTest(key=key, value=value):
                    db = Path(directory) / 'invalid.sqlite3'
                    result = subprocess.run([BINARY, 'migrate'], cwd=ROOT,
                                            env=environment(db, **{key: value}),
                                            capture_output=True, timeout=20)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(db.exists(), 'Invalid config must fail before touching storage')

    def test_unverified_production_release_fails_before_touching_storage(self):
        with tempfile.TemporaryDirectory(prefix='ecc-unverified-release-') as directory:
            db=Path(directory)/'untouched.sqlite3'
            web=Path(directory)/'web';web.mkdir()
            (web/'index.html').write_text('<html></html>')
            (web/'release.json').write_text(json.dumps({'contract':release.contract(),'verified':False,'backend':'','assets':{},'migrations':{}}))
            result=subprocess.run([BINARY],cwd=ROOT,env=environment(db,WEB_DIST=str(web)),capture_output=True,timeout=20)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(db.exists())

    def test_unknown_command_does_not_create_or_migrate_storage(self):
        with tempfile.TemporaryDirectory(prefix='ecc-command-') as directory:
            db=Path(directory)/'untouched.sqlite3'
            result=subprocess.run([BINARY,'unknown-command'],cwd=ROOT,env=environment(db),capture_output=True,timeout=20)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(db.exists())

    def test_migration_replay_and_backup_restore(self):
        with tempfile.TemporaryDirectory(prefix='ecc-backup-') as directory:
            db = Path(directory) / 'original.sqlite3'
            for _ in range(2):
                result = subprocess.run([BINARY, 'migrate'], cwd=ROOT, env=environment(db),
                                        capture_output=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stderr.decode())
            with closing(sqlite3.connect(db)) as source:
                versions = source.execute('SELECT count(*) FROM schema_migrations').fetchone()[0]
                self.assertEqual(versions, len(list((ROOT / 'migrations').glob('*.sql'))))
                source.execute("INSERT INTO clients(client_number,full_name) VALUES ('RESTORE-1','Restore 中')")
                source.commit()
            snapshot = recovery.backup_once(db, Path(directory) / 'backups')
            evidence = recovery.drill(snapshot)
            self.assertEqual(evidence['tableCounts']['clients'], 1)
            target = Path(directory) / 'restored.sqlite3'
            recovery.restore(snapshot, target)
            with closing(sqlite3.connect(target)) as restored:
                self.assertEqual(restored.execute('PRAGMA integrity_check').fetchone(), ('ok',))
                self.assertEqual(restored.execute('PRAGMA foreign_key_check').fetchall(), [])
                self.assertEqual(restored.execute('SELECT full_name FROM clients').fetchall(), [('Restore 中',)])



class LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='ecc-http-')
        cls.addClassCleanup(cls.directory.cleanup)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            cls.port = sock.getsockname()[1]
        cls.log = tempfile.TemporaryFile()
        cls.addClassCleanup(cls.log.close)
        cls.process = subprocess.Popen([BINARY], cwd=ROOT, stdout=cls.log, stderr=cls.log,
            env=environment(Path(cls.directory.name) / 'live.sqlite3', APP_ENV='development',
                            PORT=str(cls.port), SEED_DEMO='true', ASSIGNED_ONLY='true',
                            DB_POOL_SIZE='4'))  # Admit the eight concurrent read-test requests.
        def stop():
            cls.process.terminate()
            try:
                cls.process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                cls.process.kill()
                cls.process.wait(timeout=10)
        cls.addClassCleanup(stop)
        for _ in range(150):
            if cls.process.poll() is not None:
                cls.log.seek(0)
                raise RuntimeError(cls.log.read().decode())
            try:
                if cls.request('GET', '/api/health')[0] == 200:
                    break
            except OSError:
                pass
            time.sleep(0.1)
        else:
            raise RuntimeError('Server did not become healthy')
        status, _, body = cls.request('POST', '/api/auth/login',
                                     {'lrEmail': 'admin@ecc.com', 'lrPassword': 'password123'})
        if status != 200:
            raise RuntimeError(f'Fixture login failed: {status}: {body}')
        cls.token = json.loads(body)['token']

    @classmethod
    def request(cls, method, path, body=None, headers=None, token=None):
        conn = http.client.HTTPConnection('127.0.0.1', cls.port, timeout=15)
        request_headers = {'Content-Type': 'application/json', **(headers or {})}
        if token:
            request_headers['Authorization'] = 'Bearer ' + token
        try:
            conn.request(method, path, body=None if body is None else json.dumps(body), headers=request_headers)
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            conn.close()

    def test_anonymous_private_routes_are_denied(self):
        for path in ['/api/clients', '/api/leads', '/api/tasks', '/api/stats', '/api/users',
                     '/api/audit', '/api/clients/1', '/api/clients/1/profile',
                     '/api/documents/1/download', '/api/workspace/applications']:
            with self.subTest(path=path):
                self.assertEqual(self.request('GET', path)[0], 401)

    def test_cross_site_writes_are_denied(self):
        for headers in [{'Origin': 'https://attacker.test'}, {'Sec-Fetch-Site': 'cross-site'}]:
            with self.subTest(headers=headers):
                status, _, _ = self.request('POST', '/api/clients', {'ncFullName': 'Blocked'}, headers, self.token)
                self.assertEqual(status, 403)

    def test_gzip_asset_is_lossless_and_security_headers_survive(self):
        status, headers, body = self.request('GET', '/main.js', headers={'Accept-Encoding': 'gzip'})
        self.assertEqual(status, 200)
        self.assertEqual(headers.get('Content-Encoding'), 'gzip')
        self.assertEqual(gzip.decompress(body), (ROOT / 'web/dist/main.js').read_bytes())
        self.assertEqual(headers.get('X-Content-Type-Options'), 'nosniff')
        self.assertLess(len(body), (ROOT / 'web/dist/main.js').stat().st_size // 2)

    def test_pagination_and_search_boundaries(self):
        for query in ['limit=0', 'limit=-1', 'limit=999999', 'offset=-1',
                      'offset=999999', 'limit=nope', 'q=%27%20OR%201%3D1--']:
            with self.subTest(query=query):
                status, _, body = self.request('GET', '/api/clients?' + query, token=self.token)
                self.assertEqual(status, 200)
                self.assertLessEqual(len(json.loads(body)), 200)
        status, _, body = self.request('GET', '/api/clients?q=%27%20OR%201%3D1--', token=self.token)
        self.assertEqual(json.loads(body), [])

    def test_concurrent_authenticated_reads(self):
        paths = ['/api/clients', '/api/leads', '/api/stats', '/api/tasks'] * 5
        with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
            results = list(pool.map(lambda path: self.request('GET', path, token=self.token), paths))
        self.assertTrue(all(status == 200 for status, _, _ in results))
        for _, _, body in results:
            json.loads(body)

    def test_unknown_assets_and_missing_records(self):
        for path in ['/missing.js', '/%2e%2e/AGENTS.md', '/api/clients/9999999']:
            with self.subTest(path=path):
                self.assertEqual(self.request('GET', path, token=self.token)[0], 404)


if __name__ == '__main__':
    unittest.main(verbosity=2)
