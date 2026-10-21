# Repository Guidelines

## Project Structure & Module Organization

`app/Main.hs` starts the ECC CRM API and handles administrative CLI commands. Application modules live under `src/ECC/`: `Routes.hs` defines endpoints, `Models.hs` defines data types, `DB.hs` and `Store.hs` handle persistence, and feature modules implement workflows, portals, authentication, and security. Numbered SQL migrations live in `migrations/`. Regression checks are in `test/Main.hs` and `test/FeatureTests.hs`. `dist-newstyle/` contains generated Cabal output; do not edit it. Frontend assets are built separately and served from `../web/dist` by default.

## Build, Test, and Development Commands

Run commands from this directory so relative migration paths resolve correctly:

- `cabal build` — compile the API using `ecc-crm-api.cabal`.
- `cabal test regression --test-show-details=direct` — run the regression suite with visible output.
- `cabal run ecc-crm-api -- migrate` — apply pending SQLite migrations without starting the server.
- `cabal run ecc-crm-api` — start the server on port 4000 by default. Set `WEB_DIST` to a directory containing the compiled frontend's `index.html`.

## Coding Style & Naming Conventions

Use GHC2021 and explicit module-level language pragmas where needed. Match surrounding space-based indentation; ordinary `do` blocks commonly use two spaces. Use `PascalCase` for modules and types, and `camelCase` for functions and fields. Keep modules under the `ECC` namespace and add new modules to the relevant Cabal `other-modules` lists. Provide type signatures for new top-level functions. Build with the existing `-Wall` settings and address new warnings; no formatter or linter is configured here.

## Testing Guidelines

Tests use custom assertions, `Network.Wai.Test`, and temporary SQLite databases. Add descriptive assertion labels and exercise HTTP status codes, response data, authorization, and persistence when behavior changes. Extend the existing regression suite and clean up temporary resources. No numeric coverage threshold is configured.

## Commit & Pull Request Guidelines

Git history is unavailable in this checkout, so no existing commit convention can be verified. Use concise, imperative subjects such as `Fix portal document authorization`. PRs should explain the behavior change, list validation commands and results, link relevant issues, and identify migration or configuration changes.

## Security & Configuration

Never commit credentials or runtime databases. Production requires `APP_ENV=production`, a persistent `DATABASE_PATH`, a nondefault `JWT_SECRET` of at least 32 bytes, an HTTPS `PUBLIC_URL`, and demo seeding disabled. Add schema changes as numbered migrations following existing filenames.
