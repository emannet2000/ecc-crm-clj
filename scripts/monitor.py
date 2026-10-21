#!/usr/bin/env python3
"""Check readiness, disk, mail and backup age; send state-change SMTP alerts."""
import os
import pathlib
import shutil
import sqlite3
import time
import urllib.request
from contextlib import closing
from mail_worker import deliver


def problems():
    issues = []
    try:
        with urllib.request.urlopen(os.environ['MONITOR_URL'], timeout=10) as response:
            if response.status != 200:
                issues.append('API readiness failed')
    except OSError:
        issues.append('API readiness failed')
    database = pathlib.Path(os.environ['DATABASE_PATH']).resolve()
    if not database.is_file():
        issues.append('Database file is missing')
    else:
        disk = shutil.disk_usage(database.parent)
        if disk.free < int(os.environ.get('MIN_FREE_BYTES', str(512 * 1024 * 1024))):
            issues.append('Database disk space is low')
        try:
            with closing(sqlite3.connect(database.as_uri() + '?mode=ro', uri=True, timeout=5)) as conn:
                if conn.execute('SELECT count(*) FROM mail_outbox WHERE sent_at IS NULL AND attempts>=5').fetchone()[0]:
                    issues.append('Account email delivery has failed')
                if conn.execute("SELECT count(*) FROM mail_outbox WHERE sent_at IS NULL AND created_at<datetime('now','-15 minutes')").fetchone()[0]:
                    issues.append('Account email queue is delayed')
        except sqlite3.Error:
            issues.append('Database cannot be read')
    directory = pathlib.Path(os.environ.get('BACKUP_DIR', '/backups'))
    snapshots = list(directory.glob('ecc-*.sqlite3'))
    max_age = int(os.environ.get('MAX_BACKUP_AGE_SECONDS', '7200'))
    if os.environ.get('REQUIRE_OFFHOST_BACKUP') == 'true':
        marker = directory / 'offhost-success'
        if not marker.exists() or time.time() - marker.stat().st_mtime > max_age:
            issues.append('Encrypted off-host backups are missing or stale')
    if not snapshots or time.time() - max(p.stat().st_mtime for p in snapshots) > max_age:
        issues.append('Verified backups are missing or stale')
    return tuple(sorted(issues))


def main():
    for name in ('DATABASE_PATH', 'MONITOR_URL', 'ALERT_TO', 'SMTP_HOST', 'SMTP_FROM'):
        if not os.environ.get(name):
            raise SystemExit(name + ' is required')
    previous, last_sent = (), 0
    while True:
        current = problems()
        if current != previous or (current and time.time() - last_sent > 3600):
            subject = 'ECC workspace: action needed' if current else 'ECC workspace: recovered'
            body = '\n'.join(current) if current else 'The workspace checks have recovered.'
            try:
                deliver((0, os.environ['ALERT_TO'], subject, body))
            except Exception as exc:
                print('Monitoring alert delivery failed:', type(exc).__name__, flush=True)
            else:
                previous, last_sent = current, time.time()
        print('monitor:', ', '.join(current) or 'healthy', flush=True)
        time.sleep(60)


if __name__ == '__main__':
    main()
