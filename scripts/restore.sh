#!/usr/bin/env bash
set -euo pipefail
: "${RESTORE_DATABASE_PATH:?Set RESTORE_DATABASE_PATH to a new recovery database file}"
python3 "$(dirname "$0")/sqlite_backup.py" "${1:?Usage: restore.sh /secure/path/backup.sqlite3}" "$RESTORE_DATABASE_PATH"
