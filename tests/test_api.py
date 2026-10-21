"""Integration tests against the real API and an isolated SQLite file.
ECC_RUN_HTTP_TESTS=1 ECC_API_BINARY=/path/to/ecc-crm-api python3 -m unittest discover -s tests -v
"""
from contextlib import closing
import concurrent.futures
import json
import os
import pathlib
import re
import socket
import sqlite3
import tempfile
import subprocess
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]


class Client:
    def __init__(self, base, token=None):
        self.base, self.token = base, token

    def request(self, method, path, body=None, headers=None):
        hdr = dict(headers or {})
        if self.token:
            hdr['Authorization'] = 'Bearer ' + self.token
        if isinstance(body, dict):
            body = json.dumps(body).encode()
            hdr['Content-Type'] = 'application/json'
        req = urllib.request.Request(self.base + path, body, hdr, method=method)
        try:
            response = urllib.request.urlopen(req, timeout=20)
        except urllib.error.HTTPError as error:
            response = error
        raw = response.read()
        try:
            data = json.loads(raw)
        except ValueError:
            data = raw
        return response.status, data, response.headers


@unittest.skipUnless(os.environ.get('ECC_RUN_HTTP_TESTS'), 'Set ECC_RUN_HTTP_TESTS=1 to run network-based API tests')
class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix='ecc-api-')
        cls.test_db = str(pathlib.Path(cls.temporary.name) / 'test.sqlite3')
        cls.env = dict(os.environ, DATABASE_PATH=cls.test_db, APP_ENV='development', SEED_DEMO='false', WEB_DIST=str(ROOT / 'web/dist'), JWT_SECRET='integration-test-secret-32-bytes-only', ASSIGNED_ONLY='true')
        cls.binary = os.environ.get('ECC_API_BINARY')
        if not cls.binary:
            cls.binary = subprocess.check_output(['cabal', 'list-bin', 'exe:ecc-crm-api'], cwd=ROOT / 'api', text=True).strip()
        subprocess.run([cls.binary, 'adduser', 'admin@test.example', 'Test Admin', 'admin', 'correct-password-123'], env=cls.env, cwd=ROOT / 'api', check=True, stdout=subprocess.DEVNULL)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            cls.port = sock.getsockname()[1]
        cls.env['PORT'] = str(cls.port)
        cls.env['PUBLIC_URL'] = 'http://127.0.0.1:' + str(cls.port)
        cls.log = open('/tmp/ecc-crm-integration.log', 'w')
        cls.process = subprocess.Popen([cls.binary], cwd=ROOT / 'api', env=cls.env, stdout=cls.log, stderr=cls.log)
        cls.public = Client(cls.env['PUBLIC_URL'])
        for _ in range(100):
            if cls.process.poll() is not None:
                raise RuntimeError('API exited; see /tmp/ecc-crm-integration.log')
            try:
                if cls.public.request('GET', '/api/ready')[0] == 200:
                    break
            except OSError:
                pass
            time.sleep(.1)
        else:
            raise RuntimeError('API readiness timed out')
        status, login, _ = cls.public.request('POST', '/api/auth/login', {'lrEmail': 'admin@test.example', 'lrPassword': 'correct-password-123'})
        assert status == 200, login
        cls.admin = Client(cls.env['PUBLIC_URL'], login['token'])
        cls.users = {}
        for role in ('viewer', 'consultant'):
            status, user, _ = cls.admin.request('POST', '/api/users', {'nuEmail': role + '@test.example', 'nuName': role.title(), 'nuPassword': 'correct-password-123', 'nuRole': role})
            assert status == 200, user
            status, session, _ = cls.public.request('POST', '/api/auth/login', {'lrEmail': role + '@test.example', 'lrPassword': 'correct-password-123'})
            assert status == 200, session
            cls.users[role] = (user, Client(cls.env['PUBLIC_URL'], session['token']))

    @classmethod
    def sql_raw(cls, sql, scoped=False):
        with closing(sqlite3.connect(cls.test_db)) as conn, conn:
            if sql.lstrip().upper().startswith('SELECT'):
                return '\n'.join('|'.join(str(value) for value in row) for row in conn.execute(sql))
            conn.executescript(sql)
            return ''


    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        cls.process.wait(timeout=10)
        cls.log.close()
        cls.temporary.cleanup()

    def lead(self, **values):
        body = dict(nlFullName='Integration ' + uuid.uuid4().hex[:8], nlService='Student Visa', nlDestination='Canada')
        body.update(values)
        status, lead, _ = self.admin.request('POST', '/api/leads', body)
        self.assertEqual(status, 200, lead)
        return lead

    def test_conversion_preserves_documents_tasks_notes_and_retries(self):
        lead = self.lead()
        lid = lead['leadId']
        self.admin.request('POST', f'/api/leads/{lid}/notes', {'nrNote': 'Keep this history'})
        status, task, _ = self.admin.request('POST', '/api/tasks', {'ntLeadId': lid, 'ntTitle': 'Follow through'})
        self.assertEqual(status, 200, task)
        boundary = 'crm-test-boundary'
        upload = (f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="proof.txt"\r\nContent-Type: text/plain\r\n\r\nkeep these bytes\r\n--{boundary}--\r\n').encode()
        status, detail, _ = self.admin.request('POST', f'/api/leads/{lid}/documents', upload, {'Content-Type': 'multipart/form-data; boundary=' + boundary})
        self.assertEqual(status, 200, detail)
        did = detail['documents'][0]['id']
        status, client, _ = self.admin.request('POST', f'/api/leads/{lid}/convert')
        self.assertEqual(status, 200, client)
        cid = client['id']
        status, detail, _ = self.admin.request('GET', f'/api/clients/{cid}')
        self.assertEqual(status, 200, detail)
        self.assertEqual(detail['documents'][0]['id'], did)
        self.assertEqual(detail['tasks'][0]['clientId'], cid)
        self.assertTrue(any('Keep this history' in (a['description'] or '') for a in detail['activities']))
        self.assertEqual(self.admin.request('GET', f'/api/documents/{did}/download')[0], 423)
        # The worker/protocol are tested separately; simulate a clean verdict here.
        self.sql_raw(f"UPDATE documents SET scan_status='Clean' WHERE id={int(did)}")
        self.assertEqual(self.admin.request('GET', f'/api/documents/{did}/download')[1], b'keep these bytes')
        self.assertEqual(self.admin.request('POST', f'/api/leads/{lid}/convert')[1]['id'], cid)
        self.assertEqual(self.admin.request('GET', f'/api/leads/{lid}')[0], 404)

    def test_conversion_failure_rolls_back_every_write(self):
        lead = self.lead(nlFullName='Rollback test')
        self.sql_raw("CREATE TRIGGER fail_case_test BEFORE INSERT ON cases BEGIN SELECT RAISE(ABORT,'simulated failure'); END;", True)
        try:
            status, _, _ = self.admin.request('POST', f"/api/leads/{lead['leadId']}/convert")
            self.assertGreaterEqual(status, 400)
        finally:
            self.sql_raw('DROP TRIGGER fail_case_test;', True)
        self.assertEqual(self.admin.request('GET', f"/api/leads/{lead['leadId']}")[0], 200)
        self.assertEqual(self.sql_raw("SELECT count(*) FROM clients WHERE full_name='Rollback test'", True), '0')

    def test_numbering_concurrent_and_never_reused(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            leads = list(pool.map(lambda _: self.lead(), range(12)))
        self.assertEqual(len({lead['leadNumber'] for lead in leads}), 12)
        highest = max(leads, key=lambda l: int(l['leadNumber'].split('-')[-1]))
        self.admin.request('DELETE', '/api/leads/' + str(highest['leadId']))
        fresh = self.lead()
        self.assertGreater(int(fresh['leadNumber'].split('-')[-1]), int(highest['leadNumber'].split('-')[-1]))

    def test_roles_scope_validation_and_archive(self):
        lead = self.lead()
        path = '/api/leads/' + str(lead['leadId'])
        viewer = self.users['viewer'][1]
        consultant = self.users['consultant'][1]
        self.assertEqual(viewer.request('POST', '/api/leads', {'nlFullName': 'Forbidden'})[0], 403)
        self.assertEqual(consultant.request('GET', path)[0], 404)
        self.assertEqual(consultant.request('PATCH', path, {'ulFullName': 'Forbidden'})[0], 404)
        self.assertEqual(self.admin.request('POST', '/api/leads', {'nlFullName': '   '})[0], 400)
        self.assertEqual(self.admin.request('PATCH', path, {'ulStage': 'Made up'})[0], 400)
        self.assertEqual(self.admin.request('PATCH', path, {'ulConsultantId': 999999})[0], 400)
        self.assertEqual(self.admin.request('DELETE', path)[0], 200)
        self.assertEqual(self.admin.request('GET', path)[0], 404)
        self.assertTrue(any(r['id'] == lead['leadId'] for r in self.admin.request('GET', '/api/archive')[1]))
        self.assertEqual(self.admin.request('POST', path + '/restore')[0], 200)
        self.assertEqual(self.admin.request('GET', path)[0], 200)

    def test_cookie_logout_revokes_token_and_query_tokens_are_rejected(self):
        status, login, headers = self.public.request('POST', '/api/auth/login', {'lrEmail': 'admin@test.example', 'lrPassword': 'correct-password-123'})
        self.assertEqual(status, 200)
        cookie = headers['Set-Cookie']
        self.assertIn('HttpOnly', cookie)
        self.assertIn('SameSite=Strict', cookie)
        token = login['token']
        session = Client(self.env['PUBLIC_URL'], token)
        self.assertEqual(self.public.request('GET', '/api/auth/me', headers={'Cookie': cookie.split(';')[0]})[0], 200)
        self.assertEqual(self.public.request('GET', '/api/export/leads.csv?token=' + token)[0], 401)
        self.assertEqual(session.request('POST', '/api/auth/logout')[0], 200)
        self.assertEqual(session.request('GET', '/api/auth/me')[0], 401)

    def test_recovery_is_single_use_and_revokes_sessions(self):
        address = 'recover@test.example'
        status, user, _ = self.admin.request('POST', '/api/users', {'nuEmail': address, 'nuName': 'Recovery', 'nuRole': 'consultant', 'nuPassword': ''})
        self.assertEqual(status, 200, user)
        body = self.sql_raw("SELECT body FROM mail_outbox WHERE recipient='recover@test.example' ORDER BY id DESC LIMIT 1", True)
        token = re.search(r'\?reset=([\w-]+)', body).group(1)
        self.assertEqual(self.public.request('POST', '/api/auth/reset', {'token': token, 'password': 'new-password-12345'})[0], 200)
        self.assertEqual(self.public.request('POST', '/api/auth/reset', {'token': token, 'password': 'new-password-12345'})[0], 400)
        status, login, _ = self.public.request('POST', '/api/auth/login', {'lrEmail': address, 'lrPassword': 'new-password-12345'})
        self.assertEqual(status, 200, login)
        session = Client(self.env['PUBLIC_URL'], login['token'])
        self.assertEqual(session.request('PUT', '/api/auth/password', {'pcCurrent': 'new-password-12345', 'pcNew': 'replacement-password-123'})[0], 200)
        self.assertEqual(session.request('GET', '/api/auth/me')[0], 401)

    def test_reminders_duplicates_pagination_audit_and_headers(self):
        lead = self.lead(nlEmail='duplicate@test.example', nlNextFollowup='2020-01-01')
        self.lead(nlEmail='duplicate@test.example')
        status, reminders, _ = self.admin.request('GET', '/api/reminders')
        self.assertEqual(status, 200)
        self.assertTrue(any(r['id'] == lead['leadId'] and not r['read'] for r in reminders))
        self.assertEqual(self.admin.request('POST', f"/api/reminders/followup/{lead['leadId']}/read")[0], 200)
        self.assertTrue(any(r['id'] == lead['leadId'] and r['read'] for r in self.admin.request('GET', '/api/reminders')[1]))
        self.assertTrue(any(d['value'] == 'duplicate@test.example' for d in self.admin.request('GET', '/api/duplicates')[1]))
        page = self.admin.request('GET', '/api/leads?limit=1&q=Integration')[1]
        self.assertEqual(len(page), 1)
        audit = self.admin.request('GET', '/api/audit')[1]
        self.assertTrue(any(a['entityType'] == 'lead' and a['action'] == 'created' for a in audit))
        self.assertNotIn('password_hash', json.dumps(audit))
        self.assertNotIn('correct-password', json.dumps(audit))
        status, _, headers = self.public.request('GET', '/api/health')
        self.assertEqual(status, 200)
        self.assertEqual(headers['X-Content-Type-Options'], 'nosniff')
        self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
        self.assertEqual(self.admin.request('POST', '/api/auth/logout', headers={'Origin': 'https://evil.example'})[0], 403)

    def test_rate_limit_survives_new_connections(self):
        # A separate category avoids consuming login attempts needed by other tests.
        for _ in range(20):
            self.public.request('POST', '/api/auth/recover', {'email': 'unknown@test.example'})
        self.assertEqual(self.public.request('POST', '/api/auth/recover', {'email': 'unknown@test.example'})[0], 429)
