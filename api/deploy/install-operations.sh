#!/usr/bin/env bash
# Run on the production host after configuring the private environment files.
set -euo pipefail
project_dir=$(cd "$(dirname "$0")/.." && pwd)
if [[ "$project_dir" != /opt/ecc/api ]]; then
  echo 'Install the reviewed application at /opt/ecc/api before installing these units.' >&2
  exit 1
fi
for config in /etc/ecc/recovery.env /etc/ecc/workers.env; do
  [[ -r "$config" ]] || { echo "Missing $config" >&2; exit 1; }
done
command -v restic >/dev/null
for unit in ecc-verified-backup.service ecc-verified-backup.timer ecc-monitor.service ecc-monitor.timer ecc-mail.service ecc-scan.service ecc-alert-test.service; do
  install -m 0644 "$project_dir/deploy/$unit" "/etc/systemd/system/$unit"
done
systemctl daemon-reload
# Verify the replacement before stopping an existing local-only backup manager.
systemctl start ecc-verified-backup.service
systemctl start ecc-alert-test.service
systemctl enable --now ecc-verified-backup.timer ecc-monitor.timer ecc-mail.service ecc-scan.service
systemctl restart ecc-mail.service ecc-scan.service
systemctl is-active ecc-verified-backup.timer ecc-monitor.timer ecc-mail.service ecc-scan.service
# Migrate a prior continuously running local-only manager after verification.
systemctl stop ecc-recovery.service 2>/dev/null || true
systemctl disable ecc-recovery.service 2>/dev/null || true
systemctl start ecc-monitor.service
