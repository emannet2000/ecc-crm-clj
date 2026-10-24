# ECC client workspace

The default application is **Clojure + XTDB + ClojureScript + Reitit + re-frame**. It includes leads and clients, applications and checklists, tasks and appointments, profiles/photos, communication, client portals, commercial documents, finance and reconciliation, account security, provider workers, reports, and backup/monitoring tooling.

See [migration implementation and validation](docs/CLOJURE_MIGRATION.md), [production deployment](deploy/PRODUCTION.md), and the [workflow guide](deploy/clojure/WORKFLOWS.md). Provider credentials, actual delivery, and public deployment require environment-specific validation; source implementation and local fixture tests do not certify those external systems.

## Run locally

Requires Clojure CLI, a compatible JDK, Node/npm, and Chromium for browser tests. The container uses JDK 21. JVM options required by XTDB/Arrow are supplied in the runtime/test aliases.

```sh
./build.sh
export XTDB_DIR="$PWD/backend/data/xtdb"
export BLOB_DIR="$PWD/backend/data/blobs"
export PUBLIC_URL=http://localhost:4000
read -rs ECC_ADMIN_PASSWORD
export ECC_ADMIN_PASSWORD
./run.sh adduser admin@example.com 'Workspace Admin' admin
unset ECC_ADMIN_PASSWORD
./run.sh
```

Open `http://localhost:4000`. `PORT`, `BIND_HOST`, `WEB_DIST`, `XTDB_DIR`, and `BLOB_DIR` configure the server. Create the administrator before starting the server: embedded XTDB has one owning process per data directory. Subsequent users and invitations are managed through Team.

## Verify

```sh
./build.sh
(cd backend && clojure -M:integration)
(cd backend && clojure -M:capacity)
python3 scripts/clojure/export_sqlite_test.py
PG_BIN="$(pg_config --bindir)" bash scripts/clojure/postgres-migration-test.sh
CHROME_PATH=/path/to/chrome node --test scripts/clojure/browser.test.cjs
(cd backend && CHROME_PATH=/path/to/chrome clojure -M:acceptance)
```

The tests separate pure domain/HTTP behavior, real XTDB durability, SMTP/ClamAV protocol fixtures, a 10,000-record backup/restore drill, PostgreSQL migration, compiled frontend behavior, and a live browser journey against the actual Clojure/XTDB server. The live journey uses isolated test records and does not send real provider requests or email.

## Deploy

Copy `.env.example` to a private `.env`, configure HTTPS/DNS and a separate random `BACKUP_TOKEN`, then follow [the production runbook](deploy/PRODUCTION.md). `Dockerfile`, `compose.yaml`, `compose.release.yaml`, `compose.integrations.yaml`, and `compose.offhost.yaml` now target the Clojure runtime. No SQL or Haskell worker is required by the default deployment.

`python3 scripts/build_release.py` builds application/scanner images and writes immutable local image identities to `release-images.json` and `compose.verified.yaml`. The quality gate includes vulnerability scanning. Production startup verifies backend source and frontend asset hashes against `release-clojure.json`.

## Migrate existing data

Export the source read-only and import into a fresh XTDB directory. Stop source writes for the final cutover. Keep the source database and its backups until acceptance and rollback planning are complete.

```sh
python3 scripts/clojure/export_sqlite.py /path/to/source.sqlite3 /secure/source.json
./run.sh import-sqlite /secure/source.json
# PostgreSQL: set SOURCE_JDBC_URL privately, then export/import separately.
./run.sh export-postgres /secure/source-pg.json
./run.sh import-postgres /secure/source-pg.json
```

Exports and backups contain sensitive data. The source export refuses overwrite and has private file permissions. Identifiers, sequence high-water marks, passwords, access rules, original tables, and file bytes are preserved. Imported files are quarantined for a new scan; old staff and portal sessions require fresh links/logins.

The former Haskell/Elm source is retained for comparison and rollback, alongside `Dockerfile.legacy`, `compose.legacy.yaml`, `scripts/build-legacy.sh`, and historical documentation under `deploy/legacy/`. It is no longer the default build or deployment.
