#!/usr/bin/env python3
"""Validate the PostgreSQL baseline and business invariants in an isolated schema.

Use ECC_TEST_DATABASE_URL for a disposable PostgreSQL instance, or --standalone
with --data-directory when the environment forbids network/Unix sockets.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]


def acceptance_sql():
    name = 'ecc_acceptance_' + uuid.uuid4().hex
    schema = '\n'.join(path.read_text() for path in sorted((ROOT / 'migrations/postgresql').glob('*.sql')))
    checks = (ROOT / 'test/postgresql-acceptance.sql').read_text()
    return (f'BEGIN; CREATE SCHEMA {name}; SET LOCAL search_path={name},public;\n'
            + schema + '\n' + checks + '\nROLLBACK;\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--standalone', type=Path)
    parser.add_argument('--data-directory', type=Path)
    args = parser.parse_args()
    sql = acceptance_sql()
    if args.standalone:
        if not args.data_directory:
            parser.error('--data-directory is required with --standalone')
        # A standalone backend treats each input line as a command batch.
        sql = ' '.join(line for line in sql.splitlines() if not line.lstrip().startswith('--')) + '\n'
        result = subprocess.run([str(args.standalone), '--single', '-D', str(args.data_directory), 'postgres'],
                                input=sql, text=True, capture_output=True, timeout=90)
        errors = [line.split('ERROR:', 1)[1] for line in (result.stdout + result.stderr).splitlines() if 'ERROR:' in line]
        if result.returncode or errors:
            raise SystemExit('PostgreSQL acceptance failed: ' + '; '.join(errors or ['backend failed']))
    else:
        import psycopg
        url = os.environ.get('ECC_TEST_DATABASE_URL')
        if not url:
            parser.error('ECC_TEST_DATABASE_URL is required; never use a production database')
        try:
            with psycopg.connect(url, autocommit=True) as connection:
                connection.execute(sql)
        except Exception as exc:
            raise SystemExit('PostgreSQL acceptance failed: ' + type(exc).__name__) from None
    print('PostgreSQL schema, audit, revisions, binary storage, quarantine, payments, reversals, closed periods and session revocation passed')


if __name__ == '__main__':
    main()
