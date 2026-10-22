#!/usr/bin/env python3
"""PostgreSQL snapshot and restore backend for recovery.py and operations.py.

Credentials are read from environment variables, never passed in process arguments.
Only trusted ECC archives and isolated, empty restore databases are supported.
"""
from contextlib import contextmanager
from datetime import date, datetime
from decimal import Decimal
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import uuid

import database
import recovery


def is_url(value):
    return str(value).startswith(('postgresql://', 'postgres://'))


def secure_url(value):
    return database.secure_url(str(value), os.environ.get('APP_ENV') == 'production')


@contextmanager
def connect(url, timeout=900):
    import psycopg
    # Do not wrap/re-emit connection errors: the public CLI sanitizes them.
    with psycopg.connect(secure_url(url), connect_timeout=10, autocommit=True) as conn:
        conn.execute("SET TIME ZONE 'UTC'")
        conn.execute("SELECT set_config('statement_timeout',%s,false)", (str(int(timeout * 1000)),))
        conn.execute("SET lock_timeout='10s'")
        yield conn


def child_environment(url):
    from psycopg.conninfo import conninfo_to_dict
    from psycopg.pq import Conninfo
    # PGDATABASE is a database name, not a URI: libpq does not expand a URI
    # supplied through the environment. Split it using libpq's own parser.
    # Never inherit PGOPTIONS/PGSERVICE or put credentials in argv/error output.
    environment = {key: value for key, value in {
        'PATH': os.environ.get('PATH', os.defpath),
        'LD_LIBRARY_PATH': os.environ.get('LD_LIBRARY_PATH'),
        'LANG': 'C.UTF-8',
        'PGCONNECT_TIMEOUT': '10', 'PGAPPNAME': 'ecc-recovery',
        'PGPASSFILE': '/dev/null',
    }.items() if value is not None}
    variables = {option.keyword.decode(): option.envvar.decode()
                 for option in Conninfo.get_defaults() if option.envvar}
    for key, value in conninfo_to_dict(secure_url(url)).items():
        if key not in variables:
            raise recovery.RecoveryError('Unsupported PostgreSQL connection option for recovery tools')
        environment[variables[key]] = value
    return environment


def run_tool(tool, arguments, url=None, timeout=900):
    result = subprocess.run([os.environ.get(tool.upper() + '_BIN', tool), *map(str, arguments)],
                            env=child_environment(url) if url else child_environment('postgresql://unused.invalid/unused'),
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout, check=False)
    if result.returncode:
        raise recovery.RecoveryError(tool + ' failed; database details withheld')
    return result.stdout


def database_identity(conn):
    row = conn.execute("SELECT current_database(),(SELECT oid FROM pg_database WHERE datname=current_database()),coalesce(inet_server_addr()::text,'local'),inet_server_port()").fetchone()
    return hashlib.sha256(json.dumps(list(row), separators=(',', ':')).encode()).hexdigest()


def canonical(value):
    if isinstance(value, (bytes, bytearray, memoryview)):
        return {'binary': bytes(value).hex()}
    if isinstance(value, (date, datetime)):
        return {'date': value.isoformat()}
    if isinstance(value, Decimal):
        return {'decimal': str(value)}
    raise TypeError('Unsupported database value')


def summary(conn, deadline=None):
    """Hash every persisted column, including photos, documents and financial bytes."""
    from psycopg import sql
    tables = conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename").fetchall()
    if not {'clients', 'documents', 'schema_migrations'} <= {row[0] for row in tables}:
        raise recovery.RecoveryError('Expected a migrated ECC database')
    counts, hashes, columns = {}, {}, {}
    for (table,) in tables:
        names = [row[0] for row in conn.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name=%s ORDER BY ordinal_position", (table,))]
        columns[table] = names
        fields = sql.SQL(',').join(map(sql.Identifier, names))
        statement = sql.SQL('SELECT {} FROM public.{} ORDER BY {}').format(fields, sql.Identifier(table), fields)
        checksum, count = hashlib.sha256(), 0
        with conn.cursor(name='ecc_evidence_' + uuid.uuid4().hex) as cursor:
            cursor.execute(statement)
            for row in cursor:
                if deadline is not None and time.monotonic() >= deadline:
                    raise TimeoutError('Recovery verification deadline exceeded')
                checksum.update(json.dumps(list(row), ensure_ascii=False, separators=(',', ':'),
                                           allow_nan=False, default=canonical).encode())
                checksum.update(b'\n')
                count += 1
        counts[table], hashes[table] = count, checksum.hexdigest()
    return {'tableCounts': counts, 'tableRowsSha256': hashes, 'columns': columns}


def check_source(conn):
    # ECC uses public and BYTEA, not external schemas or PostgreSQL large objects.
    extra = conn.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname<>'public' AND n.nspname<>'information_schema' AND n.nspname !~ '^pg_' AND c.relkind IN ('r','p','v','m','S','f')").fetchone()[0]
    if extra or conn.execute('SELECT count(*) FROM pg_largeobject_metadata').fetchone()[0]:
        raise recovery.RecoveryError('Unsupported extra schemas or large objects; use a full administrator backup')


def backup_once(url, directory, now=None, timeout=900):
    directory, now = Path(directory).absolute(), now or recovery.utc_now()
    deadline = time.monotonic() + timeout
    with recovery.manager_lock(directory):
        # A killed dump can leave an unpublished temporary file. The directory
        # lock proves no other recovery job is currently using these files.
        for abandoned in directory.glob('.postgres-copy-*'):
            if abandoned.is_file() and not abandoned.is_symlink():
                abandoned.unlink()
        fd, name = tempfile.mkstemp(prefix='.postgres-copy-', dir=directory)
        os.close(fd)
        temporary = Path(name)
        target = directory / ('ecc-' + now.strftime('%Y%m%dT%H%M%S%fZ') + '-' + uuid.uuid4().hex[:8] + '.pgdump')
        try:
            with connect(url, timeout) as conn, conn.transaction():
                conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
                check_source(conn)
                tables = conn.execute("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename").fetchall()
                from psycopg import sql
                for (table,) in tables:
                    conn.execute(sql.SQL('LOCK TABLE public.{} IN ACCESS SHARE MODE').format(sql.Identifier(table)))
                snapshot = conn.execute('SELECT pg_export_snapshot()').fetchone()[0]
                identity = database_identity(conn)
                evidence = summary(conn, deadline)
                run_tool('pg_dump', ['--format=custom', '--no-owner', '--no-acl', '--schema=public',
                                    '--strict-names', '--snapshot=' + snapshot, '--file=' + str(temporary),
                                    '--lock-wait-timeout=10s'], url, max(0.01, deadline-time.monotonic()))
            with temporary.open('rb') as stream:
                os.fsync(stream.fileno())
            metadata = {'format': 2, 'engine': 'postgresql', 'file': target.name,
                        'createdAt': now.isoformat(), 'bytes': temporary.stat().st_size,
                        'sha256': recovery.digest(temporary), 'sourceIdentity': identity,
                        'evidence': evidence}
            # Validate archive structure before publishing it. Only a restore drill
            # is allowed to mark logical recovery as successful.
            run_tool('pg_restore', ['--list', temporary], timeout=timeout)
            os.link(temporary, target)
            recovery.atomic_json(recovery.manifest_path(target), metadata)
            verify(target, timeout)
            recovery.atomic_json(directory / 'backup-status.json',
                                 {'lastSuccess': now.isoformat(), 'snapshot': target.name, 'sha256': metadata['sha256'], 'engine': 'postgresql'})
            return target
        except BaseException:
            target.unlink(missing_ok=True)
            recovery.manifest_path(target).unlink(missing_ok=True)
            raise
        finally:
            temporary.unlink(missing_ok=True)


def verify(snapshot, timeout=900):
    snapshot = Path(snapshot).absolute()
    manifest = recovery.manifest_path(snapshot)
    if snapshot.is_symlink() or manifest.is_symlink() or not snapshot.is_file():
        raise recovery.RecoveryError('Archive and manifest must be regular files')
    metadata = json.loads(manifest.read_text())
    if not isinstance(metadata, dict):
        raise recovery.RecoveryError('Invalid PostgreSQL manifest')
    evidence = metadata.get('evidence')
    if (metadata.get('format') != 2 or metadata.get('engine') != 'postgresql'
            or metadata.get('file') != snapshot.name
            or not re.fullmatch(r'[0-9a-f]{64}', str(metadata.get('sourceIdentity', '')))
            or not isinstance(evidence, dict)):
        raise recovery.RecoveryError('Unsupported or mismatched PostgreSQL manifest')
    counts, hashes, columns = (evidence.get(key) for key in ('tableCounts', 'tableRowsSha256', 'columns'))
    if (not all(isinstance(value, dict) and value for value in (counts, hashes, columns))
            or set(counts) != set(hashes) or set(counts) != set(columns)
            or any(type(value) is not int or value < 0 for value in counts.values())
            or any(not re.fullmatch(r'[0-9a-f]{64}', str(value)) for value in hashes.values())
            or any(not isinstance(value, list) or not value or not all(isinstance(item, str) for item in value) for value in columns.values())):
        raise recovery.RecoveryError('Invalid PostgreSQL recovery evidence')
    created = datetime.fromisoformat(metadata.get('createdAt', ''))
    if created.tzinfo is None:
        raise recovery.RecoveryError('Backup timestamp requires a timezone')
    if snapshot.stat().st_size != metadata.get('bytes') or recovery.digest(snapshot) != metadata.get('sha256'):
        raise recovery.RecoveryError('PostgreSQL archive checksum mismatch')
    run_tool('pg_restore', ['--list', snapshot], timeout=timeout)
    return metadata


def require_empty(conn):
    objects = conn.execute("SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname<>'information_schema' AND n.nspname !~ '^pg_' AND c.relkind IN ('r','p','v','m','S','f')").fetchone()[0]
    routines = conn.execute("SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname<>'information_schema' AND n.nspname !~ '^pg_'").fetchone()[0]
    if objects or routines or conn.execute('SELECT count(*) FROM pg_largeobject_metadata').fetchone()[0]:
        raise recovery.RecoveryError('Restore destination must be an isolated empty database')


def validate_sequences(conn):
    from psycopg import sql
    columns = conn.execute("SELECT table_name,column_name FROM information_schema.columns WHERE table_schema='public' AND (is_identity='YES' OR column_default LIKE 'nextval(%%')").fetchall()
    for table, column in columns:
        sequence = conn.execute('SELECT pg_get_serial_sequence(%s,%s)', ('public.' + table, column)).fetchone()[0]
        # Resolve the server-returned sequence name rather than interpolating it.
        schema, name = conn.execute('SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.oid=%s::regclass', (sequence,)).fetchone()
        last, called = conn.execute(sql.SQL('SELECT last_value,is_called FROM {}.{}').format(sql.Identifier(schema), sql.Identifier(name))).fetchone()
        maximum = conn.execute(sql.SQL('SELECT max({}) FROM public.{}').format(sql.Identifier(column), sql.Identifier(table))).fetchone()[0]
        if maximum is not None and (last < maximum or last == maximum and not called):
            raise recovery.RecoveryError('Restored identity sequence would reuse an existing identifier')


def restore(snapshot, destination, timeout=900, cleanup=False):
    snapshot = Path(snapshot).absolute()
    with recovery.manager_lock(snapshot.parent):
        metadata = verify(snapshot, timeout)
        with connect(destination, timeout) as conn:
            conn.execute('SELECT pg_advisory_lock(1162036051)')
            # This connection holds the destination lock throughout pg_restore.
            if database_identity(conn) == metadata['sourceIdentity']:
                raise recovery.RecoveryError('Cannot restore over the source database')
            if cleanup and not conn.execute('SELECT current_database()').fetchone()[0].startswith('ecc_restore_'):
                raise recovery.RecoveryError('Drills require an empty database named ecc_restore_*')
            require_empty(conn)
            started = time.monotonic()
            try:
                # No --clean, --create or trigger disabling: existing data is never
                # overwritten, and errors roll back the restore transaction.
                # Fresh PostgreSQL databases already contain public. Skip only
                # its CREATE SCHEMA TOC entry; keep every table/function/data item.
                listing = run_tool('pg_restore', ['--list', snapshot], timeout=timeout).decode('utf-8')
                listing = '\n'.join(line for line in listing.splitlines()
                                    if not re.match(r'^\d+; \d+ \d+ SCHEMA - public(?: |$)', line))
                with tempfile.TemporaryDirectory(prefix='.postgres-restore-', dir=snapshot.parent) as work:
                    plan = Path(work) / 'restore.list'
                    plan.write_text(listing + '\n')
                    plan.chmod(0o600)
                    run_tool('pg_restore', ['--dbname=', '--single-transaction', '--exit-on-error',
                                            '--no-owner', '--no-acl', '--use-list=' + str(plan), snapshot], destination, timeout)
                with conn.transaction():
                    conn.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY')
                    restored = summary(conn, started + timeout)
                    if restored != metadata['evidence']:
                        raise recovery.RecoveryError('Restored records or uploaded bytes differ')
                    validate_sequences(conn)
                result = {'sourceSnapshot': snapshot.name, 'sha256': metadata['sha256'],
                          'verifiedAt': recovery.utc_now().isoformat(),
                          'durationSeconds': round(time.monotonic()-started, 3),
                          'engine': 'postgresql', 'logicalRecoveryVerified': True,
                          'tableCounts': restored['tableCounts']}
            finally:
                if cleanup:
                    # Only the dedicated, initially empty drill database is reset.
                    # A regular disaster recovery restore keeps its recovered data.
                    with conn.transaction():
                        conn.execute('DROP SCHEMA public CASCADE')
                        conn.execute('CREATE SCHEMA public')
            return result


def drill(snapshot, destination=None, timeout=900):
    destination = destination or os.environ.get('RESTORE_TEST_DATABASE_URL')
    if not destination:
        raise recovery.RecoveryError('RESTORE_TEST_DATABASE_URL is required for PostgreSQL restore drills')
    evidence = restore(snapshot, destination, timeout, cleanup=True)
    recovery.atomic_json(Path(snapshot).absolute().parent / 'restore-drill-status.json',
                         {**evidence, 'snapshot': Path(snapshot).name})
    return evidence
