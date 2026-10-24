#!/usr/bin/env python3
"""Export a consistent, read-only SQLite snapshot, preserving every table and BLOB.
No database is modified. The output contains credentials and must stay private.
"""
import argparse
import base64
import json
import os
from pathlib import Path
import sqlite3


def export(source, destination):
    source = Path(source).resolve(strict=True)
    connection = sqlite3.connect(source.as_uri() + '?mode=ro', uri=True)
    try:
        connection.execute('BEGIN')
        tables = [r[0] for r in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        result = {}
        for table in tables:
            escaped = table.replace('"', '""')
            cursor = connection.execute(f'SELECT * FROM "{escaped}"')
            columns = [c[0] for c in cursor.description]
            result[table] = [dict(zip(columns, [
                {'$binary': base64.b64encode(v).decode('ascii')} if isinstance(v, bytes) else v
                for v in row])) for row in cursor]
        sequences = dict(connection.execute('SELECT name, seq FROM sqlite_sequence')) if connection.execute("SELECT 1 FROM sqlite_master WHERE name='sqlite_sequence'").fetchone() else {}
        with os.fdopen(os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as output:
            json.dump({'format': 'ecc-sqlite-v1', 'tables': result, 'sequences': sequences}, output, ensure_ascii=False)
        return {table: len(rows) for table, rows in result.items()}
    finally:
        connection.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('destination')
    args = parser.parse_args()
    print(json.dumps(export(args.source, args.destination), indent=2))
