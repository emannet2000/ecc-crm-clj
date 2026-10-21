#!/usr/bin/env python3
"""Consistent online backup and non-overwriting restore for SQLite WAL databases."""
from contextlib import closing
import os
import pathlib
import sqlite3
import sys
import tempfile
import urllib.parse


def copy_database(source, target):
    source, target = pathlib.Path(source).resolve(), pathlib.Path(target).resolve()
    if not source.is_file() or source == target:
        raise ValueError('Source must be an existing database different from the target')
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=target.name + '.', suffix='.tmp', dir=target.parent)
    os.close(fd)
    try:
        uri = 'file:' + urllib.parse.quote(str(source), safe='/') + '?mode=ro'
        with closing(sqlite3.connect(uri, uri=True)) as src, closing(sqlite3.connect(temporary)) as dst:
            src.backup(dst)
            if dst.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
                raise ValueError('Database integrity check failed')
            if dst.execute('PRAGMA foreign_key_check').fetchall():
                raise ValueError('Database foreign key check failed')
        with open(temporary, 'rb') as handle:
            os.fsync(handle.fileno())
        # link is atomic and refuses to overwrite an existing target.
        os.link(temporary, target)
        directory = os.open(target.parent, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: sqlite_backup.py SOURCE TARGET (target must not exist)')
    copy_database(sys.argv[1], sys.argv[2])
    print('Verified SQLite copy created:', sys.argv[2])
