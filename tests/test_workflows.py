"""Workflow persistence and scheduler acceptance tests, using real migrated SQLite."""
import unittest
from test_sqlite import SQLiteTests, load_script

scheduler = load_script('workflow_worker')


class WorkflowTests(unittest.TestCase):
    setUp = SQLiteTests.setUp
    tearDown = SQLiteTests.tearDown
    def test_scheduling_retries_do_not_duplicate_tasks_or_emails(self):
        db = self.conn
        db.execute("INSERT INTO clients(client_number,full_name,case_officer_id) VALUES ('C-1','Client',1)")
        db.execute("INSERT INTO tasks(client_id,title,due_date,assigned_to_id,recurrence_days,status) VALUES (1,'Weekly review','2020-01-01',1,7,'Done')")
        db.execute("INSERT INTO reminder_rules(task_id) VALUES (1)")
        db.execute("INSERT INTO tasks(client_id,title,due_date,assigned_to_id) VALUES (1,'Overdue','2020-01-01',1)")
        db.execute("INSERT INTO reminder_rules(task_id,days_before,escalate_after) VALUES (2,1,2)")
        db.commit()
        scheduler.run_once(db)
        scheduler.run_once(db)
        self.assertEqual(db.execute('SELECT count(*) FROM tasks WHERE recurrence_parent=1').fetchone()[0], 1)
        self.assertEqual(db.execute('SELECT count(*) FROM mail_outbox').fetchone()[0], 2)
        self.assertEqual(db.execute('SELECT count(*) FROM reminder_deliveries').fetchone()[0], 2)
        self.assertEqual(db.execute('SELECT count(*) FROM reminder_rules').fetchone()[0], 3)
        self.assertEqual(db.execute('SELECT actor_id,role FROM request_context').fetchone(), (None, None))
        db.execute("UPDATE clients SET deleted_at=datetime('now') WHERE id=1")
        db.execute("DELETE FROM reminder_deliveries")
        db.commit()
        scheduler.run_once(db)
        self.assertEqual(db.execute('SELECT count(*) FROM mail_outbox').fetchone()[0], 2)

    def test_account_suspension_revokes_access_and_redacts_mfa_audit(self):
        db = self.conn
        db.execute("INSERT INTO sessions(token_hash,user_id,expires_at) VALUES ('session',1,'2099-01-01')")
        db.execute("UPDATE users SET mfa_secret='PRIVATE-AUTHENTICATOR-KEY' WHERE id=1")
        db.execute("UPDATE users SET suspended=1 WHERE id=1")
        self.assertEqual(db.execute('SELECT count(*) FROM sessions').fetchone()[0], 0)
        history = str(db.execute('SELECT changes FROM audit_log').fetchall())
        self.assertNotIn('PRIVATE-AUTHENTICATOR-KEY', history)
        self.assertIn('enabled', history)
        self.assertIn('suspended', history)

    def test_children_invalidate_parent_merge_preview(self):
        db = self.conn
        db.execute("INSERT INTO clients(client_number,full_name) VALUES ('C-1','Client')")
        revision = lambda: db.execute("SELECT revision FROM record_versions WHERE kind='clients' AND record_id=1").fetchone()[0]
        before = revision()
        db.execute("INSERT INTO work_history(client_id,kind,note) VALUES (1,'note','New conversation')")
        self.assertGreater(revision(), before)
        before = revision()
        db.execute("INSERT INTO document_requests(client_id,title) VALUES (1,'Passport')")
        self.assertGreater(revision(), before)

    def test_audit_upgrade_preserves_entries_and_captures_new_categories(self):
        db = self.conn
        db.execute("INSERT INTO clients(client_number,full_name) VALUES ('C-1','Client')")
        db.execute("INSERT INTO document_requests(client_id,title) VALUES (1,'Passport')")
        db.execute("INSERT INTO invoices(client_id,description,currency,amount_minor,due_date) VALUES (1,'Consultation','PHP',12550,'2030-01-01')")
        categories = {row[0] for row in db.execute('SELECT DISTINCT entity_type FROM audit_log')}
        self.assertTrue({'user', 'client', 'document_request', 'invoice'}.issubset(categories))
        self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])


del SQLiteTests

if __name__ == '__main__':
    unittest.main()
