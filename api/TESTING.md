Testing and CI
==============

Run the full quality gate from the API directory:

```sh
CHROME_PATH=/usr/bin/chromium bash scripts/check.sh
```

Requirements: GHC 9.6.6, Cabal, Elm 0.19.1, Node 22+, Python 3.11+ and Chrome/Chromium.
The runner builds optimized production assets plus one unoptimized Elm bundle for
state/report tests. `ELM_BIN`, `ELM_HOME`, `CABAL_CONFIG` and `CHROME_PATH` can override
local tool locations. It fails when a required check fails; it does not silently
skip networking or browser tests.

The existing regression suite now runs **1,000 deterministic generated property
cases**, each identified by a group and integer seed:

| Property | Cases |
| --- | ---: |
| Unicode, quotes, commas, CR/LF and empty CSV field round trips | 200 |
| Spreadsheet formula neutralization with whitespace | 100 |
| Byte equality, unequal lengths and tampering | 100 |
| Base32 round trips across binary lengths | 100 |
| Token hash encoding and corpus uniqueness | 100 |
| Signed-token verification, wrong secrets and tampering | 100 |
| PNG zero/maximum/oversized dimensions and truncation | 100 |
| Database pagination against an independent list model | 100 |
| Transaction and audit rollback after injected failures | 100 |

These are generated cases across nine property families, not 1,000 independent
features. The fixed corpus is reproducible; there is no randomized shrinking.
Failure messages identify the exact property and seed. Tests use isolated temporary
databases and do not access runtime CRM data.

Other checks include existing HTTP/WAI authorization and workflows, conversion
idempotence, optimistic concurrency, document quarantine, simultaneous reference
allocation, real Elm state updates, report injection/escaping, offline privacy,
responsive browser flows, query-plan checks and 20 backup/recovery tests.
`scripts/system_test.py` additionally launches the real API on a disposable local
port to test configuration guards, startup, migrations, restore, authorization,
compression and concurrent requests. Browser acceptance tests use fixture HTTP
responses; the WAI and system tests exercise the actual backend.

CI setup
--------

The parent repository already has `.github/workflows/quality.yml`, which runs
`cabal test all` in `api`. That automatically includes the new 1,000 cases. Keep its
image scanning and advisory checks.

The expanded workflow is staged in `api/.github/workflows/ci.yml`. GitHub only
recognizes workflow files in the repository-root `.github/workflows` directory.
Install the additional workflow from a writable checkout:

```sh
bash api/scripts/install-ci.sh /path/to/repository-root
```

For a standalone API repository, its `.github/workflows/ci.yml` is already at the
correct location. The expanded workflow runs all checks on pushes and pull requests,
uses dependency caches and uploads logs/screenshots. It does not deploy the app.
Action setup follows the upstream [Haskell setup](https://github.com/haskell-actions/setup)
and [Chrome setup](https://github.com/browser-actions/setup-chrome) documentation.

Local validation in this workspace: the API build, existing regression suite,
all 1,000 generated cases, frontend state/report/offline checks, query-plan checks,
production configuration guards and backup/restore checks pass. Local sockets and
Chromium's sandbox process startup are denied by this execution environment, so
live HTTP and browser execution require the CI runner. No hosted CI run has been
triggered from this checkout.
