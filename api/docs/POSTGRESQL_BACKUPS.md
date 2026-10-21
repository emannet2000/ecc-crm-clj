# PostgreSQL backups and restore on Render

The implementation is prepared in this checkout. It has not been deployed to Render. A normal PostgreSQL connection is required to run the real recovery tests and validate the hosted configuration. Local passing unit tests are not evidence of a successful hosted restore.

## What is backed up

`recovery.py` selects PostgreSQL when `DATABASE_URL` is set. It uses a custom-format `pg_dump` archive and an exported repeatable-read snapshot. Verification hashes every persisted table row and column from that same snapshot, including photos/PDFs in `documents.content`, photo links, financial attachments, payment entries and audit history. Concurrent committed/uncommitted changes after that snapshot are excluded consistently.

Archives and manifests are private files. SHA-256 detects changed bytes; a restore drill checks the logical contents and ID sequences. Archive listing/checksum verification alone is not a restore test. ECC's public schema and BYTEA uploads are supported; non-public data schemas or PostgreSQL large objects cause backup failure rather than being silently omitted. PostgreSQL roles, provider settings, application configuration and external accounts are not part of this database backup.

## Render setup

1. Create a **background worker** from the same repository, using the API directory as build context and `deploy/Dockerfile.postgres-backup` as Dockerfile. Set the non-secret build argument `POSTGRES_VERSION` to your database's major version. `pg_dump` must not be older than the server; use the matching major for dump/restore and the restore database.
2. Attach a persistent disk at `/var/backups/ecc`. Choose capacity for multiple complete archives plus working space. A Render cron job has no persistent disk; this worker keeps retention and monitoring evidence across restarts.
3. Supply `DATABASE_URL` using the source database's internal URL, with TLS. Use a read-capable backup account that can read all ECC tables and sequences. The backup does not write to the source database.
4. Provision a **separate empty database** with a database name beginning `ecc_restore_`. Set `RESTORE_TEST_DATABASE_URL` to it. Do not connect the API, mail/scanning workers or Flor to this database. The restore account must own its public schema and be able to create schema objects. After a drill, the worker clears only this dedicated, initially empty test database.
5. Configure a dedicated off-site Restic repository, storage credentials and a private encryption password. Set `RESTIC_PASSWORD` as a Render secret environment variable, or provide a private `RESTIC_PASSWORD_FILE`. The worker entry point creates a temporary mode-0600 password file for the environment-variable option. Keep a recoverable copy of the encryption key outside Render.
6. Configure `HEALTH_URL` and an HTTPS `ALERT_WEBHOOK_URL`. Optional `ALERT_TOKEN_FILE` supplies a bearer token. See `deploy/postgres-backup.env.example`; replace all example values privately in Render.
7. Initialize the dedicated empty repository once with `python3 scripts/render_backup_worker.py init-repository`. Never reuse a repository containing unrelated services with this retention policy.
8. Start with the default Docker command. It backs up hourly, restores and compares each backup in the test database, restores the encrypted off-site copy to check its bytes, applies retention, and monitors every five minutes. Verify an actual failure alert and an independent external uptime check; a stopped worker cannot alert about itself.

The worker keeps 24 recent, 7 daily, 4 weekly and 12 monthly points in UTC. Corrupt evidence stops pruning. Local retention also protects the last recorded successful drill and off-site recovery point. Off-site retention groups the dedicated repository by its recovery tag, so changing archive paths or worker hostnames do not defeat pruning.

Check `backup-job-status.json`, `backup-status.json`, `restore-drill-status.json`, `offsite-status.json` and `operations-status.json` on the persistent disk. Success requires the full job and recent restore/off-site verification, not merely an existing `.pgdump` file. The monitor reports failed/interrupted jobs, stale/missing evidence, API incompatibility, stuck mail/scans, local backup storage pressure, and alert delivery failure. Monitor database capacity separately in Render.

## One-shot commands

Run from the API/release directory after setting secrets in the environment. Do not put connection URLs or encryption passwords directly in shell command arguments/history.

```sh
python3 scripts/render_backup_worker.py backup
python3 scripts/recovery.py verify /var/backups/ecc/ecc-TIMESTAMP-ID.pgdump
python3 scripts/recovery.py drill /var/backups/ecc/ecc-TIMESTAMP-ID.pgdump
python3 scripts/render_backup_worker.py check
python3 scripts/render_backup_worker.py alert-test
```

For a local-only test without off-site upload, use `python3 scripts/operations.py backup --local-only`. This still requires the separate drill database. It does not verify off-site protection.

## Disaster recovery

1. Pause API traffic and all writers/delivery workers. Keep the original database and deployment intact.
2. Recover a trusted archive **and its matching `.pgdump.json` manifest** from the encrypted Restic repository. Example, with private Restic configuration already loaded: `restic snapshots --tag ecc-recovery`, then `restic restore SNAPSHOT_ID --target /private/recovery`. The original archive directory tree is preserved under that target.
3. Create a new isolated, empty PostgreSQL database. Set its URL privately as `RESTORE_DATABASE_URL`. Keep it separate from the live source and the drill database.
4. Run the restore:

```sh
python3 scripts/recovery.py restore /private/recovery/PATH/ecc-TIMESTAMP-ID.pgdump --timeout 900
```

The script verifies the archive before writing, rejects the source or an occupied destination, and uses a single-transaction `pg_restore` without `--clean` or `--create`. It compares every recovered row and checks identity sequences. It retains a normal restored database for inspection; automatic schema cleanup applies only to dedicated drills. If logical verification fails after the restore transaction, treat the new database as unverified and do not connect the app to it.

5. Check students, permissions, photo/PDF downloads, outstanding requirements, invoices and balances using the matching tested API release. Rotate JWT secrets to invalidate recovered sessions. Review queued mail/jobs before re-enabling workers, to avoid repeating messages from older state.
6. Switch the API **and every worker** to the recovered database only after those checks pass. Reconfigure backup source and run another successful backup/restore drill. Restore-point recovery loses changes made after the snapshot; this logical export system does not provide point-in-time recovery.

Only restore trusted ECC archives: PostgreSQL dumps contain executable schema/function definitions. Local archives are compressed but not encrypted by pg_dump; protect the persistent disk and rely on configured Restic encryption for the off-site copies.

## Required tests before release

- `python3 -m unittest discover -s scripts -p 'test_*.py'`: existing unit/regression checks plus 1,000 reproducible generated recovery cases.
- `python3 scripts/postgres_recovery_integration.py`: uses only `ECC_TEST_DATABASE_URL` pointing to a disposable database named `ecc_test`, with CREATEDB permission. Creates/drops unique test databases, exercises real pg_dump/pg_restore, verifies exact bytes/balances and concurrent snapshots, and rejects unsafe targets/corruption. Missing infrastructure fails this check.
- `bash scripts/check.sh`: the complete gate requires these integration checks before it seals a release. A real Render restore drill and alert test are additional deployment acceptance steps.

Sources: [PostgreSQL pg_dump](https://www.postgresql.org/docs/current/app-pgdump.html), [pg_restore](https://www.postgresql.org/docs/current/app-pgrestore.html), [Render backups/recovery](https://render.com/docs/postgresql-backups), [Render disks](https://render.com/docs/disks), [Render cron limitations](https://render.com/docs/cronjobs). Render's provider recovery features depend on the actual database plan and must be verified separately.
