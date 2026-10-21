#!/usr/bin/env python3
"""SQLite/PostgreSQL snapshots, verified recovery and automatic tiered retention.

PostgreSQL requires psycopg and pg_dump/pg_restore. Restore never overwrites data.
Run `python3 scripts/recovery.py --help` for commands. POSIX file locks serialize
managers sharing a backup directory. The API can continue writing during backup.
"""
import argparse
from contextlib import closing, contextmanager
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import signal
import sqlite3
import tempfile
import threading
import time
from urllib.parse import quote
import uuid


class RecoveryError(ValueError):
    pass


def utc_now():
    return datetime.now(timezone.utc)


def sync_directory(directory):
    fd = os.open(directory, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def readonly(path):
    return sqlite3.connect('file:' + quote(str(path.resolve()), safe='/') + '?mode=ro', uri=True, timeout=10)


def validate(path):
    if not path.is_file() or path.is_symlink():
        raise RecoveryError('Expected an existing regular database file')
    with closing(readonly(path)) as conn:
        if conn.execute('PRAGMA integrity_check').fetchall() != [('ok',)]:
            raise RecoveryError('SQLite integrity check failed')
        if conn.execute('PRAGMA foreign_key_check').fetchall():
            raise RecoveryError('SQLite foreign-key check failed')
        # Force schema parsing; reject empty/non-SQLite files too.
        if not conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
            raise RecoveryError('Database contains no tables')


def atomic_json(path, data):
    fd, name = tempfile.mkstemp(prefix='.metadata-', dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream, sort_keys=True)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
        sync_directory(path.parent)
    finally:
        temporary.unlink(missing_ok=True)


@contextmanager
def manager_lock(directory):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Do not silently chmod existing operator-managed directories.
    flags = os.O_CREAT | os.O_RDWR | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(directory / '.recovery.lock', flags, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RecoveryError('Another recovery operation is already running') from exc
        yield
    finally:
        os.close(fd)


def copy_verified(source, target, timeout=120):
    source, target = Path(source).absolute(), Path(target).absolute()
    if not source.is_file() or source.is_symlink():
        raise RecoveryError('Source must be an existing regular database file')
    if source.resolve() == target.resolve() or target.exists() or target.is_symlink():
        raise RecoveryError('Restore/backup destination must be a new file')
    # A sidecar can contain newer committed data even if the main file was removed.
    if any(Path(str(target) + suffix).exists() for suffix in ('-wal', '-shm', '-journal')):
        raise RecoveryError('Destination has SQLite sidecars; choose a fresh path')
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix='.sqlite-copy-', dir=target.parent)
    os.close(fd)
    temporary = Path(name)
    deadline = time.monotonic() + timeout
    def progress(_status, _remaining, _total):
        if time.monotonic() >= deadline:
            raise TimeoutError('SQLite backup deadline exceeded')
    try:
        with closing(readonly(source)) as src, closing(sqlite3.connect(temporary)) as dst:
            src.backup(dst, pages=256, progress=progress, sleep=0.05)
            # Consolidate destination storage in one portable database file.
            dst.execute('PRAGMA journal_mode=DELETE')
        validate(temporary)
        with temporary.open('rb') as stream:
            os.fsync(stream.fileno())
        os.link(temporary, target)  # Atomic publish; concurrent creators cannot be overwritten.
        sync_directory(target.parent)
    finally:
        temporary.unlink(missing_ok=True)
        for suffix in ('-wal', '-shm', '-journal'):
            Path(str(temporary) + suffix).unlink(missing_ok=True)
    return target


def manifest_path(snapshot):
    return Path(str(snapshot) + '.json')


def verify(snapshot):
    if str(snapshot).endswith('.pgdump'):
        import postgres_recovery
        return postgres_recovery.verify(snapshot)
    snapshot = Path(snapshot).absolute()
    metadata_path = manifest_path(snapshot)
    if metadata_path.is_symlink():
        raise RecoveryError('Snapshot manifest must not be a symlink')
    metadata = json.loads(metadata_path.read_text())
    if metadata.get('format') != 1 or metadata.get('file') != snapshot.name:
        raise RecoveryError('Unsupported or mismatched snapshot manifest')
    if snapshot.is_symlink() or snapshot.stat().st_size != metadata.get('bytes'):
        raise RecoveryError('Snapshot size mismatch')
    if digest(snapshot) != metadata.get('sha256'):
        raise RecoveryError('Snapshot checksum mismatch')
    validate(snapshot)
    return metadata


def backup_once(database, directory, now=None, timeout=120):
    if str(database).startswith(('postgresql://', 'postgres://')):
        import postgres_recovery
        return postgres_recovery.backup_once(database, directory, now, timeout)
    directory = Path(directory).absolute()
    now = now or utc_now()
    with manager_lock(directory):
        filename = 'ecc-' + now.strftime('%Y%m%dT%H%M%S%fZ') + '-' + uuid.uuid4().hex[:8] + '.sqlite3'
        target = directory / filename
        copy_verified(database, target, timeout)
        try:
            metadata = {'format': 1, 'file': filename, 'createdAt': now.isoformat(),
                        'bytes': target.stat().st_size, 'sha256': digest(target)}
            atomic_json(manifest_path(target), metadata)
            verify(target)
        except BaseException:
            target.unlink(missing_ok=True)
            manifest_path(target).unlink(missing_ok=True)
            raise
        atomic_json(directory / 'backup-status.json',
                    {'lastSuccess': now.isoformat(), 'snapshot': filename, 'sha256': metadata['sha256']})
        return target


def retain(directory, latest=24, daily=7, weekly=4, monthly=12):
    if latest < 1 or min(daily, weekly, monthly) < 0:
        raise RecoveryError('Retention requires latest>=1 and nonnegative calendar counts')
    directory = Path(directory).absolute()
    with manager_lock(directory):
        snapshots = []
        # Ignore interrupted copies, unrecognized files and safety snapshots.
        for path in [*directory.glob('ecc-*.sqlite3'), *directory.glob('ecc-*.pgdump')]:
            metadata = verify(path)  # Corruption stops deletion; retain recovery evidence.
            created = datetime.fromisoformat(metadata['createdAt']).astimezone(timezone.utc)
            snapshots.append((created, path))
        snapshots.sort(reverse=True)
        keep = {path for _, path in snapshots[:latest]}
        for count, key in [(daily, lambda d: d.date()),
                           (weekly, lambda d: d.isocalendar()[:2]),
                           (monthly, lambda d: (d.year, d.month))]:
            periods = set()
            for created, path in snapshots:
                period = key(created)
                if period not in periods and len(periods) < count:
                    periods.add(period)
                    keep.add(path)
        # Keep the last recovery point that was successfully drilled or copied
        # off-site even when newer backups cannot complete their restore checks.
        for marker, key in [('restore-drill-status.json', 'snapshot'), ('offsite-status.json', 'snapshot')]:
            status = directory / marker
            if status.exists():
                metadata = json.loads(status.read_text())
                name = metadata.get(key)
                keep.update(path for _, path in snapshots if path.name == name)
        deleted = []
        for _, path in snapshots:
            if path not in keep:
                path.unlink()
                manifest_path(path).unlink()
                deleted.append(path.name)
        sync_directory(directory)
        return deleted


def restore(snapshot, destination, timeout=120):
    if str(snapshot).endswith('.pgdump'):
        import postgres_recovery
        return postgres_recovery.restore(snapshot, destination, timeout)
    snapshot = Path(snapshot).absolute()
    destination = Path(destination).absolute()
    with manager_lock(snapshot.parent):
        metadata = verify(snapshot)
        copy_verified(snapshot, destination, timeout)
        # Return evidence without publishing operational secrets or source paths.
        return {'sourceSnapshot': snapshot.name, 'sha256': digest(destination),
                'snapshotSha256': metadata['sha256'], 'restoredAt': utc_now().isoformat()}



def database_summary(path):
    if str(path).endswith('.pgdump'):
        return verify(path)['evidence']
    with closing(readonly(path)) as conn:
        tables = [row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name")]
        counts = {table: conn.execute('SELECT count(*) FROM "' + table.replace('"', '""') + '"').fetchone()[0]
                  for table in tables}
        files_hash = hashlib.sha256()
        if 'documents' in tables:
            columns = {row[1] for row in conn.execute('PRAGMA table_info(documents)')}
            if {'id', 'content'} <= columns:
                for ident, content in conn.execute('SELECT id,content FROM documents ORDER BY id'):
                    content = content or b''
                    files_hash.update(str(ident).encode() + b':' + str(len(content)).encode() + b':')
                    files_hash.update(content)
        evidence = {'tableCounts': counts, 'documentBytesSha256': files_hash.hexdigest()}
        financial_hash = hashlib.sha256()
        if 'financial_files' in tables:
            for ident, content in conn.execute('SELECT id,content FROM financial_files ORDER BY id'):
                financial_hash.update(str(ident).encode()+b':'+str(len(content)).encode()+b':'+content)
        evidence['financialFileBytesSha256'] = financial_hash.hexdigest()
        return evidence


def drill(snapshot):
    """Restore to private temporary storage and compare logical recovery evidence."""
    if str(snapshot).endswith('.pgdump'):
        import postgres_recovery
        return postgres_recovery.drill(snapshot)
    snapshot = Path(snapshot).absolute()
    with manager_lock(snapshot.parent):
        metadata = verify(snapshot)
        started = time.monotonic()
        with tempfile.TemporaryDirectory(prefix='ecc-restore-drill-') as directory:
            restored = copy_verified(snapshot, Path(directory) / 'restored.sqlite3')
            original_summary = database_summary(snapshot)
            if database_summary(restored) != original_summary:
                raise RecoveryError('Restored records or document bytes differ')
        evidence = {'snapshot': snapshot.name, 'sha256': metadata['sha256'],
                    'verifiedAt': utc_now().isoformat(),
                    'durationSeconds': round(time.monotonic()-started, 3), **original_summary}
        atomic_json(snapshot.parent / 'restore-drill-status.json', evidence)
        return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    for name in ('backup', 'run'):
        command = commands.add_parser(name)
        command.add_argument('--database', default=os.environ.get('DATABASE_URL') or os.environ.get('DATABASE_PATH'), required=not (os.environ.get('DATABASE_URL') or os.environ.get('DATABASE_PATH')))
        command.add_argument('--directory', default=os.environ.get('BACKUP_DIR', '/backups'))
        command.add_argument('--latest', type=int, default=24)
        command.add_argument('--daily', type=int, default=7)
        command.add_argument('--weekly', type=int, default=4)
        command.add_argument('--monthly', type=int, default=12)
        command.add_argument('--timeout', type=float, default=120)
        if name == 'run':
            command.add_argument('--interval', type=float, default=3600)
            command.add_argument('--drill-interval', type=float, default=86400)
    command = commands.add_parser('verify')
    command.add_argument('snapshot')
    command = commands.add_parser('drill')
    command.add_argument('snapshot')
    command = commands.add_parser('restore')
    command.add_argument('snapshot')
    command.add_argument('--destination', help='SQLite path; PostgreSQL uses RESTORE_DATABASE_URL')
    command.add_argument('--timeout', type=float, default=120)
    args = parser.parse_args()
    if args.command in ('verify', 'drill'):
        result = verify(args.snapshot) if args.command == 'verify' else drill(args.snapshot)
        print(json.dumps(result, sort_keys=True))
        return
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error('timeout must be positive')
    if args.command == 'restore':
        destination = os.environ.get('RESTORE_DATABASE_URL') if args.snapshot.endswith('.pgdump') else args.destination
        if not destination:
            parser.error('Set RESTORE_DATABASE_URL for PostgreSQL or --destination for SQLite')
        print(json.dumps(restore(args.snapshot, destination, args.timeout), sort_keys=True))
        return
    if args.latest < 1 or min(args.daily, args.weekly, args.monthly) < 0:
        parser.error('retention requires latest>=1 and nonnegative calendar counts')
    if args.command == 'run' and (not all(math.isfinite(v) for v in (args.interval, args.drill_interval)) or min(args.interval, args.drill_interval) < 60):
        parser.error('automatic backup and drill intervals must be at least 60 seconds')
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    last_drill = None
    while not stop.is_set():
        try:
            # Validate/prune before creating another snapshot so a persistent
            # retention failure cannot fill the disk with repeated retries.
            deleted = retain(args.directory, args.latest, args.daily, args.weekly, args.monthly)
            target = backup_once(args.database, args.directory, timeout=args.timeout)
            if args.command == 'run' and (last_drill is None or time.monotonic()-last_drill >= args.drill_interval):
                drill(target)
                last_drill = time.monotonic()
            deleted += retain(args.directory, args.latest, args.daily, args.weekly, args.monthly)
            print(json.dumps({'event': 'backup-success', 'snapshot': target.name,
                              'pruned': len(deleted)}), flush=True)
        except Exception as exc:
            print(json.dumps({'event': 'backup-failed', 'error': type(exc).__name__}), flush=True)
            if args.command == 'backup':
                raise
            stop.wait(min(args.interval, 60))
            continue
        if args.command == 'backup':
            return
        stop.wait(args.interval)


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        raise SystemExit('Recovery failed: ' + type(exc).__name__ + '; details withheld') from None
