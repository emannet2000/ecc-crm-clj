#!/usr/bin/env bash
set -euo pipefail
: "${DATABASE_PATH:?Set DATABASE_PATH}"
python3 "$(dirname "$0")/sqlite_backup.py" "$DATABASE_PATH" "${1:?Usage: backup.sh /secure/path/backup.sqlite3}"
