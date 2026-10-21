> PostgreSQL deployment: use the [PostgreSQL backup and restore runbook](docs/POSTGRESQL_BACKUPS.md) for the new PostgreSQL backend and Render worker. The SQLite file commands below apply to local SQLite installations. Hosted PostgreSQL restoration and alert delivery still require deployment verification.

# Reliability controls and deployment strategy

These controls reduce the eight failure risks; they do not guarantee that a server,
storage provider, network or administrator can never fail. Source tests are separate
from evidence gathered on the actual production host.

| Failure | Controls in the application/repository | Remaining production verification |
| --- | --- | --- |
| Lost records | Consistent SQLite snapshots, integrity/foreign-key checks, document/evidence hashes, local restore drills, encrypted off-site copies restored and checked byte-for-byte | Activate the timers with real credentials; perform a recovery to another host and keep the encryption key separately |
| Incorrect balances | Integer minor units, immutable ledger entries, exact receipt/invoice binding, revision checks, transaction serialization, unique reversal/payment constraints, reconciliation and closed periods | Review opening data and bank matches; test operator workflows in the browser |
| Private data exposed | Server-side account/record/privilege checks; task lists, reminders, dashboard summaries, panels and direct task updates now enforce owner and assignment scope consistently | Verify the real staff privilege matrix and document downloads after role changes |
| Lost work | Save failures retain fields; navigation/close warnings; stale revisions require conflict review; expired-session drafts remain only in tab memory and restore to the same account and URL | Browser-test expiry while editing; closing/reloading the tab still discards memory-only drafts, and attachments must be selected again |
| Wrong deadlines/reports | Shared business clock, server synchronization, midnight rollover, timezone-aware posting checks/report dates and period locks, explicit legacy unknown dates | Verify host time synchronization and review historical entries near business midnight |
| Silent failures | Five-minute monitoring of backup evidence, failed/stuck mail and scans, API readiness/contract, disk capacity, deduplicated failure/recovery alerts with delivery retries | Configure the actual alert endpoint and an independent external uptime check; an entirely failed host cannot alert from itself |
| Slow/unavailable service | Indexed client queries, panel-only refresh, paginated financial history, upload/body size/deadline/capacity limits, bounded API admission and database busy timeout | Load-test actual record sizes and concurrency; monitor growth and storage rather than treating synthetic timing as production latency |
| Broken deployment | Verified release manifest binds the exact binary, web assets and migrations; incompatible frontend saves fail; production refuses pending schemas; downgrade checks; stopped-writer and verified-restore preparation | Deploy a successful CI artifact and verify the actual service, proxy and frontend together |

## Test and release gates

Run `bash scripts/check.sh` in a host that supports loopback HTTP and Chromium.
It compiles both applications, runs backend and generated regressions, compiled Elm
state tests, Python recovery/operations tests, query performance checks, real HTTP
process tests, and browser/mobile/financial tests. Only its successful final step
seals `web/dist/release.json` for that exact API binary. Rebuilding the frontend
invalidates the seal. Changing assets, the binary or migrations after sealing makes
production startup fail. This is deployment evidence for trusted operators, not a
cryptographic signature against someone who can edit the application itself.

CI packages a sealed `ecc-crm-release.tar.gz` only after the entire gate succeeds.
The package uses explicit file paths and excludes databases, private environment
files, credentials and caches. Deploy that same artifact; rebuilding its binary
requires running the quality gate again. `ECC.Release.releaseContract` and
`web/src/Release.elm` must be changed together for incompatible protocol changes.
Existing versions which do not send a contract header cannot be checked by that
header; the production startup/artifact checks protect the installed release.

New two-connection regression tests race identical receipt, reversal and expense
payment requests and verify one success, one conflict and one ledger effect. They
also reject a receipt belonging to another invoice and a repeated lost-response
retry. Permission regressions exercise lists, reminders, dashboard and direct writes.
Draft tests check account isolation, password removal, repeated expiry, unchanged
revisions and network failures. Release tests reject changed/missing assets,
unverified builds, changed binaries/migrations and newer database schemas.

## Production change procedure

1. Obtain the artifact from a successful, reviewed CI run. Extract it into a new
   release directory, leaving the running release intact. Verify that its binary
   can run on this host. Configure the API service to use that release directory,
   binary, `WEB_DIST`, persistent `DATABASE_PATH` and production environment.
2. Plan a maintenance window and stop the API and every database writer (including
   mail/scanning workers and any manual imports). Keep their previous configuration
   available. Run preparation as the service account with private API/recovery
   environment variables loaded. From the new release directory:

   ```sh
   python3 scripts/prepare_release.py --binary ./ecc-crm-api \
     --service ecc-api.service --service ecc-mail.service --service ecc-scan.service
   ```

   Replace `ecc-api.service` with the actual API unit name. `DATABASE_PATH` and
   `BACKUP_DIR` must be set, along with production API, restic and alert settings.
   Preparation verifies the release, requires synchronized host time and stopped,
   installed writer services, validates the database, creates a fresh backup and
   verifies an actual off-site restore, then applies migrations transactionally.
   If any preceding step fails, it does not run migrations. It does not start services.
3. Start the API and workers. Verify `/api/ready` reports `ready` with the expected
   contract, `/api/time` has the intended business timezone, and the served frontend
   belongs to the same release. Test a restricted account, client loading, an expense
   approval and a reversible test payment in an isolated test account/database.
   Confirm timers, a delivered test alert and a verified remote restore.
4. If validation fails, stop writes and investigate. Never start an older binary
   against a newer schema. Recovery means restoring the pre-change snapshot to a
   new database path with its compatible prior application, checking it, and then
   switching the stopped services. Do not overwrite a database while writers run.

## Recovery and monitoring limits

Backups are scheduled hourly. Any data after the last successful recoverable copy
remains exposed to loss of the host/storage. A smaller recovery-point target needs
more frequent verified copies or separately designed replication. Restore duration
must be measured with the actual database and attachments; no recovery-time promise
has been established here.

`HEALTH_URL` is a credential-free HTTPS `/api/ready` endpoint. Production monitoring
flags a missing endpoint, unavailable API or contract mismatch. Database and backup
volumes alert below 256 MiB free or 5% free, whichever is larger. Mail/scans stuck
for over 30 minutes and backup failures are also reported. An external monitor must
check service availability from another host/network, and alert delivery needs a
real test. Storage thresholds and backup retention need adjustment to measured data
growth, especially when documents are stored in SQLite.

## Evidence from this workspace

Backend regressions, two-connection financial races, release/schema checks, compiled
Elm state tests and Python local restore/monitoring tests run without sockets.
Off-site adapter tests use a fake restic runner; they do not prove cloud access.
This environment cannot run the live HTTP/browser suites or access the production
service manager. Consequently its production release manifest remains unverified:
no local bypass or false successful quality-gate stamp is supplied.
