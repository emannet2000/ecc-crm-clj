#!/usr/bin/env bash
set -euo pipefail
umask 077
: "${BACKUP_TOKEN:?Set BACKUP_TOKEN}"
[[ "$BACKUP_TOKEN" =~ ^[A-Za-z0-9_-]{32,}$ ]] || { echo 'BACKUP_TOKEN must use at least 32 URL-safe characters' >&2; exit 1; }
mkdir -p /snapshots /backup-status
interval=${BACKUP_INTERVAL_SECONDS:-3600}
keep=${BACKUP_KEEP_LOCAL:-24}
[[ "$interval" =~ ^[0-9]+$ && "$keep" =~ ^[0-9]+$ ]] && (( interval >= 60 && keep >= 1 )) || exit 1
config_file=$(mktemp /tmp/ecc-backup-curl.XXXXXX)
trap 'rm -f "$config_file"' EXIT
printf 'header = "Authorization: Bearer %s"\n' "$BACKUP_TOKEN" > "$config_file"
while true; do
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  destination="/snapshots/ecc-$stamp.zip"
  if curl --silent --show-error --fail --max-time 600 --config "$config_file" "${BACKUP_URL:-http://api:4000/internal/backup}" --output "$destination.part"; then
    mv "$destination.part" "$destination"
    date +%s > /backup-status/local-success
    if [[ -n "${RESTIC_REPOSITORY:-}" ]]; then
      if restic backup --host "${BACKUP_HOST_ID:-ecc-workspace}" --tag ecc-clojure "$destination" && restic forget --group-by host,tags --host "${BACKUP_HOST_ID:-ecc-workspace}" --tag ecc-clojure --keep-daily 7 --keep-weekly 4 --keep-monthly 12 && restic check; then
        date +%s > /backup-status/offhost-success
      else
        echo 'offhost_backup_failed' >&2
      fi
    fi
    count=0
    while IFS= read -r file; do
      count=$((count + 1))
      if (( count > keep )); then rm -f -- "$file"; fi
    done < <(find /snapshots -maxdepth 1 -type f -name 'ecc-????????T??????Z.zip' -printf '%p\n' | sort -r)
  else
    echo 'local_backup_failed' >&2
    rm -f -- "$destination.part"
  fi
  sleep "$interval"
done
