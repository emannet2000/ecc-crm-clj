#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${ELM_BIN:-}" ]]; then
  ELM_BIN=$(command -v elm)
  if [[ "$("$ELM_BIN" --version)" != '0.19.1' ]] && [[ -x /usr/bin/elm ]]; then
    ELM_BIN=/usr/bin/elm
  fi
  export ELM_BIN
fi
if [[ "$("$ELM_BIN" --version)" != '0.19.1' ]]; then
  echo 'Elm 0.19.1 is required' >&2
  exit 1
fi
# CABAL_CONFIG is useful on machines with a read-only global configuration/cache.
cabal_cmd=(cabal)
if [[ -n "${CABAL_CONFIG:-}" ]]; then cabal_cmd+=("--config-file=$CABAL_CONFIG"); fi
GHCRTS=-N2 bash scripts/build-themed-web.sh
# One unoptimized compile is shared by tests which inspect Elm runtime functions.
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
(cd web && GHCRTS=-N2 "${ELM_BIN:-elm}" make src/Main.elm --output="$test_dir/state.js")
export ECC_ELM_STATE_JS="$test_dir/state.js"
export ECC_ELM_REPORT_JS="$test_dir/state.js"
"${cabal_cmd[@]}" build all
"${cabal_cmd[@]}" test regression --test-show-details=direct
node --test --test-concurrency=1 test/frontend-state.test.cjs test/dialog-observer.test.cjs scripts/report.test.cjs scripts/report-output.test.cjs scripts/pwa.test.cjs
python3 -m unittest discover -s scripts -p 'test_*.py' -v
python3 scripts/performance.py
# PostgreSQL coverage is required before a release may be sealed.
: "${ECC_TEST_DATABASE_URL:?Set ECC_TEST_DATABASE_URL to a disposable PostgreSQL database}"
"${cabal_cmd[@]}" test postgres-regression --test-show-details=direct
ECC_INTEGRATION_TEST_DATABASE_URL="$ECC_TEST_DATABASE_URL" python3 -m unittest discover -s scripts -p test_integrations.py -v
python3 scripts/postgres_acceptance.py
python3 scripts/postgres_workers.py
python3 scripts/postgres_recovery_integration.py
export ECC_API_BIN
ECC_API_BIN=$("${cabal_cmd[@]}" list-bin exe:ecc-crm-api)
python3 scripts/bootstrap_acceptance.py
python3 scripts/system_test.py
if [[ -z "${CHROME_PATH:-}" ]]; then
  CHROME_PATH=$(command -v chromium || command -v chromium-browser || command -v google-chrome)
  export CHROME_PATH
fi
node --test --test-concurrency=1 test/browser-transport.test.cjs test/browser-acceptance.test.cjs scripts/mobile.browser.cjs test/finance-live.browser.cjs

# Reached only after backend, real HTTP, browser and mobile checks succeed.
python3 scripts/release.py seal --binary "$ECC_API_BIN"
