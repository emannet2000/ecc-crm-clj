# ECC client workspace

Elm frontend, Haskell/Scotty API and **SQLite**. Includes leads, clients, cases, editable/reassignable recurring tasks, document checklists and versions, shared activity history, scheduled email reminders, safe duplicate merging, management reports, saved views, MFA/session administration, appointments, a client portal and invoices. See the [workflow guide](deploy/WORKFLOWS.md) and [daily operations guide](deploy/OPERATIONS.md) for inline client/case work, conflict comparisons, scan-gated uploads, email tracking, notifications and report exports.

## Run locally

Requires GHC 9.6.6, Cabal and Elm **0.19.1**. Python 3.11+ runs the mail worker, backups and database tests; no Python packages or database server are required. Node 22+ and Chromium run browser tests.

```sh
export DATABASE_PATH="$PWD/ecc-crm.sqlite3"
export PUBLIC_URL=http://localhost:4000
export JWT_SECRET="$(openssl rand -hex 32)"
./scripts/build.sh
cd api
cabal run ecc-crm-api -- adduser admin@example.com 'Workspace Admin' admin 'choose-a-long-unique-password'
cabal run ecc-crm-api
```

Open `http://localhost:4000`. The API serves the optimized frontend from `web/dist`. Use the same origin for the frontend and API; set `PORT` and `PUBLIC_URL` together if changing ports. `WEB_DIST` can override the static directory. SQLite defaults to `ecc-crm.sqlite3` in the API working directory when `DATABASE_PATH` is unset in development.

Demo data is opt-in (`SEED_DEMO=true`) and forbidden in production. Never enable demo mode against live records.

## Deploy

1. Copy `.env.example` to `.env`. Set separate random `JWT_SECRET` and `PROXY_TOKEN` values (32+ bytes each), your real DNS hostname and HTTPS public URL, and SMTP credentials. Keep this file private and outside version control.
2. Point DNS at the server, allow ports 80/443, build and test the release with `python3 scripts/build_release.py`, then run `docker compose -f compose.yaml -f compose.release.yaml up --no-build -d`. Caddy obtains the TLS certificate. The API and mail worker share a persistent SQLite volume; the database is not exposed as a network service.
3. Create the first administrator:
   `docker compose exec api ecc-crm-api adduser admin@example.com 'Workspace Admin' admin 'choose-a-long-unique-password'`.
4. In Team, add colleagues with the password left blank to email invitations. Verify delivery and the reset link on the public origin.
5. Run the quality gate, test representative permissions, and complete a backup/restore drill in staging before importing customer data.

Production requires `DATABASE_PATH`, a 32+ byte `JWT_SECRET`, HTTPS `PUBLIC_URL`, and demo data disabled. The database's parent directory must exist and be writable by the application user. The container runs as UID 10001; both API and worker use that UID to access the data volume. Protect the volume and backups as sensitive customer data.

SQLite connections enable **WAL**, `foreign_keys=ON`, a ten-second busy timeout and `synchronous=FULL`. `DB_POOL_SIZE` defaults to 2 (range 1–16). Read requests use deferred transactions and connection-local authorization context, allowing concurrent WAL reads without taking the main write lock. Mutations use `BEGIN IMMEDIATE`; uploads are buffered with bounded admission before acquiring a connection. Login uses atomic rate-limit upserts and runs bcrypt outside a write transaction; session creation checks that the password hash is still current. Writes are serialized by SQLite, including audit context and conversion; the email worker releases its write lock before talking to SMTP. Use local persistent storage on one host, not a shared network filesystem or independent replicas. All data, uploaded documents and sessions live in the SQLite file and its WAL.

Migrations run transactionally at startup. Back up before deployment and stop old application versions during incompatible schema changes. Existing email addresses must be unique ignoring case before migration 0004. If your existing SQLite schema differs from these migrations, test an upgraded copy before switching the live file. No migration from another database engine is performed.

## Accounts and access

Browser sessions use HttpOnly, SameSite=Strict cookies (Secure in production). Tokens are never stored in localStorage or placed in download URLs. CLI/API clients may use the login response token in an Authorization bearer header. Sessions expire after eight hours; logout revokes that session, and password/role changes revoke all account sessions. Administrators cannot delete themselves or remove the last administrator.

Admins manage accounts, audit history, archive and system status. Viewers cannot mutate CRM data. Colleagues share records by default. Set `ASSIGNED_ONLY=true` to restrict non-admin access to assigned records; verify this workspace policy with your team before rollout. This application does not provide multi-tenant isolation.

Invitations and recovery links are single-use, expire after one hour, and are stored as hashes. Email is delivered by `scripts/mail_worker.py`, a separate supervised process. Set `DATABASE_PATH`, `SMTP_HOST`, `SMTP_FROM`, and optional SMTP port/user/password/TLS settings. Remote SMTP requires STARTTLS or TLS. A failed message is attempted at most five times; System shows failures. Successful message bodies are removed. Expiring delivery leases allow worker restarts, with at-least-once SMTP delivery semantics.

Login and recovery persist limits of 20 requests per normalized account and 200 per source/category per fifteen minutes. Reset uses a limit of 20 per source. Account keys are hashed. The supplied proxy overwrites client-IP headers and authenticates them with `PROXY_TOKEN`; without the correct secret the API uses the socket address. Keep the API port private and use separate random proxy/session secrets. Arbitrary forwarded headers are not trusted.

## CRM behavior

Conversion creates the client/case, transfers documents, attaches tasks, and preserves the original lead/activity history in one transaction. Retrying conversion returns the existing client. Atomic reference counters prevent collisions and retain their high-water marks after archive or conversion.

Deleting a lead/client archives it with all children intact. Administrators restore records from Archive. Converted source leads remain as history. Individual unversioned document, task and case deletion requires confirmation and is permanent; versioned files are retained; use a database backup for recovery of those records.

Audit triggers record all lead, client, case, task, document and user writes, including direct SQL. Request context assigns the actor within the same serialized transaction; CLI/direct SQL has no named actor. Password hashes and file bytes are excluded. Database operators can still alter audit history; this is not an external tamper-proof audit service.

Lists use server pagination (default 50, maximum 200). Lead search, stage/quality/source filters and sorting run on the server. Duplicate review groups accessible leads/clients with matching normalized email/phone values; administrators can preview and confirm same-type merges while preserving related records and history. In-app reminders cover tasks and lead follow-ups due within seven days, with per-user read receipts. The scheduler adds configured task reminder and overdue escalation emails, and creates the next occurrence of completed recurring tasks.

Documents are SQLite BLOBs (25 MB per file; 27 MB total request limit), served as safe attachments. Include their storage in backup planning. Documents are quarantined until the ClamAV scanner succeeds; Compose supplies the scanner and signature updater. See [scanning setup](deploy/OPERATIONS.md#quarantine-and-malware-scanning). CSV imports accept up to 2 MB/5,000 rows and report invalid rows; exports guard spreadsheet formula prefixes.

## Backups and operations

```sh
DATABASE_PATH=/data/ecc-crm.sqlite3 ./scripts/backup.sh /secure/backups/ecc-$(date +%F).sqlite3
RESTORE_DATABASE_PATH=/recovery/ecc-crm.sqlite3 ./scripts/restore.sh /secure/backups/ecc-2026-10-18.sqlite3
```

In Docker, the same scripts are available under `/app/scripts`; run them with `docker compose exec api` and use paths in `/data`, then copy snapshots off the host.

The Compose `backup` service creates a verified snapshot at startup and hourly in the separate `sqlite_backups` volume, retaining the latest 24. Configure `BACKUP_INTERVAL_SECONDS` and `BACKUP_KEEP_LOCAL` for your recovery objectives. `compose.offhost.yaml` adds encrypted restic replication, remote retention and monitoring of remote backup freshness. Repository access and a recovery password are deployment configuration; local snapshots alone do not protect against host loss.

Backups use SQLite's online backup API, so committed WAL data is included consistently. Every copy passes integrity and foreign-key checks and receives private file permissions. Backup and restore refuse to overwrite an existing destination. **Do not copy just the live `.sqlite3` file while WAL mode is active.** Schedule the backup script, copy verified snapshots to encrypted off-host storage, and configure retention. Stop the recovery app before restoring; verify logins, counts, document downloads and conversion in the restored environment before switching traffic.

`/api/health` reports process liveness; `/api/ready` checks database connectivity. JSON request logs include method, path, status and latency without query strings or credentials. System and the admin-only `/api/metrics` endpoint report mail queue failures, active sessions and database size. Set `ALERT_TO` and start `docker compose -f compose.yaml -f compose.release.yaml --profile monitoring up --no-build -d` to enable the supplied monitor. It checks readiness, disk space, delayed/failed mail and stale backups every minute, emails state changes, and repeats active alerts hourly. It shares your SMTP transport, so use an independent uptime service to detect a host or SMTP outage. Connect structured request logs to your log service for 5xx/latency alerting. No external monitoring account, live DNS or SMTP account is provisioned by the repository.

## Verify

```sh
./scripts/build.sh
(cd api && cabal test all)
python3 -m unittest discover -s tests -v
node --test tests/state.test.cjs
CHROME_PATH=/usr/bin/chromium node --test tests/ui.test.cjs
# Optional real HTTP transport tests; starts an isolated SQLite-backed API.
ECC_RUN_HTTP_TESTS=1 python3 -m unittest discover -s tests -p test_api.py -v
```

Haskell regression tests exercise the actual WAI application and SQLite transactions without network sockets. Python database tests cover migrations, concurrent counters, audit redaction, session revocation, backup integrity and mail delivery leases. State regression tests execute the compiled Elm update function to verify stale-response protection and operational pagination. Browser tests run compiled Elm with fixture HTTP responses and save desktop/mobile screenshots in `/tmp`; they complement real API tests. CI runs the suites, checks the Cabal plan against the Haskell Security Advisory Database, builds the release images and scans them for high/critical vulnerabilities. Release manifests record immutable image identities.

Before production, pass the quality gate in your environment, verify real DNS/TLS/SMTP and monitoring, and complete a restore drill. Those external systems require your deployment configuration.

See [the production runbook](deploy/PRODUCTION.md) for immutable release builds, staging acceptance, off-host backup setup, load testing and the timed restore drill.
