#!/usr/bin/env python3
"""Integration checks for PostgreSQL workers, without sending mail or using ClamAV."""
import os
from pathlib import Path
import uuid
from unittest import mock
import database
import mail_worker
import scan_worker
import workflow_worker

ROOT = Path(__file__).resolve().parents[1]


def main():
    import psycopg
    from psycopg import sql
    url = os.environ.get('ECC_TEST_DATABASE_URL')
    if not url:
        raise SystemExit('ECC_TEST_DATABASE_URL must identify a disposable PostgreSQL database')
    name = 'ecc_worker_test_' + uuid.uuid4().hex
    with mock.patch.dict(os.environ, {'DATABASE_URL': url, 'APP_ENV': 'development'}):
        connection = database.connect()
    raw = connection.connection
    try:
        raw.execute(sql.SQL('CREATE SCHEMA {}; SET search_path={},public').format(sql.Identifier(name), sql.Identifier(name)))
        raw.execute('\n'.join(path.read_text() for path in sorted((ROOT / 'migrations/postgresql').glob('*.sql'))))
        raw.execute("INSERT INTO users(email,password_hash,name,role) VALUES('workers@example.invalid','fixture','Test worker','admin')")
        raw.execute("INSERT INTO clients(client_number,full_name) VALUES('WORKER-TEST','Worker student')")
        raw.execute("INSERT INTO mail_outbox(recipient,subject,body) VALUES('nobody@example.invalid','Fixture','private fixture body')")
        raw.commit()
        delivered = []
        with mock.patch.object(mail_worker, 'deliver', side_effect=delivered.append):
            assert mail_worker.run_once(connection)
            assert not mail_worker.run_once(connection)
        row = raw.execute('SELECT sent_at,body,attempts FROM mail_outbox').fetchone()
        assert len(delivered) == 1 and row[0] and row[1] == '' and row[2] == 1
        raw.execute("INSERT INTO documents(client_id,filename,content) VALUES(1,'fixture.pdf',%s)", (b'\x00fixture\xff',))
        raw.commit()
        scanned = []
        def scanner(content):
            scanned.append(bytes(content))
            return 'Clean', 'Fixture scan'
        assert scan_worker.run_once(connection, scanner)
        assert not scan_worker.run_once(connection, scanner)
        assert scanned == [b'\x00fixture\xff']
        assert raw.execute('SELECT scan_status FROM documents').fetchone() == ('Clean',)
        raw.execute("INSERT INTO expenses(supplier,description,category,currency,amount_minor,expense_on,created_by,created_name) VALUES('School','Receipt','Education','PHP',100,'2020-01-01',1,'Test')")
        raw.execute("INSERT INTO financial_files(expense_id,filename,content,size,uploaded_by,uploaded_name) VALUES(1,'receipt.pdf',%s,4,1,'Test')", (b'test',))
        raw.commit()
        assert scan_worker.run_financial_once(connection, scanner)
        assert raw.execute('SELECT scan_status FROM financial_files').fetchone() == ('Clean',)
        raw.execute("INSERT INTO tasks(client_id,title,due_date,status,assigned_to_id,recurrence_days) VALUES(1,'Recurring','2020-01-01','Done',1,7)")
        raw.execute('INSERT INTO reminder_rules(task_id) VALUES(1)')
        raw.commit()
        workflow_worker.run_once(connection)
        workflow_worker.run_once(connection)
        assert raw.execute('SELECT count(*) FROM tasks WHERE recurrence_parent=1').fetchone()[0] == 1
        assert raw.execute('SELECT count(*) FROM reminder_rules').fetchone()[0] == 2
        print('PostgreSQL mail claiming, body cleanup, document/evidence scanning and recurring-task idempotence passed')
    finally:
        raw.rollback()
        raw.execute(sql.SQL('SET search_path=public; DROP SCHEMA {} CASCADE').format(sql.Identifier(name)))
        raw.commit()
        connection.close()


if __name__ == '__main__':
    main()
