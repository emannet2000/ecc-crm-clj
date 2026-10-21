#!/usr/bin/env python3
"""Copy a verified SQLite CRM into an empty PostgreSQL CRM, atomically.

The source is opened read-only. DATABASE_URL must identify the migrated, empty
destination. Stop application writers and take a verified backup before use.
"""
import argparse
from contextlib import closing
import hashlib
import json
import os
from pathlib import Path
import sqlite3
from urllib.parse import quote
import database

ROOT = Path(__file__).resolve().parents[1]


def checksum(rows):
    digest = hashlib.sha256()
    for row in rows:
        digest.update(json.dumps(list(row), ensure_ascii=False, separators=(',', ':'),
                                 default=lambda value: {'bytes': bytes(value).hex()}).encode('utf-8'))
        digest.update(b'\n')
    return digest.hexdigest()


def transfer(source, url):
    import psycopg
    from psycopg import sql
    path = Path(source).resolve(strict=True)
    url = database.secure_url(url, os.environ.get('APP_ENV') == 'production')
    with closing(sqlite3.connect('file:' + quote(str(path), safe='/') + '?mode=ro', uri=True)) as legacy:
        legacy.execute('BEGIN')
        if legacy.execute('PRAGMA integrity_check').fetchall() != [('ok',)] or legacy.execute('PRAGMA foreign_key_check').fetchall():
            raise ValueError('SQLite source failed integrity or foreign-key checks')
        versions = [row[0] for row in legacy.execute('SELECT version FROM schema_migrations ORDER BY version')]
        if versions != [file.name for file in sorted((ROOT / 'migrations').glob('*.sql'))]:
            raise ValueError('SQLite source must have the complete current schema')
        with psycopg.connect(url, connect_timeout=10) as target:
            target.execute('SELECT pg_advisory_xact_lock(1162036050)')
            applied = target.execute('SELECT version FROM schema_migrations ORDER BY version').fetchall()
            if applied != [(file.name,) for file in sorted((ROOT / 'migrations/postgresql').glob('*.sql'))]:
                raise ValueError('Run the PostgreSQL baseline migration before importing')
            tables = [row[0] for row in target.execute("SELECT table_name FROM information_schema.tables WHERE table_schema=current_schema() AND table_type='BASE TABLE' AND table_name NOT IN ('schema_migrations','request_context') ORDER BY table_name")]
            legacy_tables = {row[0] for row in legacy.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT IN ('schema_migrations','request_context','sqlite_sequence')")}
            if set(tables) != legacy_tables:
                raise ValueError('Source/destination table sets differ')
            for table in tables:
                if table in ('checklist_templates','checklist_template_items'):
                    continue
                if target.execute(sql.SQL('SELECT count(*) FROM {}').format(sql.Identifier(table))).fetchone()[0]:
                    raise ValueError('PostgreSQL destination must be empty; existing records were not changed')
            # Only untouched starter examples may be removed from an empty destination.
            with sqlite3.connect(':memory:') as starter:
                starter.create_function('business_offset',0,lambda:'480 minutes')
                for migration in sorted((ROOT/'migrations').glob('*.sql')):
                    starter.executescript(migration.read_text())
                selections=["SELECT name,category,destination,revision FROM checklist_templates ORDER BY name",
                            "SELECT t.name,i.title,i.required FROM checklist_template_items i JOIN checklist_templates t ON t.id=i.template_id ORDER BY t.name,i.title"]
                for selection in selections:
                    if list(starter.execute(selection)) != target.execute(selection).fetchall():
                        raise ValueError('Destination checklists were changed; use an empty database')
            target.execute('DELETE FROM checklist_template_items')
            target.execute('DELETE FROM checklist_templates')
            target.execute('SET CONSTRAINTS ALL DEFERRED')
            for table in tables:
                target.execute(sql.SQL('ALTER TABLE {} DISABLE TRIGGER USER').format(sql.Identifier(table)))
            counts = {}
            for table in tables:
                info = legacy.execute('PRAGMA table_info("' + table + '")').fetchall()
                columns = [row[1] for row in info]
                keys = [row[1] for row in sorted(info, key=lambda row: row[5]) if row[5]]
                selection = 'SELECT ' + ','.join('"' + column + '"' for column in columns) + ' FROM "' + table + '"'
                counts[table] = legacy.execute('SELECT count(*) FROM "' + table + '"').fetchone()[0]
                with target.cursor().copy(sql.SQL('COPY {} ({}) FROM STDIN').format(sql.Identifier(table), sql.SQL(',').join(map(sql.Identifier, columns)))) as copy:
                    for row in legacy.execute(selection):
                        copy.write_row(row)
                order = ' ORDER BY ' + ','.join('"' + key + '"' for key in keys)
                expected = checksum(legacy.execute(selection + order))
                actual = checksum(target.execute(sql.SQL('SELECT {} FROM {} ORDER BY {}').format(
                    sql.SQL(',').join(map(sql.Identifier, columns)), sql.Identifier(table), sql.SQL(',').join(map(sql.Identifier, keys)))))
                if expected != actual:
                    raise ValueError('Imported row/document verification failed; transaction rolled back')
                sequence = target.execute('SELECT pg_get_serial_sequence(%s,%s)', (table, 'id')).fetchone()[0] if 'id' in columns else None
                if sequence:
                    target.execute(sql.SQL("SELECT setval(%s,coalesce(max(id),1),max(id) IS NOT NULL) FROM {}").format(sql.Identifier(table)), (sequence,))
            for table in tables:
                target.execute(sql.SQL('ALTER TABLE {} ENABLE TRIGGER USER').format(sql.Identifier(table)))
            target.execute('SET CONSTRAINTS ALL IMMEDIATE')
            return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    args = parser.parse_args()
    url = os.environ.get('DATABASE_URL')
    if not url:
        parser.error('Set DATABASE_URL to the empty PostgreSQL destination')
    try:
        counts = transfer(args.source, url)
    except Exception as exc:
        # Never print libpq connection strings or database error details.
        raise SystemExit('Import failed; no rows committed: ' + type(exc).__name__) from None
    print(json.dumps({'imported': counts, 'rowAndDocumentChecksumsVerified': True}, sort_keys=True))


if __name__ == '__main__':
    main()
