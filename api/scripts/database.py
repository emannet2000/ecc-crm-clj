"""Database access shared by the mail, quarantine and workflow workers."""
import os
import re
import sqlite3
from urllib.parse import urlsplit, parse_qsl, urlencode, urlunsplit


class DatabaseError(RuntimeError):
    pass


def secure_url(url, production):
    parts = urlsplit(url)
    if parts.scheme not in ('postgresql', 'postgres') or not parts.hostname or not parts.path or parts.fragment:
        raise ValueError('DATABASE_URL must be a PostgreSQL connection URL')
    options = parse_qsl(parts.query, keep_blank_values=True)
    modes = [value for key, value in options if key == 'sslmode']
    if not modes:
        options.append(('sslmode', 'require'))
    elif len(modes) != 1 or modes[0] not in ('require', 'verify-ca', 'verify-full', *(() if production else ('disable', 'allow', 'prefer'))):
        raise ValueError('DATABASE_URL must require TLS in production')
    return urlunsplit(parts._replace(query=urlencode(options)))


def postgres_sql(sql):
    """Translate worker expressions, preserving all SQL string literals."""
    if sql.startswith('PRAGMA '):
        return 'SELECT 1'
    ignore = bool(re.match(r'INSERT OR IGNORE\b', sql, re.I))
    if ignore:
        sql = re.sub(r'^INSERT OR IGNORE\b', 'INSERT', sql, flags=re.I)
    names = {'datetime': 'ecc_datetime', 'date': 'ecc_date', 'strftime': 'ecc_strftime',
             'min': 'least', 'max': 'greatest'}
    parts = re.split(r"('(?:''|[^'])*')", sql)
    for index, part in enumerate(parts):
        part = part.replace('%', '%%')
        if index % 2 == 0:
            part = part.replace('?', '%s')
            part = re.sub(r'\b(' + '|'.join(names) + r')\s*\(',
                          lambda m: names[m[1].lower()] + '(', part, flags=re.I)
        parts[index] = part
    sql = ''.join(parts)
    if ignore:
        match = re.search(r'\bRETURNING\b', sql, re.I)
        position = match.start() if match else len(sql)
        sql = sql[:position] + ' ON CONFLICT DO NOTHING ' + sql[position:]
    return sql


class PostgresConnection:
    def __init__(self, connection):
        self.connection = connection

    def execute(self, sql, parameters=()):
        try:
            if sql == 'BEGIN IMMEDIATE':
                self.connection.execute('BEGIN')
                return self.connection.execute('SELECT pg_advisory_xact_lock(1162036050)')
            return self.connection.execute(postgres_sql(sql), parameters or None)
        except Exception as exc:
            # Server details can include email addresses and document contents.
            raise DatabaseError('PostgreSQL operation failed: ' + type(exc).__name__) from None

    def __enter__(self):
        self.execute('SELECT pg_advisory_xact_lock(1162036050)')
        return self

    def __exit__(self, kind, value, traceback):
        if kind is None:
            self.commit()
        else:
            self.rollback()

    def commit(self):
        self.connection.commit()

    def rollback(self):
        self.connection.rollback()

    def close(self):
        self.connection.close()


def connect():
    url = os.environ.get('DATABASE_URL')
    zone = os.environ.get('CRM_TIMEZONE', 'Asia/Manila')
    if zone not in ('Asia/Manila', 'UTC'):
        raise ValueError('CRM_TIMEZONE must be Asia/Manila or UTC')
    if url is not None:
        url = secure_url(url, os.environ.get('APP_ENV') == 'production')
        try:
            import psycopg
            connection = psycopg.connect(url, connect_timeout=10)
            connection.execute("SELECT set_config('ecc.timezone',%s,false)", (zone,))
            connection.execute("SET TIME ZONE 'UTC'")
            connection.execute("SET lock_timeout='10s'")
            connection.execute("SET statement_timeout='60s'")
            connection.execute("CREATE TEMP TABLE request_context(id BIGINT PRIMARY KEY,actor_id BIGINT,role TEXT,assigned_only TEXT)")
            connection.execute("INSERT INTO request_context VALUES(1,NULL,NULL,'false')")
            connection.commit()
            return PostgresConnection(connection)
        except Exception as exc:
            raise DatabaseError('Cannot open PostgreSQL connection: ' + type(exc).__name__) from None
    path = os.environ.get('DATABASE_PATH')
    if not path:
        raise ValueError('DATABASE_URL or DATABASE_PATH is required')
    connection = sqlite3.connect(path, timeout=10)
    connection.create_function('business_offset', 0, lambda: '0 minutes' if zone == 'UTC' else '480 minutes')
    connection.execute('PRAGMA foreign_keys=ON')
    connection.execute('PRAGMA busy_timeout=10000')
    return connection
