# Reliability and usability review — 23 October 2026

The changes use the existing database adapters, backup tools, and runtime
monitoring. No schema migration is needed for these improvements.

| Area | Change and validation |
| --- | --- |
| Database compatibility | The shared client/application suite now enters and searches leads through HTTP before testing conversion, tasks, documents, application edits, conflicts, and permissions. Both SQLite and PostgreSQL runners passed. |
| Deployment | Preflight checks now validate port and connection-pool limits. CI builds the actual Render image and smoke-tests production startup, assets, authentication boundaries, migration replay, and restart persistence. Separate SQLite disk/migration instructions are provided. |
| Recovery | SQLite's real migration/restore test now checks exact uploaded document bytes and application school/program details. Real PostgreSQL restore drills check records, document/photo/receipt bytes, balances, sequences, audit triggers, corruption rejection, and source preservation. |
| Usability | Reviewed lead entry, conversion, application filtering, search, and mobile layouts. Add Lead supports normal form/keyboard submission. Fixed the theme control's text contrast. Mobile checks cover widths 320, 390, and 720, local form validation, dialogs, touch targets, and navigation. |
| Errors | Connection and timeout messages explain that drafts remain and advise checking the record before retrying saves. Gateway responses without JSON use a readable fallback with a validated request reference. State checks verify drafts survive failures without automatic retries and preserve conflict handling. |
| Monitoring | Existing request/database/readiness alerts remain active when configured. Backup monitoring now requires restore and off-site evidence to match the latest snapshot and checksum; an older successful drill cannot hide an unverified newer backup. |

Validation uses disposable databases and fixture accounts. The local PostgreSQL
server is version 18; the CI and Docker build configurations use version 17.
The ordinary regression suite includes 1,000 deterministic generated cases.
The Python suite passed 1,081 tests, and frontend state/report/offline/dialog
checks passed 57 tests. Real PostgreSQL recovery passed ten acceptance tests.
The final browser/mobile run passed 22 tests, live HTTP/startup checks passed
ten tests, and account CLI checks passed two tests. The release was sealed
after these checks succeeded. The final gate was resumed from recovery after
its initial process was interrupted; earlier stages had passed on the same
compiled assets and binary.

## Remaining hosted validation

Docker is not installed in this workspace, so the new `render-image` CI job has
not been executed here. Run it from the new repository before deploying.
Local tests do not prove a Render disk survives redeployment, a configured
webhook reaches its recipient, or an external backup repository is accessible.
Off-site orchestration tests simulate the remote repository; PostgreSQL database
snapshot/restore tests use the real local server and pg_dump/pg_restore.

Use a separate staging service and database, verify the actual disk permissions
and restart/redeploy persistence, configure the scanner and alert receiver, and
perform a restore from the real off-site repository. Follow
[Render deployment notes](RENDER_POSTGRESQL.md),
[logging and alerts](LOGGING.md), and
[PostgreSQL backups](POSTGRESQL_BACKUPS.md).
