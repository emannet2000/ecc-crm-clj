#!/usr/bin/env python3
"""Verified SQLite snapshots, optional encrypted off-host copies, bounded retention."""
import os
import pathlib
import subprocess
import time
from datetime import datetime, timezone
from sqlite_backup import copy_database


def replicate(target, directory):
    """Repository must be initialized explicitly; never hide configuration errors."""
    if not os.environ.get('RESTIC_REPOSITORY'):
        return False
    if not os.environ.get('RESTIC_PASSWORD_FILE'):
        raise ValueError('RESTIC_PASSWORD_FILE is required for off-host backup')
    with target.open('rb') as source:
        subprocess.run(['restic', 'backup', '--stdin', '--stdin-filename', 'ecc-crm.sqlite3',
                        '--host', 'ecc-crm', '--tag', 'ecc-crm', '--quiet'], stdin=source, check=True)
    subprocess.run(['restic', 'forget', '--tag', 'ecc-crm', '--host', 'ecc-crm',
                    '--group-by', 'host,tags', '--keep-last', '24', '--keep-daily', '7',
                    '--keep-weekly', '4', '--keep-monthly', '12', '--prune', '--quiet'], check=True)
    subprocess.run(['restic', 'check', '--quiet'], check=True)
    # Written only after successful upload, retention and repository validation.
    marker = directory / 'offhost-success'
    temporary = directory / '.offhost-success.tmp'
    temporary.write_text(datetime.now(timezone.utc).isoformat() + '\n')
    temporary.replace(marker)
    return True


def retain(directory, keep):
    snapshots = sorted(directory.glob('ecc-*.sqlite3'), reverse=True)
    for old in snapshots[max(1, keep):]:
        old.unlink()


def backup_once(database, directory, keep):
    target = directory / ('ecc-' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.sqlite3')
    copy_database(database, target)
    try:
        replicate(target, directory)
    finally:
        # Bound local disk use even during a remote outage; always keep the latest copy.
        retain(directory, keep)
    return target


def main():
    database = os.environ['DATABASE_PATH']
    directory = pathlib.Path(os.environ.get('BACKUP_DIR', '/backups'))
    interval = max(60, int(os.environ.get('BACKUP_INTERVAL_SECONDS', '3600')))
    keep = max(1, int(os.environ.get('BACKUP_KEEP_LOCAL', '24')))
    directory.mkdir(parents=True, exist_ok=True)
    while True:
        try:
            target = backup_once(database, directory, keep)
            print('Verified snapshot created:', target.name, flush=True)
        except Exception as exc:
            print('Backup failed:', type(exc).__name__, flush=True)
            time.sleep(60)
            continue
        time.sleep(interval)


if __name__ == '__main__':
    main()
