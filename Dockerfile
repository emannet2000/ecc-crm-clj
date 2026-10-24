ARG CLOJURE_IMAGE=clojure:temurin-21-tools-deps
FROM ${CLOJURE_IMAGE} AS frontend
RUN apt-get update && apt-get install -y --no-install-recommends nodejs npm && rm -rf /var/lib/apt/lists/*
WORKDIR /app/frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
RUN clojure -J-Xmx768m -M:build

FROM ${CLOJURE_IMAGE} AS backend
RUN apt-get update && apt-get install -y --no-install-recommends curl restic ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app/backend
COPY backend/deps.edn ./
RUN clojure -P -M:dev
COPY backend/src ./src
COPY backend/test ./test
RUN clojure -M:test
COPY --from=frontend /app/frontend/public /app/frontend/public
COPY scripts/clojure /app/scripts/clojure
RUN clojure -M -m ecc-crm.release generate .. ../release-clojure.json
RUN cp -a /root/.m2 /app/.m2
RUN groupadd --gid 10001 ecc && useradd --uid 10001 --gid ecc --home-dir /app ecc && mkdir -p /data/xtdb /data/blobs /snapshots /backup-status && chown -R ecc:ecc /data /app /snapshots /backup-status
ENV CLJ_CONFIG=/tmp/clojure-config CLJ_CACHE=/tmp/clojure-cache
ENV XTDB_DIR=/data/xtdb BLOB_DIR=/data/blobs WEB_DIST=/app/frontend/public BIND_HOST=0.0.0.0
USER 10001:10001
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s CMD curl --fail --silent http://127.0.0.1:4000/api/ready || exit 1
ENTRYPOINT ["clojure", "-M:dev"]
