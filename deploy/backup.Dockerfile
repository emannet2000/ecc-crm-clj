FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends python3 restic ca-certificates && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 worker && mkdir /backups && chown worker /backups
WORKDIR /app
COPY scripts/backup_worker.py scripts/sqlite_backup.py ./
USER worker
ENV RESTIC_CACHE_DIR=/tmp/restic-cache
CMD ["python3", "-u", "backup_worker.py"]
