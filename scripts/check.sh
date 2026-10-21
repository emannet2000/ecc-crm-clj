#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
(cd api && cabal test all)
python3 -m unittest discover -s tests -p 'test_*.py' -v
node --test tests/state.test.cjs
node --test tests/ui.test.cjs
