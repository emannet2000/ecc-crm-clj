For Render PostgreSQL, use the [PostgreSQL backup and restore runbook](docs/POSTGRESQL_BACKUPS.md). It covers the worker, encrypted off-site retention, dedicated restore database and required live checks. The SQLite-specific instructions below remain available for local installations.

Automatic backups and verified restoration
=========================================

The new `scripts/recovery.py` manager uses Python's standard library and SQLite's
online backup API. It includes committed WAL data while the application runs,
checks SQLite integrity and foreign keys, writes SHA-256 manifests, publishes
snapshots atomically and serializes recovery operations with a file lock. New
snapshot files have mode 0600; newly created backup directories have mode 0700.

Start an hourly worker with 24 recent, 7 daily, 4 weekly and 12 monthly recovery
points. It also performs an automatic restore drill at startup and every day:

```sh
python3 scripts/recovery.py run \
  --database /var/lib/ecc/ecc-crm.sqlite3 \
  --directory /var/backups/ecc \
  --interval 3600 --drill-interval 86400 \
  --latest 24 --daily 7 --weekly 4 --monthly 12
```

Calendar retention keeps the newest snapshot in each selected UTC day/week/month.
The latest snapshot is always retained. Corruption halts pruning to preserve
recovery evidence. No external Python dependencies are required. Each database
copy has a 120-second deadline; adjust `--timeout` for large databases.

For supervised startup, adapt `deploy/ecc-recovery.service` and
`deploy/recovery.env.example` to your installation's service account and paths.
Place the environment file at `/etc/ecc/recovery.env` with private permissions,
create writable database/backup directories for that account, install the unit,
then run `systemctl enable --now ecc-recovery.service`. The unit is a deployment
template; it has not been installed or enabled here. Do not run two retention
managers against the same directory.

One-shot backup, verification and restore drill:

```sh
python3 scripts/recovery.py backup --database /data/ecc-crm.sqlite3 --directory /backups
python3 scripts/recovery.py verify /backups/ecc-TIMESTAMP-ID.sqlite3
python3 scripts/recovery.py drill /backups/ecc-TIMESTAMP-ID.sqlite3
```

`backup-status.json` records the last verified snapshot. `restore-drill-status.json`
records the most recent successful recovery duration, table counts and document
byte digest. The drill restores into a private temporary database and compares
all table counts and stored document bytes. Monitor both markers for freshness
and alert on `backup-failed` log events. A successful local backup is not evidence
that an off-host upload succeeded.

Recover without overwriting current data:

```sh
python3 scripts/recovery.py restore /backups/ecc-TIMESTAMP-ID.sqlite3 \
  --destination /recovery/ecc-crm.sqlite3
```

Keep the `.sqlite3.json` manifest beside its snapshot. Restore refuses existing
destinations, dangling symlinks and destinations with WAL/journal sidecars. It
verifies the snapshot checksum before writing the destination, then checks the
restored database. For a production switch, stop the API and all database workers,
keep the original database intact, point `DATABASE_PATH` at the recovered database,
rotate `JWT_SECRET` to invalidate sessions recovered from the snapshot, and run
migrations with the intended application version. Check login, staff permissions,
client records and document downloads before restoring traffic and worker delivery.
Restoring old state can also recover previously pending email/jobs; review queues.

Off-host recovery
-----------------

The parent deployment already supplies encrypted restic replication and a
production recovery runbook. Keep off-host storage on a separate host/account and
store the recovery password separately. Archive the new snapshots **and their
manifest sidecars** together; the older stdin-only upload format does not include
these manifests. Use a separate directory if retaining the older backup worker.
The new local worker does not provision an off-host repository or upload data.

Start with hourly backups (up to one hour of lost changes), verify the backup
markers daily, perform a monthly application-level restore drill, and repeat the
drill after schema changes. The automated drill verifies storage recovery;
DNS/TLS, SMTP, permissions and application behavior still need a staging drill.
Snapshots contain client data, documents and account/session state; use encrypted
storage and restrict access. SHA-256 detects accidental corruption, not malicious
changes by someone who can rewrite both the snapshot and its manifest.

Encrypted off-site automation and alerts
---------------------------------------

The newer `ecc-verified-backup.timer` and `ecc-monitor.timer` extend the local-only
manager with encrypted restic uploads, remote restore verification and worker-health
alerts. The older local manager remains available. The installer verifies the
replacement before stopping an installed older loop. See [OPERATIONS.md](OPERATIONS.md)
for configuration, activation, recovery evidence and the tests that can run locally.
No production services or off-site credentials are installed by editing these files.
