#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
(cd frontend && npm ci --no-audit --no-fund && clojure -J-Xmx768m -M:build)
(cd backend && clojure -M:test)
printf '%s\n' 'Clojure backend checks and ClojureScript production build passed.'
(cd backend && clojure -M -m ecc-crm.release generate .. ../release-clojure.json)
