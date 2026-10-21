#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../web"
mkdir -p dist/css
compiler="${ELM_BIN:-elm}"
if [ "$("$compiler" --version)" != '0.19.1' ]; then
  if [ -z "${ELM_BIN:-}" ] && [ -x /usr/bin/elm ] && [ "$(/usr/bin/elm --version)" = '0.19.1' ]; then
    compiler=/usr/bin/elm
  else
    echo 'Elm 0.19.1 is required. Set ELM_BIN to its executable.' >&2
    exit 1
  fi
fi
"$compiler" make src/Main.elm --optimize --output=dist/main.js
cp public/index.html public/bootstrap.js public/reports.js public/finance-print.js public/guide.html dist/
cp public/css/app.css dist/css/
cp public/manifest.webmanifest public/sw.js public/offline.html dist/
mkdir -p dist/brand
cp public/brand/ecc-emblem.png dist/brand/
mkdir -p dist/icons
cp public/icons/*.png dist/icons/

python3 ../scripts/release.py build --web dist
