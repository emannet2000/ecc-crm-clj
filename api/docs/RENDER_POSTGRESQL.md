# Render PostgreSQL deployment notes

The code supports PostgreSQL through `DATABASE_URL` and retains SQLite for existing local installs and regression tests. This document does not confirm deployment or transfer any existing data.

## Before switching an existing service

1. Rotate the database password and JWT secret that were shared in chat. Store replacement credentials in Render environment settings, never in source files.
2. Take a backup and test restoration. Stop all writers, including mail, scanning and workflow workers, before moving an existing database.
3. Run the complete release gate on a machine with PostgreSQL and browser access: set `ECC_TEST_DATABASE_URL` to a disposable test database and run `bash scripts/check.sh`. The script seals a release only after all checks pass. Do not manually change `verified` in `release.json`.
4. Deploy the matching tested executable, frontend assets (including the guides and emblem), and migration directories together. The current local build remains unverified until the complete gate runs.

## API environment

- `APP_ENV=production`
- `DATABASE_URL`: Render's internal PostgreSQL URL for services in the same region, with `sslmode=require`. The app adds this TLS setting if absent and rejects plaintext modes in production.
- `JWT_SECRET`: a fresh random secret of at least 32 bytes.
- `PUBLIC_URL`: the app's public HTTPS address.
- `SEED_DEMO=false`
- `WEB_DIST`: the deployed frontend distribution directory, if it differs from the default.
- `PORT`: supplied by Render.

The executable requires libpq and the existing SQLite runtime dependencies. Python workers require `pip install -r scripts/requirements.txt` and the same database environment. Setting `DATABASE_URL` takes precedence over `DATABASE_PATH`.

Run `ecc-crm-api migrate` as the migration step before starting the new API. Production startup requires the current schema. PostgreSQL uses `migrations/postgresql/`; SQLite uses the SQL files directly under `migrations/`.

For an existing SQLite database, first bring an offline copy to the current SQLite schema. Then initialize an empty PostgreSQL database using the migration command and use `python3 scripts/import_sqlite_to_postgres.py --help` for the importer arguments. The importer verifies source integrity, requires an empty destination apart from untouched starter templates, preserves identifiers and binary data, and checks copied rows before committing. It has not been run against the live database here. Verify the imported records, documents and balances before enabling writers. Do not run a bulk copy against a database already in use.

## Photos and documents

Uploads are stored in the database's `documents.content` column; PostgreSQL stores the bytes as BYTEA. `client_photos` links a student to their photo. They do not depend on a local uploads directory or an additional Render disk when PostgreSQL is configured. They consume database storage and are included in database backups.

Photos accept PNG/JPEG up to 2 MB and 4096 × 4096 pixels. Photos and documents remain quarantined until the scanning worker successfully scans them. Deploy and monitor the scanner and its required ClamAV service; do not bypass quarantine to make an upload visible.

Render's normal service filesystem is temporary. Do not change uploads to local-file storage without providing persistent storage and a backup plan. Object storage may be considered separately if document volume grows; it is not configured by this implementation.

Render documents managed PostgreSQL encryption at rest. The app requires TLS for production database connections. Field-level encryption has not been added; do not describe the database as end-to-end encrypted. Verify backup retention and recovery on the actual database plan. The recovery and operations scripts now support PostgreSQL archives, safe restores, restore drills, retention and encrypted off-site copies. Follow [PostgreSQL backup deployment](POSTGRESQL_BACKUPS.md); real connection-based acceptance and hosted restoration still need to pass before accepting live data.

## Acceptance before Flor starts

Verify sign-in and access restrictions; create and convert a lead; edit a student; save school/program details; apply a tailored checklist; upload and scan a photo and a document; complete a milestone; log a conversation; and post and reverse a test payment. Check Today, audit history and balances. Test restart persistence and backup restoration. Verify email delivery separately if using it. Manual WhatsApp/SMS links require no automatic provider integration and do not send messages themselves.

Provider references: https://render.com/docs/postgresql-creating-connecting and https://render.com/docs/disks

## Current service configuration

Update the existing ECC CRM web service after the checks below. Keep its current PostgreSQL database if it belongs to this CRM; do not recreate or wipe it. If its schema differs, stop and review the migration plan. A connection URL alone cannot prove compatibility.

Use Root Directory `api` if the repository contains an `api` folder (otherwise use the repository root). Set Dockerfile Path to `deploy/Dockerfile.render` relative to that build context, health check path `/api/ready`, and pre-deploy command `ecc-crm-api migrate`. The new Dockerfile includes libpq, all frontend assets, and the full release gate using a disposable build-time PostgreSQL database. It never contacts the hosted database during the build and does not seal a failed build. This Docker image has not been built in the restricted workspace; its first full build must pass before deployment. Do not use the older repository-level Dockerfile for this release.

| Process | Runtime configuration |
| --- | --- |
| API | `deploy/Dockerfile.render`; private settings from `deploy/render-api.env.example` |
| Scan worker | `deploy/Dockerfile.workers`; start `python3 scripts/scan_worker.py`; private settings from `deploy/render-workers.env.example` |
| Workflow scheduler | Same worker image; start `python3 scripts/workflow_worker.py`; same database/timezone |
| Optional mail worker | Same worker image; start `python3 scripts/mail_worker.py`; configure SMTP credentials privately |
| Backup worker | `deploy/Dockerfile.postgres-backup`; see the dedicated backup runbook and persistent disk requirements |

The scan worker needs an existing private ClamAV service reachable on `CLAMD_HOST`/`CLAMD_PORT` in the same Render region/network. Use its internal hostname rather than `127.0.0.1` when it runs as a separate service. Do not publish the scanner port to the internet. Merely starting the scan worker does not install or configure the ClamAV service. Verify a harmless photo/PDF remains quarantined before scanning and becomes accessible after a clean scan. Keep virus definitions current.

## Operator sequence before Flor's pilot

- [ ] Back up the existing database and demonstrate restoration to a separate target. Confirm ownership and current schema before migrations or data imports.
- [ ] Rotate the previously shared database password in Render. Update `DATABASE_URL` on the API and all dependent workers using the newly issued URL. Restart/redeploy them and verify connectivity. Rotation has not been performed from this workspace.
- [ ] Generate a fresh random JWT secret privately and set it on the API. Expect staff to sign in again. Remove old secret copies from any runtime configuration. No new secret is embedded in these example files.
- [ ] Set `APP_ENV=production`, `SEED_DEMO=false`, the actual HTTPS `PUBLIC_URL` and the other required environment variables. Disabling seeding does not delete existing demo rows; review those separately rather than deleting possible live records automatically.
- [ ] Deploy the tested image and run the migration step. Run `python3 scripts/render_preflight.py --mode api --live` from a worker image with the API environment loaded; the API runtime image contains the binary, frontend and logging wrapper. The checker is read-only and reports codes rather than credentials. Configuration checks alone do not establish production readiness.
- [ ] Follow [the logging runbook](LOGGING.md): mount persistent `/var/log/ecc` storage, configure the HTTPS alert receiver, verify restart persistence, and test readiness/error alerts in staging. Configure an independent external uptime monitor.
- [ ] Configure the scan worker and its private scanner. Run `python3 scripts/render_preflight.py --mode scan --live` in the scan worker's shell.
- [ ] Initialize/configure the encrypted backup repository and separate drill database. Start the backup worker, run a real restore drill and test an alert. Run `python3 scripts/render_preflight.py --mode backup --live` with that worker's environment to inspect current evidence.
- [ ] Create the operator and Flor accounts using Team or `ecc-crm-api create-user-env`, with `ECC_USER_EMAIL`, `ECC_USER_NAME`, `ECC_USER_ROLE` and `ECC_USER_PASSWORD` supplied privately. The command creates a new account only; it refuses to overwrite an existing account. Remove temporary account-creation variables afterward. Flor's actual email and role still need confirmation.
- [ ] Enable MFA and verify staff permissions. Complete [Flor's pilot checklist](FLOR_PILOT.md), including failure/retry, document, payment-correction and restart checks.

Use [the web security controls and acceptance guide](WEB_SECURITY.md) when reviewing the deployed service. No hosted passwords, account permissions, migrations, scanner settings or Render services have been changed by preparing these files.

Render references: [Docker configuration](https://render.com/docs/docker), [monorepo paths](https://render.com/docs/monorepo-support), [private services](https://render.com/docs/private-services), [environment settings](https://render.com/docs/configure-environment-variables).
