# API logging and diagnosis

The API writes JSON lines containing UTC timestamp, severity, event, service,
release contract (`version`), method, safe route template, request ID, response
status and duration in milliseconds. Durations use a monotonic clock.
`request_exception` records contain the exception type and an IO category when
available. `database_error` records contain a database code and operation.
Raw exception messages, SQL, request/response bodies, cookies, credentials,
query strings, student details and record IDs are excluded. Unknown route parts
become `:value`; static assets become `/:asset`. Add only fixed public route
names to the allowlist when introducing routes.

Every request receives a fresh server-generated 256-bit `X-Request-ID`; incoming
values are replaced. The same ID links completion and database/exception logs.
HTTP 500 exception responses contain the reference, and the Elm client displays
references from response headers for server failures. A reference is diagnostic
metadata, not permission to access a record. Existing audit history remains in
the database; these operational logs do not replace it.

## Runtime collection

Use `python3 scripts/log_runtime.py -- /path/to/ecc-crm-api` for the serving
process. Run administrative CLI commands directly. The Render Dockerfile now
uses this wrapper; a systemd example is in `deploy/ecc-api.service`.

Set `API_LOG_DIR` (default `/var/log/ecc`) to a dedicated persistent directory.
The wrapper appends to `api.jsonl`, rotates at 10 MiB, retains at most ten archived
files, and deletes archives older than 14 days during active writes. The size
limit can shorten history under heavy traffic. The directory is mode 0700 and
files are 0600; retain these restrictions for backups and any external log drain.
JSON also goes to stdout for the platform collector. Raw unstructured process
output is replaced by a generic event because boot/runtime errors can contain
secrets. The wrapper records nonzero process exits and retains their exit status.
Disk write failures produce `log_storage_failed` on stdout and an alert condition.

On Render, attach a persistent disk at `/var/log/ecc`, writable by UID 10001.
Without a disk, container-local logs will not survive replacement or redeployment.
Configure the platform's log retention/access separately if using its log drain.
The wrapper requires a writable log directory and fails startup if it cannot open
it. Keep disk usage monitoring enabled. On systemd, install the reviewed binary
at `/opt/ecc/bin/ecc-crm-api`, configure `/etc/ecc/api.env` privately, install the
example unit, then enable it through the normal deployment procedure. The unit
creates `/var/log/ecc` and restarts a failed process.

## Runtime alerts

Configure `ALERT_WEBHOOK_URL` as an HTTPS receiver for JSON events, optionally
with `ALERT_TOKEN_FILE` pointing to a private 0400/0600 bearer-token file. Redirects
are rejected. These are the same settings used by the existing operations monitor.
No customer details, URLs, credentials or exception strings enter alert payloads.
Without a webhook the wrapper emits `runtime_alerts_unconfigured`; it does not
claim that notifications are active.

Every 30 seconds the wrapper checks local `/api/ready` with a five-second timeout.
It alerts after three consecutive readiness failures, ten HTTP 5xx responses or
three database request failures in the recent five minute buckets, or a log
storage failure. Ordinary validation/permission/conflict responses do not count.
Changed conditions alert immediately; unchanged failures remind hourly. Recovery
also produces an event. Failed deliveries retry at the next check. Counters reset
on process restart. A nonzero process exit triggers a separate alert attempt.
An independent external uptime monitor remains necessary: a dead host, stopped
wrapper or broken network cannot reliably alert about itself.

Backup monitoring also compares the latest snapshot name and checksum with the
restore-drill and off-site evidence. Fresh evidence for an older snapshot is
reported as `snapshot-mismatch`, rather than marking a newer backup healthy.
PostgreSQL drills must explicitly report `logicalRecoveryVerified=true`.

## Diagnose an incident

1. Copy the reference from the error message or browser response `X-Request-ID`.
2. Search current/archived `api.jsonl*` files or the platform collector for that ID.
3. Inspect `request_exception` or `database_error`, its route, category/code,
   duration and release version. Use audit history for authorized record changes.
4. Check readiness, database connectivity, capacity and recent deployment changes.
   Do not enable request-body or raw SQL logging to investigate private records.

Before production, verify the persistent mount survives a restart/redeployment,
confirm logs remain private, and send a synthetic test to the configured receiver
using the existing operations `alert-test` command. In staging, exercise repeated
5xx/database failures, readiness outages and recovery and confirm notifications.
No real alerts are sent by the automated tests. This repository change does not
configure or deploy a hosted disk, webhook, log drain or uptime monitor.
