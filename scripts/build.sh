#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
elm_compiler="${ELM_BIN:-elm}"
if [ "$("$elm_compiler" --version)" != '0.19.1' ]; then
  echo 'Elm 0.19.1 is required. Set ELM_BIN to its executable.' >&2
  exit 1
fi
mkdir -p web/dist/css
(cd web && "$elm_compiler" make src/Main.elm --optimize --output=dist/main.js)
cp web/public/index.html web/public/bootstrap.js web/dist/
cp web/public/css/app.css web/dist/css/
(cd api && cabal build all)
