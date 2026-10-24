# Clojure implementation and validation

The default build, server launcher, container, Compose files, and quality workflow now use Clojure/XTDB and ClojureScript/Reitit/re-frame. Historical Haskell/Elm files remain available for comparison and rollback. No live deployment or source database cutover is performed by changing these files.

## Implemented areas

| Area | Implementation |
|---|---|
| XTDB storage | One document per entity, lazy record resolution at a fixed snapshot time, SQL pagination and indexed relation lookup, atomic revision assertions, incremental writes, automatic import of the first port's aggregate document |
| Provider integration | OAuth/token handling, Zoom meeting creation/update/cancellation with uncertain-create reconciliation, deterministic Google Calendar IDs/ETags and change synchronization, Stripe checkout/idempotency/payment reconciliation, signed/replay-safe Stripe webhooks, DocuSign transaction identity/polling and quarantined signed PDFs, persistent job leases/retries/review states |
| Finance | Integer-cent calculations, balances, payment reversals, expense approvals and immutable posting entries, attachments/history, period controls, bank CSV import/deduplication/matching/unmatching/ignoring, currency-separated reports/exports, backend and UI permission controls |
| CRM | Student profiles and normalized photos, template application with deduplication, milestones/contact history, saved-view storage/application, record-scoped sections, conflict comparisons, conversion/history preservation |
| Accounts | Invitations, password recovery/reset, persistent login throttling, TOTP enrollment/replay checks, one-use recovery codes, administrative resets/session revocation/suspension, access scope and privilege editing |
| Communication/portal | Notification preferences, assignment/deadline/escalation notifications and queued email, leased SMTP delivery, one-use client links, uploads and explicit grants for latest approved/unexpired clean checklist versions, receipts/invoices/commercial downloads, checked checkout links and clean signed agreements |
| Operations | Streaming ZIP snapshots and bounded/resumable restore, checksums and record counts, production release-file verification, structured request logs, readiness, disk/mail/backup monitoring, local retention and encrypted restic replication |
| Migration | Read-only SQLite and repeatable-read PostgreSQL export, sequence/identity preservation, canonical workflow records plus original source rows, document bytes, permissions, legacy SHA-256 TOTP and recovery-code compatibility |

Provider HTTP calls are bounded, use HTTPS with restricted hosts and no redirects, and run outside database transactions. Uncertain create outcomes retain their operation identity. A local fixture test is not proof that a particular provider account is configured correctly. See [provider configuration](../deploy/clojure/PROVIDERS.md).

## Storage and capacity

A snapshot resolves individual entities as needed. Lead/client/task list pagination executes in XTDB rather than loading the complete workspace. Related-record queries use indexed parent columns. A workspace revision assertion keeps multi-record business writes atomic; writes remain serialized within one workspace. Reporting that enumerates a whole table still has a cost proportional to that table's size.

The measured 10,000-record drill verified pagination, a single-record update, snapshot consistency across a later write, streaming backup, and bounded-batch restore. Results from this machine are recorded in [clojure-capacity.json](validation/clojure-capacity.json). They are benchmark observations, not latency or capacity guarantees for different data, concurrency, hardware, or document volumes.

The repository database drill preserved all 57 source tables and 36 rows through export, import, backup and restore; [the recorded result](validation/clojure-migration-drill.json) contains counts and a snapshot checksum, not record contents. The source workspace database can be checked without modifying it:

```sh
python3 scripts/clojure/export_sqlite.py /path/to/source.sqlite3 /secure/source.json
(cd backend && clojure -M:drill /secure/source.json)
```

The drill imports into separate temporary XTDB directories, compares every retained source row, writes a streaming backup, restores into another directory, and compares the materialized state. Customer datasets not supplied here still require their own staging drill.

## Validation commands

```sh
./build.sh
(cd backend && clojure -M:integration)
(cd backend && clojure -M:capacity)
PG_BIN="$(pg_config --bindir)" bash scripts/clojure/postgres-migration-test.sh
python3 scripts/clojure/export_sqlite_test.py
CHROME_PATH=/path/to/chrome node --test scripts/clojure/browser.test.cjs
(cd backend && CHROME_PATH=/path/to/chrome clojure -M:acceptance)
```

The unit suite checks authorization, stale writes, conversion, money, recurrence, security, portal isolation, file quarantine, reconciliation, templates/profiles/views, invitations, recovery-code consumption, reminder deduplication, webhook verification, safe provider retries, route precedence, and backup/restore. Integration tests use real XTDB and local SMTP/ClamAV protocol fixtures. The live browser journey exercises actual cookie-authenticated CRM/finance/portal routes against isolated XTDB storage.

## External validation boundary

- Live Zoom/Google/Stripe/DocuSign accounts and production SMTP delivery are not verified without configured credentials and provider test accounts.
- Local ClamAV protocol fixtures verify transport and quarantine behavior; deployed signatures/scanning must also be checked against the actual ClamAV service.
- Encrypted off-host replication requires a configured, initialized restic repository and recovery credentials. No remote repository is provisioned or written during local fixture tests.
- The local Docker socket denied access at the OS level, including outside the sandbox. Container build/runtime validation must be completed on an accessible Docker host or by CI. Compose configuration can still be checked independently.
- Existing compiled Elm clients use a different wire contract. The replacement frontend uses the Clojure API shapes; external API consumers need contract review before cutover.

These boundaries remain explicit in the runbook. They are not reported as completed production validation.
