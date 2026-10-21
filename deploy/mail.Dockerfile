FROM python:3.12-slim-bookworm@sha256:34386ef0cb081344d7ec1c103ba398e6e9f64e9ab3a1509accc92a4e24a07258
WORKDIR /app
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 worker && mkdir /backups && chown worker /backups
COPY scripts/scan_worker.py scripts/workflow_worker.py scripts/mail_worker.py scripts/monitor.py scripts/backup_worker.py scripts/sqlite_backup.py ./
USER worker
CMD ["python", "-u", "mail_worker.py"]
