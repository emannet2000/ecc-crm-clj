#!/usr/bin/env python3
"""Test the real operator account CLI against isolated SQLite databases."""
from contextlib import closing
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest

BINARY=os.environ.get('ECC_API_BIN')


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        if not BINARY: self.fail('ECC_API_BIN is required')
        self.work=tempfile.TemporaryDirectory(prefix='ecc-bootstrap-')
        self.addCleanup(self.work.cleanup)
        self.path=Path(self.work.name)/'test.sqlite3'
        self.env={key:value for key,value in os.environ.items() if key not in ['DATABASE_URL','APP_ENV','DATABASE_PATH','ECC_USER_EMAIL','ECC_USER_NAME','ECC_USER_ROLE','ECC_USER_PASSWORD']}
        self.env.update(APP_ENV='development',DATABASE_PATH=str(self.path),SEED_DEMO='false',JWT_SECRET='isolated-bootstrap-test-secret-at-least-32-bytes',
                        ECC_USER_EMAIL='flor@example.invalid',ECC_USER_NAME='Flor test',ECC_USER_ROLE='consultant',ECC_USER_PASSWORD='fixture-bootstrap-password-123')

    def run_cli(self):
        return subprocess.run([BINARY,'create-user-env'],env=self.env,cwd=Path(__file__).resolve().parents[1],capture_output=True,text=True,timeout=30)

    def test_create_without_password_in_arguments_and_duplicate_cannot_promote(self):
        first=self.run_cli()
        self.assertEqual(first.returncode,0,first.stdout+first.stderr)
        self.assertNotIn(self.env['ECC_USER_PASSWORD'],first.stdout+first.stderr)
        with closing(sqlite3.connect(self.path)) as conn:
            before=conn.execute('SELECT email,role,password_hash FROM users').fetchall()
        self.assertEqual(before[0][:2],('flor@example.invalid','consultant'))
        self.env.update(ECC_USER_ROLE='admin',ECC_USER_PASSWORD='another-fixture-password-123')
        again=self.run_cli()
        self.assertNotEqual(again.returncode,0)
        self.assertNotIn(self.env['ECC_USER_PASSWORD'],again.stdout+again.stderr)
        with closing(sqlite3.connect(self.path)) as conn:
            self.assertEqual(conn.execute('SELECT email,role,password_hash FROM users').fetchall(),before)

    def test_bad_role_missing_password_and_overlong_utf8_password_create_no_users(self):
        for key,value in [('ECC_USER_ROLE','owner'),('ECC_USER_PASSWORD',''),('ECC_USER_PASSWORD','é'*40),('ECC_USER_EMAIL','bad-address')]:
            with self.subTest(key=key,value=value):
                original=self.env[key];self.env[key]=value
                result=self.run_cli()
                self.assertNotEqual(result.returncode,0)
                with closing(sqlite3.connect(self.path)) as conn:
                    self.assertEqual(conn.execute('SELECT count(*) FROM users').fetchone()[0],0)
                self.env[key]=original


if __name__=='__main__':unittest.main(verbosity=2)
