"""Acceptance checks for quarantine, notification preferences and trend snapshots."""
from contextlib import closing
import sqlite3
import struct
import unittest
from unittest.mock import patch
from test_sqlite import ROOT, SQLiteTests, load_script

scan = load_script('scan_worker')
scheduler = load_script('workflow_worker')
mail = load_script('mail_worker')


class OperationsTests(unittest.TestCase):
    setUp = SQLiteTests.setUp
    tearDown = SQLiteTests.tearDown

    def document(self):
        self.conn.execute("INSERT INTO clients(client_number,full_name,case_officer_id) VALUES ('C-1','Client',1)")
        self.conn.execute("INSERT INTO documents(client_id,filename,size,content) VALUES (1,'file.txt',4,X'74657374')")
        self.conn.execute("INSERT INTO document_requests(client_id,title,status) VALUES (1,'Passport','Received')")
        self.conn.execute("INSERT INTO document_versions(request_id,document_id,version) VALUES (1,1,1)")
        self.conn.commit()

    def test_scan_fails_closed_then_allows_only_scanned_bytes(self):
        self.document()
        def unavailable(_):
            raise OSError('unavailable')
        self.assertTrue(scan.run_once(self.conn, unavailable))
        self.assertEqual(self.conn.execute('SELECT scan_status FROM documents').fetchone()[0], 'Error')
        self.conn.execute("UPDATE documents SET scan_until=datetime('now','-1 minute')")
        self.conn.commit()
        self.assertTrue(scan.run_once(self.conn, lambda data: ('Clean', 'test scanner')))
        self.assertEqual(self.conn.execute('SELECT scan_status FROM documents').fetchone()[0], 'Clean')
        self.conn.execute("UPDATE documents SET content=X'6e6577' WHERE id=1")
        self.conn.commit()
        self.assertEqual(self.conn.execute('SELECT scan_status FROM documents').fetchone()[0], 'Pending')
        def replaced_while_scanning(data):
            self.conn.execute("UPDATE documents SET content=X'666f7572' WHERE id=1")
            self.conn.commit()
            return 'Clean', 'old bytes'
        scan.run_once(self.conn, replaced_while_scanning)
        self.assertEqual(self.conn.execute('SELECT scan_status FROM documents').fetchone()[0], 'Pending')

    def test_infection_rejects_latest_version_and_notifies_owner(self):
        self.document()
        scan.run_once(self.conn, lambda data: ('Infected', 'test signature'))
        self.assertEqual(self.conn.execute('SELECT status FROM document_requests').fetchone()[0], 'Rejected')
        self.assertEqual(self.conn.execute("SELECT count(*) FROM notifications WHERE kind='documents'").fetchone()[0], 1)
        self.assertFalse(scan.run_once(self.conn, lambda data: ('Clean', 'never called')))

    def test_clamd_stream_framing_and_error_verdict(self):
        class Socket:
            sent = b''
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def sendall(self, data): self.sent += data
            def recv(self, count): return self.answer
        connection = Socket()
        connection.answer = b'stream: OK\0'
        with patch.object(scan.socket, 'create_connection', return_value=connection):
            self.assertEqual(scan.scan_bytes(b'test')[0], 'Clean')
        self.assertEqual(connection.sent, b'zINSTREAM\0' + struct.pack('!I',4) + b'test\0\0\0\0')
        connection.answer = b'stream: signature FOUND\0'
        with patch.object(scan.socket, 'create_connection', return_value=connection):
            self.assertEqual(scan.scan_bytes(b'test')[0], 'Infected')
        connection.answer = b'INSTREAM size limit exceeded. ERROR\0'
        with patch.object(scan.socket, 'create_connection', return_value=connection), self.assertRaises(RuntimeError):
            scan.scan_bytes(b'test')

    def test_preferences_snapshots_notifications_and_recurring_case_scope(self):
        db = self.conn
        db.execute("INSERT INTO clients(client_number,full_name,case_officer_id) VALUES ('C-1','Client',1)")
        db.execute("INSERT INTO cases(client_id,stage) VALUES (1,'Submitted')")
        db.execute("INSERT INTO tasks(client_id,case_id,title,assigned_to_id,due_date,recurrence_days,status) VALUES (1,1,'Review',1,'2020-01-01',7,'Done')")
        db.execute("INSERT INTO tasks(client_id,case_id,title,assigned_to_id,due_date) VALUES (1,1,'Due task',1,'2020-01-01')")
        db.execute("INSERT INTO reminder_rules(task_id) VALUES (2)")
        db.execute("INSERT INTO notification_preferences(user_id,email_enabled) VALUES (1,0)")
        db.commit()
        scheduler.run_once(db)
        scheduler.run_once(db)
        self.assertEqual(db.execute('SELECT count(*) FROM mail_outbox').fetchone()[0], 0)
        self.assertEqual(db.execute('SELECT count(*) FROM workload_snapshots').fetchone()[0], 1)
        self.assertEqual(db.execute('SELECT case_id FROM tasks WHERE recurrence_parent=1').fetchone()[0], 1)
        self.assertEqual(db.execute("SELECT count(*) FROM notifications WHERE kind='deadlines'").fetchone()[0], 2)
        self.assertEqual(db.execute("SELECT count(*) FROM notifications WHERE kind='escalations'").fetchone()[0], 1)

    def test_upgrade_quarantines_legacy_files_without_losing_bytes_or_approval(self):
        with closing(sqlite3.connect(':memory:')) as db:
            db.execute('PRAGMA foreign_keys=ON')
            migrations = sorted((ROOT / 'api/migrations').glob('*.sql'))
            for migration in migrations[:-1]:
                db.executescript(migration.read_text())
            db.execute("INSERT INTO users(email,name,role,password_hash) VALUES ('legacy@example.com','Legacy','admin','hash')")
            db.execute("INSERT INTO clients(client_number,full_name) VALUES ('C-1','Legacy client')")
            db.execute("INSERT INTO documents(client_id,filename,size,content) VALUES (1,'old.txt',4,X'74657374')")
            db.execute("INSERT INTO document_requests(client_id,title,status) VALUES (1,'Passport','Approved')")
            db.execute("INSERT INTO document_versions(request_id,document_id,version) VALUES (1,1,1)")
            audit_count = db.execute('SELECT count(*) FROM audit_log').fetchone()[0]
            db.commit()
            db.executescript('BEGIN IMMEDIATE;\n' + migrations[-1].read_text() + '\nCOMMIT;')
            self.assertEqual(db.execute('SELECT content,scan_status FROM documents').fetchone(), (b'test', 'Pending'))
            self.assertEqual(db.execute('SELECT status FROM document_requests').fetchone()[0], 'Approved')
            self.assertEqual(db.execute('SELECT count(*) FROM audit_log').fetchone()[0], audit_count)
            self.assertEqual(db.execute('PRAGMA foreign_key_check').fetchall(), [])

    def test_smtp_failures_back_off_before_retrying(self):
        self.conn.execute("INSERT INTO mail_outbox(recipient,subject,body) VALUES ('test@example.com','Test','Body')")
        self.conn.commit()
        with patch.object(mail, 'deliver', side_effect=OSError('unavailable')):
            self.assertTrue(mail.run_once(self.conn))
            self.assertFalse(mail.run_once(self.conn))
        self.assertEqual(self.conn.execute('SELECT attempts FROM mail_outbox').fetchone()[0], 1)
        self.assertIsNotNone(self.conn.execute('SELECT next_attempt_at FROM mail_outbox').fetchone()[0])


del SQLiteTests
if __name__ == '__main__':
    unittest.main()
