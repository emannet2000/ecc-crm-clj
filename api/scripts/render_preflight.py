#!/usr/bin/env python3
"""Read-only Render setup checks. Never prints credentials or changes data."""
import argparse
import json
import os
from pathlib import Path
import socket
from urllib.parse import urlsplit
import database
import operations

ROOT = Path(__file__).resolve().parents[1]


def configuration_problems(env, mode):
    problems = []
    if env.get('APP_ENV') != 'production': problems.append('APP_ENV:require-production')
    try:
        database.secure_url(env.get('DATABASE_URL', ''), True)
    except ValueError:
        problems.append('DATABASE_URL:require-postgresql-and-TLS')
    if mode == 'api':
        key = env.get('JWT_SECRET', '')
        if len(key.encode()) < 32 or key == 'local-development-secret-only-0000':
            problems.append('JWT_SECRET:require-fresh-private-secret')
        if env.get('SEED_DEMO') != 'false': problems.append('SEED_DEMO:set-explicit-false')
        try:
            url = urlsplit(env.get('PUBLIC_URL', ''))
            if url.scheme != 'https' or not url.hostname or url.username or url.password or url.path not in ('', '/') or url.query or url.fragment:
                problems.append('PUBLIC_URL:require-https-origin')
        except ValueError:
            problems.append('PUBLIC_URL:require-https-origin')
    elif mode == 'scan':
        if not env.get('CLAMD_HOST'): problems.append('CLAMD_HOST:required')
        try:
            port = int(env.get('CLAMD_PORT', '3310'))
            if not 1 <= port <= 65535: raise ValueError()
        except ValueError:
            problems.append('CLAMD_PORT:invalid')
    elif mode == 'backup':
        try:
            target = database.secure_url(env.get('RESTORE_TEST_DATABASE_URL', ''), True)
            if not urlsplit(target).path.startswith('/ecc_restore_'):
                problems.append('RESTORE_TEST_DATABASE_URL:require-dedicated-drill-database')
        except ValueError:
            problems.append('RESTORE_TEST_DATABASE_URL:require-TLS-url')
        repository = env.get('RESTIC_REPOSITORY', '')
        if not repository.startswith(('s3:', 'sftp:', 'rest:', 'b2:', 'azure:', 'gs:', 'rclone:')):
            problems.append('RESTIC_REPOSITORY:require-offsite-repository')
        if not env.get('RESTIC_PASSWORD') and not env.get('RESTIC_PASSWORD_FILE'):
            problems.append('RESTIC_PASSWORD:require-private-encryption-key')
        for key in ('HEALTH_URL', 'ALERT_WEBHOOK_URL'):
            try:
                url = urlsplit(env.get(key, ''))
                if url.scheme != 'https' or not url.hostname or url.username or url.password:
                    problems.append(key + ':require-https-endpoint')
            except ValueError:
                problems.append(key + ':require-https-endpoint')
        if not Path(env.get('BACKUP_DIR', '/var/backups/ecc')).is_absolute():
            problems.append('BACKUP_DIR:require-absolute-persistent-path')
    return sorted(set(problems))


def database_problems():
    import postgres_recovery
    problems = []
    try:
        with postgres_recovery.connect(os.environ['DATABASE_URL'], 30) as conn:
            conn.execute('SET default_transaction_read_only=on')
            versions = [row[0] for row in conn.execute('SELECT version FROM public.schema_migrations ORDER BY version')]
            if versions != [path.name for path in sorted((ROOT / 'migrations/postgresql').glob('*.sql'))]:
                problems.append('database:migrations-do-not-match-release')
            admins = conn.execute("SELECT count(*) FROM users WHERE role='admin' AND suspended=0").fetchone()[0]
            if not admins: problems.append('database:active-admin-required')
            samples = conn.execute("SELECT count(*) FROM users WHERE email IN ('admin@ecc.com','aya@ecc.com','marco@ecc.com','hana@ecc.com','devon@ecc.com')").fetchone()[0]
            if samples: problems.append('database:review-existing-demo-accounts')
            flor = os.environ.get('FLOR_EMAIL')
            if flor:
                row = conn.execute('SELECT role,suspended FROM users WHERE lower(email)=lower(%s)', (flor,)).fetchone()
                if not row or row[1] or row[0] == 'viewer': problems.append('database:Flor-needs-active-editing-account')
    except Exception:
        problems.append('database:connection-or-query-failed')
    return problems


def scanner_problem():
    try:
        with socket.create_connection((os.environ['CLAMD_HOST'], int(os.environ.get('CLAMD_PORT', '3310'))), timeout=10) as stream:
            stream.sendall(b'zPING\0')
            answer = b''
            while b'\0' not in answer and len(answer) < 32:
                chunk = stream.recv(32-len(answer))
                if not chunk: break
                answer += chunk
            if answer.rstrip(b'\0\r\n') == b'PONG': return None
    except (OSError, ValueError, KeyError):
        pass
    return 'scanner:unavailable-or-invalid-response'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode', choices=['api', 'scan', 'backup'], default='api')
    parser.add_argument('--live', action='store_true', help='Read-only database/service checks; does not create users or migrate')
    args = parser.parse_args()
    problems = configuration_problems(os.environ, args.mode)
    if args.live and not problems:
        problems += database_problems()
        if args.mode == 'api':
            problem = operations.readiness_problem(os.environ['PUBLIC_URL'].rstrip('/') + '/api/ready')
            if problem: problems.append(problem)
        elif args.mode == 'scan':
            problem = scanner_problem()
            if problem: problems.append(problem)
        elif args.mode == 'backup':
            problems += operations.health(os.environ['DATABASE_URL'], os.environ.get('BACKUP_DIR', '/var/backups/ecc'))
    print(json.dumps({'mode': args.mode, 'liveChecksPerformed': args.live and not configuration_problems(os.environ, args.mode),
                      'checksPassed': not problems, 'problems': sorted(set(problems)),
                      'doesNotVerify': ['secret-rotation', 'end-to-end-user-workflows', 'database-restore']}, sort_keys=True))
    raise SystemExit(bool(problems))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        raise SystemExit('Setup check failed: ' + type(exc).__name__ + '; details withheld') from None
