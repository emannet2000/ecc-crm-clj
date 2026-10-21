ARG HASKELL_IMAGE=haskell:9.6.6-slim-bookworm
FROM node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5 AS frontend
RUN npm install -g elm@0.19.1-6
WORKDIR /src/web
COPY web/elm.json ./
COPY web/src ./src
COPY web/public ./public
RUN mkdir -p dist/css && elm make src/Main.elm --optimize --output=dist/main.js && cp public/index.html public/bootstrap.js dist/ && cp public/css/app.css dist/css/

FROM ${HASKELL_IMAGE} AS backend
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends libsqlite3-dev pkg-config && rm -rf /var/lib/apt/lists/*
WORKDIR /src/api
COPY api/ecc-crm-api.cabal api/cabal.project api/cabal.project.freeze ./
RUN cabal update && cabal build --only-dependencies
COPY api/app ./app
COPY api/src ./src
RUN cabal build && cp "$(cabal list-bin exe:ecc-crm-api)" /usr/local/bin/ecc-crm-api

FROM debian:bookworm-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends libsqlite3-0 libgmp10 ca-certificates curl python3 && rm -rf /var/lib/apt/lists/* && useradd --system --uid 10001 app && mkdir -p /data && chown app /data
WORKDIR /app
COPY --from=backend /usr/local/bin/ecc-crm-api /usr/local/bin/
COPY --from=frontend /src/web/dist ./web
COPY api/migrations ./migrations
COPY scripts/backup.sh scripts/restore.sh scripts/sqlite_backup.py ./scripts/
ENV APP_ENV=production PORT=4000 WEB_DIST=/app/web SEED_DEMO=false DATABASE_PATH=/data/ecc-crm.sqlite3
VOLUME ["/data"]
USER app
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD curl --fail http://127.0.0.1:4000/api/ready || exit 1
ENTRYPOINT ["ecc-crm-api"]
