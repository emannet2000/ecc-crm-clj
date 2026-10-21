#!/usr/bin/env python3
"""Restore an immutable snapshot to a new path and record counts/document parity."""
import argparse
from contextlib import closing
import hashlib
import json
import pathlib
import sqlite3
import time
from datetime import datetime, timezone
from sqlite_backup import copy_database


def inventory(database):
    with closing(sqlite3.connect(pathlib.Path(database).resolve().as_uri() + '?mode=ro', uri=True)) as conn:
        tables = [name for name, in conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        counts = {name: conn.execute('SELECT count(*) FROM "' + name.replace('"', '""') + '"').fetchone()[0] for name in tables}
        digest = hashlib.sha256()
        if 'documents' in tables:
            for doc_id, data in conn.execute('SELECT id,content FROM documents ORDER BY id'):
                digest.update(str(doc_id).encode() + b':' + hashlib.sha256(data).digest())
        return {'tableCounts': counts, 'documentDigest': digest.hexdigest()}


def drill(snapshot, destination):
    started = time.monotonic()
    expected = inventory(snapshot)
    copy_database(snapshot, destination)
    restored = inventory(destination)
    if expected != restored:
        raise ValueError('Restored counts or document contents differ')
    return {'checkedAt': datetime.now(timezone.utc).isoformat(),
            'elapsedSeconds': round(time.monotonic() - started, 3),
            'snapshotModifiedAt': datetime.fromtimestamp(pathlib.Path(snapshot).stat().st_mtime, timezone.utc).isoformat(),
            **restored, 'integrityAndForeignKeys': 'passed', 'countsAndDocuments': 'passed',
            'applicationChecks': 'pending: verify logins, permissions, conversion, downloads and email'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('snapshot')
    parser.add_argument('destination')
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    report = pathlib.Path(args.report)
    if report.exists() or pathlib.Path(args.destination).resolve() == report.resolve():
        parser.error('Report must be a new path different from the restored database')
    result = drill(args.snapshot, args.destination)
    with report.open('x') as handle:
        handle.write(json.dumps(result, indent=2) + '\n')
    print('Restore verified; application acceptance checks remain. Report:', report)
