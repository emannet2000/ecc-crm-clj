import os
from pathlib import Path
import sqlite3
import unittest
from unittest import mock
import database
import workflow_worker


class DatabaseTests(unittest.TestCase):
    def test_tls_is_required_by_default_and_cannot_be_disabled_in_production(self):
        for production in (False, True):
            result = database.secure_url('postgresql://test@example.invalid/test', production)
            self.assertIn('sslmode=require', result)
        for mode in ('disable', 'prefer', 'allow', ''):
            with self.subTest(mode=mode), self.assertRaises(ValueError):
                database.secure_url('postgresql://test@example.invalid/test?sslmode=' + mode, True)
        for mode in ('require', 'verify-ca', 'verify-full'):
            self.assertIn('sslmode=' + mode, database.secure_url('postgresql://test@example.invalid/test?sslmode=' + mode, True))
        with self.assertRaises(ValueError):
            database.secure_url('postgresql://test@example.invalid/test?sslmode=require&sslmode=disable', True)

    def test_local_test_server_can_explicitly_disable_tls(self):
        result = database.secure_url('postgresql://test@localhost/test?sslmode=disable', False)
        self.assertIn('sslmode=disable', result)

    def test_worker_parameters_and_literals_stay_separate(self):
        sql = database.postgres_sql("UPDATE mail_outbox SET body='date(?) 100%',claimed_until=datetime('now','+2 minutes') WHERE id=?")
        self.assertIn("body='date(?) 100%%'", sql)
        self.assertIn("ecc_datetime('now','+2 minutes')", sql)
        self.assertTrue(sql.endswith('id=%s'))

    def test_postgres_ignore_conflicts_precede_returned_ids(self):
        sql = database.postgres_sql('INSERT OR IGNORE INTO tasks(title) VALUES (?) RETURNING id')
        self.assertIn('ON CONFLICT DO NOTHING RETURNING id', sql)

    def test_bad_url_never_falls_back_to_a_local_database(self):
        with mock.patch.dict(os.environ, {'DATABASE_URL': 'invalid', 'DATABASE_PATH': '/tmp/should-not-exist.sqlite3'}):
            with self.assertRaises(ValueError):
                database.connect()

    def test_recurring_tasks_and_reminders_remain_idempotent(self):
        with sqlite3.connect(':memory:') as conn:
            conn.create_function('business_offset', 0, lambda: '480 minutes')
            for path in sorted((Path(__file__).resolve().parents[1] / 'migrations').glob('*.sql')):
                conn.executescript(path.read_text())
            conn.execute("INSERT INTO users(email,password_hash,name,role) VALUES('worker@example.invalid','fixture','Worker','admin')")
            conn.execute("INSERT INTO clients(client_number,full_name) VALUES('TEST','Test student')")
            conn.execute("INSERT INTO tasks(client_id,title,due_date,status,assigned_to_id,recurrence_days) VALUES(1,'Recurring','2020-01-01','Done',1,7)")
            conn.execute('INSERT INTO reminder_rules(task_id) VALUES(1)')
            conn.commit()
            workflow_worker.run_once(conn)
            workflow_worker.run_once(conn)
            self.assertEqual(conn.execute('SELECT count(*) FROM tasks WHERE recurrence_parent=1').fetchone()[0], 1)
            self.assertEqual(conn.execute('SELECT count(*) FROM reminder_rules').fetchone()[0], 2)
