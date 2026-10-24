# Local validation

Validated on 2026-10-24:

- Production ClojureScript build and backend unit suite: 27 tests, 140 assertions, zero failures/errors.
- XTDB integration suite: 4 tests, 16 assertions, zero failures/errors; includes local SMTP and ClamAV protocol fixtures.
- Compiled frontend browser regression: passed, including stale-response handling and mobile layout.
- Live isolated XTDB browser journey: passed conversion, profiles, checklist application, quarantine enforcement, proposal/contract issue and portal acceptance, invoices, payment deduplication, bank reconciliation, downloads, public portal isolation, portal closure and staff logout.
- Release manifest verification: passed for 27 release files.
- Read-only SQLite exporter regression and isolated PostgreSQL export/import/restore fixture: passed.
- 10,000-record capacity and backup/restore round trip: see [measured results](clojure-capacity.json).
- Repository SQLite migration and backup/restore round trip: see [source counts and checksum](clojure-migration-drill.json). This source has 36 rows; it is not a full customer production dataset.

Live provider accounts, production SMTP, actual ClamAV signatures, encrypted remote backup recovery, and deployment on the target host remain external verification steps. Docker build/runtime checks were blocked by local Docker socket permissions. See [the migration validation boundary](../CLOJURE_MIGRATION.md#external-validation-boundary) and [the production runbook](../../deploy/PRODUCTION.md).
