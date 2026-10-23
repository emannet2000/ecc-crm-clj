#!/usr/bin/env python3
"""Smoke-test the actual Render image using an isolated container and SQLite file.

The Docker build runs the PostgreSQL workflow/restore suites. This final-image
check verifies release assets, native runtime libraries, production startup,
migration replay, HTTP readiness and restart persistence. No hosted service is used.
"""
import argparse
import http.client
import json
import subprocess
import time
import uuid


def docker(*args):
    return subprocess.check_output(['docker', *args], text=True, timeout=120).strip()


def request(port, path, method='GET', body=None, token=None):
    connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
    try:
        headers = {'Content-Type': 'application/json'}
        if token:
            headers['Authorization'] = 'Bearer ' + token
        connection.request(method, path, json.dumps(body) if body is not None else None, headers)
        response = connection.getresponse()
        return response.status, {key.lower(): value for key, value in response.getheaders()}, response.read()
    finally:
        connection.close()


def ready(port):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        try:
            status, _, body = request(port, '/api/ready')
            if status == 200 and json.loads(body).get('status') == 'ready':
                return
        except (OSError, ValueError, http.client.HTTPException):
            pass
        time.sleep(1)
    raise RuntimeError('Render image did not become ready')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', required=True)
    args = parser.parse_args()
    user = docker('image', 'inspect', '--format', '{{.Config.User}}', args.image)
    if user in ('', 'root', '0', '0:0'):
        raise RuntimeError('Runtime image must use an unprivileged user')
    name = 'ecc-render-smoke-' + uuid.uuid4().hex
    try:
        docker('run', '-d', '--name', name, '-p', '127.0.0.1::4000',
               '-e', 'DATABASE_PATH=/tmp/ecc-smoke.sqlite3',
               '-e', 'JWT_SECRET=isolated-container-test-secret-at-least-32-bytes',
               '-e', 'PUBLIC_URL=https://crm.example.test',
               '--entrypoint', '/bin/sh', args.image, '-c',
               'ecc-crm-api migrate && exec python3 scripts/log_runtime.py -- ecc-crm-api')
        port = int(docker('port', name, '4000/tcp').rsplit(':', 1)[1])
        ready(port)
        status, headers, body = request(port, '/')
        if status != 200 or b'<html' not in body.lower() or headers.get('x-content-type-options') != 'nosniff':
            raise RuntimeError('Production frontend or security headers unavailable')
        if request(port, '/api/clients')[0] != 401:
            raise RuntimeError('Anonymous client access must be rejected')
        if request(port, '/main.js')[0] != 200:
            raise RuntimeError('Compiled frontend unavailable')
        # An administrative write must survive restarting the same container.
        docker('exec', '-e', 'ECC_USER_EMAIL=smoke@example.invalid',
               '-e', 'ECC_USER_NAME=Smoke test', '-e', 'ECC_USER_ROLE=admin',
               '-e', 'ECC_USER_PASSWORD=isolated-smoke-password-123',
               name, 'ecc-crm-api', 'create-user-env')
        docker('restart', name)
        port = int(docker('port', name, '4000/tcp').rsplit(':', 1)[1])
        ready(port)
        status, _, body = request(port, '/api/auth/login', 'POST',
                                 {'lrEmail': 'smoke@example.invalid', 'lrPassword': 'isolated-smoke-password-123'})
        if status != 200 or json.loads(body).get('user', {}).get('email') != 'smoke@example.invalid':
            raise RuntimeError('Account did not survive restart and migration replay')
        print('Render image: production startup, assets, authorization, migration replay and restart persistence passed')
    except Exception:
        result = subprocess.run(['docker', 'logs', name], check=False, capture_output=True, text=True, timeout=15)
        print(result.stdout[-12000:])
        raise
    finally:
        subprocess.run(['docker', 'rm', '-f', name], check=False, capture_output=True, timeout=30)


if __name__ == '__main__':
    main()
