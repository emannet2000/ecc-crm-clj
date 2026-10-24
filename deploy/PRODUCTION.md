# Clojure production deployment and recovery

The default deployment uses one Clojure/XTDB API process, in-process workers, ClamAV, Caddy, and a separate backup container. Provider credentials, actual SMTP delivery, TLS/DNS, scanner signatures, and off-host recovery must be exercised in staging before importing customer data. Changing deployment files does not migrate or restart an existing installation.

## Build and verify

Run the quality commands in [README](../README.md), including the live browser journey, PostgreSQL migration fixture, and 10,000-record restore drill. On an accessible Docker host:

```sh
python3 scripts/build_release.py
# Use the quality gate's high/critical image scan before deployment.
docker compose --env-file .env -f compose.yaml -f compose.verified.yaml config --quiet
```

The release builder resolves the Clojure builder image to a repository digest and records the resulting local image IDs. Use `compose.verified.yaml` with `--no-build` to deploy those IDs. Registry deployment requires pushing the tested images and using their immutable registry digests on the destination host. Do not rebuild after acceptance and assume image identity is unchanged.

Production startup verifies the exact source/frontend file set and SHA-256 values against `release-clojure.json`. Modified/missing files fail startup. This protects release consistency; it is not an external tamper-proof attestation.

The application uses a read-only container filesystem, private API networking, persistent `/data`, and temporary Clojure configuration/cache directories. The backup token is separate from browser authentication. Caddy blocks `/internal/*`; keep the API port private.

## Configuration and initial administrator

Set HTTPS `PUBLIC_URL`, `SITE_HOST`, a random URL-safe `BACKUP_TOKEN` of at least 32 characters, SMTP transport settings, monitoring recipient, and the intended `ASSIGNED_ONLY` policy. Preserve `.env` outside version control. Set `REQUIRE_ADMIN_MFA=true` to require enrollment before administrators open workspace records.

Embedded XTDB has one owning process for a data directory. Create/import/restore offline; do not run a second CLI node against the running server's directory.

```sh
# Bootstrap before starting the API, or stop it first.
docker compose -f compose.yaml -f compose.verified.yaml stop api
read -rs ECC_ADMIN_PASSWORD
export ECC_ADMIN_PASSWORD
docker compose -f compose.yaml -f compose.verified.yaml run --rm --no-deps -e ECC_ADMIN_PASSWORD api adduser admin@example.com 'Workspace Admin' admin
unset ECC_ADMIN_PASSWORD
docker compose -f compose.yaml -f compose.verified.yaml up --no-build -d
```

Enroll the administrator, save one-use recovery codes, and create staff through Team. Confirm invitations and password recovery in the intended inbox, test expiry/single use, and verify revocation after password/role/access changes. Test admin, consultant, viewer, finance privileges, and assigned-record restrictions with separate accounts.

## Migration and cutover

Export the source read-only using the SQLite or PostgreSQL commands in README. Stop source writes for the final export. Import into a fresh XTDB directory with a separate blob directory, then verify source-row counts, identifiers, reference/sequence floors, access rules, files, ledger balances, periods, templates, profiles, and provider records. Imported files require a new scan. Imported staff sessions and old portal links require fresh authentication/reissue.

Run `clojure -M:drill` on the source export for a complete local import/backup/restore comparison. Take and retain a source database backup before cutover. Preserve the old deployment/data until acceptance and rollback planning are complete. The legacy source remains available; no volume is automatically deleted.

## Scanning, workers, and providers

Allow ClamAV to download signatures before evaluating scan results. Test clean, infected, unavailable-scanner, and retry behavior with the deployed scanner. Files stay quarantined until a clean result; exhausted scans need an administrator retry. Photos are normalized before entering the same quarantine pipeline.

SMTP uses required STARTTLS or TLS for remote hosts and checks server identity. Mail has expiring leases, bounded attempts, and at-least-once transport semantics. A server crash after SMTP acceptance can cause a duplicate delivery; successful stored message bodies are removed. Test actual delivery, not only SMTP acceptance.

Providers run inside the Clojure worker; see [PROVIDERS](clojure/PROVIDERS.md). Do not run the former SQL/Python integration worker against the new data directory.

## Backups and off-host replication

The API creates a consistent streaming ZIP snapshot through a private token-protected `/internal/backup` endpoint. Every record and immutable document is a separate archive entry. Record counts and document checksums are validated on restore. The backup container downloads a snapshot hourly by default and keeps the latest 24 local copies. Configure interval/retention for the required recovery point.

For encrypted off-host replication, configure a dedicated restic repository and a private password file readable by UID 10001. Keep independent recovery copies of the repository location, password, and credentials. Initialize the repository once, then enable the overlay:

```sh
docker compose -f compose.yaml -f compose.verified.yaml -f compose.offhost.yaml run --rm --no-deps --entrypoint restic backup init
docker compose -f compose.yaml -f compose.verified.yaml -f compose.offhost.yaml up --no-build -d
```

The worker records off-host success only after backup, retention, and repository checking succeed. Retention keeps seven daily, four weekly, and twelve monthly points, grouped by stable host/tag. Use a dedicated repository or distinct backup host ID for separate workspaces. Remote outages do not stop bounded local retention, so alert response must precede loss of the required local recovery window.

To restore, retrieve a ZIP snapshot using restic/local storage, stop the target API, and restore into a fresh XTDB/blob directory:

```sh
XTDB_DIR=/recovery/xtdb BLOB_DIR=/recovery/blobs ./run.sh restore /secure/ecc-snapshot.zip
```

Restore commits bounded batches and marks an interrupted restore. Startup refuses incomplete restores; rerunning the same archive can resume. A different archive cannot overwrite that target. Test logins, permissions, counts, file downloads, conversion, financial balances and provider identities before switching traffic. Record actual recovery time and recovered snapshot time.

## Monitoring

`/api/health` reports liveness; `/api/ready` checks storage. Structured request logs contain method, path, status and latency, without bodies, credentials or query strings. Admin metrics include operational state. The worker monitors disk space, delayed/failed mail, and local/off-host backup freshness; state changes and persistent alerts use the configured SMTP recipient.

Use an independently hosted uptime/alert transport to detect loss of the application host or SMTP itself. No external monitoring account is provisioned by this repository.
