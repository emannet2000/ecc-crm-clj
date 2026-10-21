# Production recovery, monitoring and browser verification

## What is implemented and what requires the production host

The repository provides timers, workers, an installer, encrypted off-site upload
and remote restore verification, local restore drills, failure/recovery alerts,
and an isolated live browser suite. These files do not activate services on their
own. This workspace cannot access the systemd service bus or launch Chromium/Brave;
no production schedule, remote repository or alert destination has been activated
or verified from here. No production credentials have been supplied.

Before activation, provide the production host/service account, off-site repository
and alert webhook. Production verification must run on that host and the browser
suite must run in the configured hosted CI runner (or another unrestricted test host).

## Installation on a production host

1. Back up the live database. Install the reviewed application at `/opt/ecc/api`,
   follow the verified release preparation below, apply migrations through
   `0014_business_clock.sql`, and restart
   the API with the new binary and frontend.
2. Install Python 3 and restic. Create the `ecc` service account and private writable
   `/var/lib/ecc` and `/var/backups/ecc` directories. Configure the API's own service
   with its persistent database, production JWT secret, HTTPS public origin and demo
   seeding disabled. Set `CRM_TIMEZONE=Asia/Manila` (default) or `UTC`; see [CLOCK.md](CLOCK.md).
3. Copy `deploy/recovery.env.example` to `/etc/ecc/recovery.env`, and
   `deploy/workers.env.example` to `/etc/ecc/workers.env`. Replace the example values.
   Use a real off-site restic backend, not another directory on the same host.
   Configure SMTP and a reachable ClamAV daemon for the workers.
4. Initialize the encrypted restic repository once using `restic init` with the
   configured repository and private password file. Keep its password/key separately
   from this server. Configure provider credentials privately; never commit them.
   The example uses S3-compatible storage. For SFTP, supply the service account's
   SSH configuration, key and known hosts through paths under `/etc`, because these
   units restrict home-directory access.
5. Set an HTTPS alert webhook and a private bearer-token file. The endpoint receives
   JSON with `service`, `event`, `problems` and `checkedAt`. It must accept an HTTP
   POST and return a 2xx response. Redirects are rejected. Payloads omit customer
   names, email addresses, credentials and database paths.
6. Make environment and secret files readable by the `ecc` service account only
   (for example owner `ecc`, mode `0600`). Restrict `/etc/ecc` appropriately. The
   repository password file must have no group/world permissions.
7. Run `sudo bash deploy/install-operations.sh` on the production host. It installs
   units, runs an actual backup/upload/remote restore drill as `ecc`, and verifies
   delivery of a test alert before enabling timers. It starts the updated mail and
   scanning workers. Only after verification does it stop/disable an older
   `ecc-recovery.service` local-only loop.

If verification fails, the installer exits before enabling the replacement timers.
An existing local-only manager is left running until the replacement succeeds.
Newly installed unit files remain available for inspection and diagnosis. The
installer does not initialize a remote repository or overwrite a live database.

## Schedules and evidence

- `ecc-verified-backup.timer`: hourly, catches up after downtime. Every successful
  job creates a consistent SQLite snapshot including committed WAL data, verifies
  integrity/foreign keys/checksum, restores it privately, uploads it with restic,
  restores that exact remote snapshot, and checks its checksum and logical contents.
- `ecc-monitor.timer`: every five minutes, persistent across downtime. Checks for
  missing/stale local backups, missing/stale restore drills, missing/stale verified
  off-site copies, failed/interrupted backup jobs, exhausted or >30-minute queued
  email, failed scans, and >30-minute pending/scanning documents and financial files.
- Backup/drill/off-site evidence becomes unhealthy after two hours without success.
  Backup failures persist until a succeeding job. Alerts retry on delivery failure,
  repeat at most hourly for an unchanged problem, and emit a recovery notification.
- `ecc-mail.service` and `ecc-scan.service`: supervised workers with restart on exit.
  The scanner handles client documents and expense evidence. Files remain quarantined
  while Pending/Scanning/Error/Infected; only Clean evidence can be downloaded.

Inspect:

```sh
systemctl status ecc-verified-backup.timer ecc-monitor.timer ecc-mail ecc-scan
journalctl -u ecc-verified-backup.service -u ecc-monitor.service --since today
```

Status files in the backup directory include `backup-status.json`,
`restore-drill-status.json`, `offsite-status.json`, `backup-job-status.json`, and
`operations-status.json`. They are written atomically with private permissions.
Recovery evidence includes counts of financial tables and hashes of client-document
and expense-attachment contents.

Local retention keeps 24 recent, 7 daily, 4 weekly and 12 monthly snapshots. Off-site
snapshots are retained; configure an independent provider/restic retention policy
when the production destination is chosen. The application does not automatically
prune remote recovery evidence. Monitor storage/quota on the selected destination.

The restic integration follows its [scripting interface](https://restic.readthedocs.io/en/stable/075_scripting.html)
and [snapshot restore layout](https://restic.readthedocs.io/en/stable/050_restore.html).

## Local tests and restore drill

```sh
python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/operations.py backup --database /path/to/test.sqlite3 --directory /tmp/ecc-recovery-test --local-only
python3 scripts/operations.py check --database /path/to/test.sqlite3 --directory /tmp/ecc-recovery-test --local-only
```

`--local-only` is explicit test mode: it makes no off-site or alert-delivery claim.
The Python tests perform real local SQLite backup/restore drills and test the remote
adapter using a fake restic runner. A real off-site restore requires the configured
production repository, restic binary and credentials.

## Browser verification

`scripts/check.sh` runs the original UI/mobile suites and
`test/finance-live.browser.cjs`. The live suite starts a separate API on an ephemeral
loopback port with a disposable SQLite database, creates test-only accounts and
invoices, and uses real browser HTTP/cookies. It verifies partial payment, receipt
reversal, expense submission/approval/payment/reversal, denied payment privileges
(including a direct API bypass attempt), and phone-width financial pages. It never
connects to or mutates the production CRM.

```sh
export ECC_API_BIN="$(cabal list-bin exe:ecc-crm-api)"
export CHROME_PATH=/path/to/chromium
node --test test/browser-acceptance.test.cjs scripts/mobile.browser.cjs test/finance-live.browser.cjs
```

The existing `.github/workflows/ci.yml` provisions Chrome on Ubuntu and runs the full
check script. If this checkout is the `api/` subdirectory of a larger Git repository,
install the workflow at the Git root with `scripts/install-ci.sh /path/to/repository`.
Browser screenshots are uploaded with CI diagnostics. A prepared workflow is not
proof of a successful hosted run; inspect the actual run results before production.

## Release preparation and operational checks

Use the stopped-writer, synchronized-clock, verified off-site restore procedure in
[RELIABILITY.md](RELIABILITY.md) before applying production migrations. Production
startup now requires a sealed release manifest for the exact binary/assets/schema
and refuses pending migrations. The complete quality gate must run on a browser-
capable host; this workspace does not produce a successful production seal.

Configure `HEALTH_URL` to the public HTTPS `/api/ready` endpoint. The monitor checks
its status and application contract, plus database/backup volume free space (256 MiB
or 5%, whichever is larger). Install a separate external uptime monitor to detect
complete host failure. Existing backup, mail and scanning alerts remain active.
