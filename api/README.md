# Run ECC CRM locally

Run these commands from this directory. Use GHC 9.6.6 and Cabal 3.10.3.0
to match `cabal.project.freeze`, and Elm 0.19.1 to build the frontend.

On Debian/Ubuntu, install the native build dependencies first:

```sh
sudo apt-get update
sudo apt-get install -y build-essential pkg-config zlib1g-dev libgmp-dev libpq-dev libsqlite3-dev
```

`libpq-dev` is required even when using SQLite locally because the executable
also includes the PostgreSQL backend. The frozen zlib dependency uses
pkg-config, so installing only the zlib runtime library is insufficient.

Build and start the application:

```sh
cabal update
cabal build
bash web/build.sh
cabal run ecc-crm-api
```

Open http://localhost:4000. Development uses a local `ecc-crm.sqlite3` database
and applies migrations automatically. The frontend is built into `web/dist`;
`WEB_DIST` can select another compiled frontend directory.

## Choose SQLite or PostgreSQL

The same API executable supports both databases without rebuilding. Configure
one before starting the API or running its administrative commands.

For SQLite, unset `DATABASE_URL` and set a file path (its parent directory must
exist and be writable):

```sh
unset DATABASE_URL
export DATABASE_PATH=/absolute/path/to/ecc-crm.sqlite3
cabal run ecc-crm-api -- migrate
cabal run ecc-crm-api
```

For PostgreSQL, create a database and user on your PostgreSQL server, then set
the connection URL using your deployment's secret configuration:

```sh
export DATABASE_URL='postgresql://USER:PASSWORD@HOST:5432/DATABASE?sslmode=require'
cabal run ecc-crm-api -- migrate
cabal run ecc-crm-api
```

Percent-encode special characters in URL credentials. `postgres://` is also
accepted. A local development PostgreSQL server without TLS can use
`sslmode=disable`; production requires `require`, `verify-ca`, or `verify-full`.
If omitted, `sslmode` defaults to `require`.

`DATABASE_URL` takes precedence over `DATABASE_PATH`. An invalid URL fails
startup rather than falling back to SQLite. With neither variable set,
development uses `ecc-crm.sqlite3` in the current directory. Production requires
an explicit persistent database and the other settings in `AGENTS.md`.

Migrations are selected automatically for the configured backend. Switching
configuration connects to the selected database; it does not copy records
between SQLite and PostgreSQL. Back up and migrate existing data separately.

To create your first account, set `ECC_USER_EMAIL`, `ECC_USER_NAME`,
`ECC_USER_ROLE` (`admin`, `consultant`, or `viewer`) and `ECC_USER_PASSWORD`
(12 characters to 72 UTF-8 bytes) in your shell, then run:

```sh
cabal run ecc-crm-api -- create-user-env
```

Keep passwords out of shell history. Demo seeding is disabled by default.
See `TESTING.md` for the full quality gate. The backend regression command is:

```sh
cabal test regression --test-show-details=direct
```

Production additionally requires the configuration in `AGENTS.md` and a verified
release; use the deployment workflow rather than development defaults.
