#!/usr/bin/env python3
"""Deliver queued account email from the application's SQLite file."""
from contextlib import closing
import os
import smtplib
import sqlite3
import ssl
import time
import uuid
from email.message import EmailMessage


def deliver(row):
    message = EmailMessage()
    message['From'] = os.environ['SMTP_FROM']
    message['To'] = row[1]
    message['Subject'] = row[2]
    message.set_content(row[3])
    host = os.environ['SMTP_HOST']
    port = int(os.environ.get('SMTP_PORT', '587'))
    secure = os.environ.get('SMTP_TLS', 'starttls')
    if secure not in ('ssl', 'starttls') and host not in ('localhost', 'mailpit'):
        raise ValueError('SMTP_TLS must be starttls or ssl for remote servers')
    if secure == 'ssl':
        server = smtplib.SMTP_SSL(host, port, timeout=30, context=ssl.create_default_context())
    else:
        server = smtplib.SMTP(host, port, timeout=30)
    with server:
        if secure == 'starttls':
            server.starttls(context=ssl.create_default_context())
        if os.environ.get('SMTP_USER'):
            server.login(os.environ['SMTP_USER'], os.environ['SMTP_PASSWORD'])
        server.send_message(message)


def run_once(conn):
    # Claim atomically, then release SQLite's writer lock before network I/O.
    # Expiring leases allow recovery after a crash; SMTP remains at least once.
    lease = uuid.uuid4().hex
    with conn:
        row = conn.execute("UPDATE mail_outbox SET claim_token=?,claimed_until=datetime('now','+2 minutes'),attempts=attempts+1 WHERE id=(SELECT id FROM mail_outbox WHERE sent_at IS NULL AND attempts<5 AND (next_attempt_at IS NULL OR next_attempt_at<=datetime('now')) AND (claimed_until IS NULL OR claimed_until<datetime('now')) ORDER BY id LIMIT 1) RETURNING id,recipient,subject,body", (lease,)).fetchone()
    if not row:
        return False
    try:
        deliver(row)
    except Exception as exc:
        with conn:
            conn.execute("UPDATE mail_outbox SET claim_token=NULL,claimed_until=NULL,next_attempt_at=datetime('now','+'||min(3600,60*(1 << min(attempts,6)))||' seconds'),last_error=? WHERE id=? AND claim_token=?", (type(exc).__name__, row[0], lease))
        print('mail delivery failed:', type(exc).__name__, flush=True)
    else:
        with conn:
            conn.execute("UPDATE mail_outbox SET sent_at=datetime('now'),body='',claim_token=NULL,claimed_until=NULL,last_error=NULL WHERE id=? AND claim_token=?", (row[0], lease))
        print('mail delivered', flush=True)
    return True


def cleanup(conn):
    with conn:
        conn.execute("DELETE FROM sessions WHERE expires_at<datetime('now')")
        conn.execute("DELETE FROM account_tokens WHERE expires_at<datetime('now')")
        conn.execute("DELETE FROM login_attempts WHERE expires_at<datetime('now')")
        conn.execute("DELETE FROM mail_outbox WHERE sent_at<datetime('now','-30 days')")


def main():
    for name in ('DATABASE_PATH', 'SMTP_HOST', 'SMTP_FROM'):
        if not os.environ.get(name):
            raise SystemExit(name + ' is required')
    while True:
        try:
            with closing(sqlite3.connect(os.environ['DATABASE_PATH'], timeout=10)) as conn:
                conn.execute('PRAGMA foreign_keys=ON')
                conn.execute('PRAGMA busy_timeout=10000')
                while True:
                    if not run_once(conn):
                        cleanup(conn)
                        time.sleep(15)
                    else:
                        time.sleep(1)
        except (sqlite3.OperationalError, OSError) as exc:
            print('mail worker retrying:', type(exc).__name__, flush=True)
            time.sleep(10)


if __name__ == '__main__':
    main()
