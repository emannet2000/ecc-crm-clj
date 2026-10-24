#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
pg_bin=${PG_BIN:-/usr/lib/postgresql/18/bin}
pg_work=$(mktemp -d /tmp/ecc-clojure-pg.XXXXXX)
pg_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
trap '"$pg_bin/pg_ctl" -D "$pg_work/data" -m immediate stop >/dev/null 2>&1 || true' EXIT
"$pg_bin/initdb" -D "$pg_work/data" -A trust --no-locale --encoding UTF8 > "$pg_work/init.log"
"$pg_bin/pg_ctl" -D "$pg_work/data" -l "$pg_work/server.log" -o "-p $pg_port -h 127.0.0.1 -k $pg_work" start > "$pg_work/start.log"
"$pg_bin/psql" -h 127.0.0.1 -p "$pg_port" -d postgres -v ON_ERROR_STOP=1 > "$pg_work/fixture.log" <<'SQL'
CREATE TABLE users(id bigserial PRIMARY KEY, name text, email text, role text, password_hash text, suspended integer);
INSERT INTO users VALUES(1,'Migration admin','fixture@example.com','admin','fixture-hash',0);
CREATE TABLE leads(id bigserial PRIMARY KEY, full_name text, lead_number text, stage text, consultant_id bigint, created_at timestamp, revision integer);
INSERT INTO leads VALUES(10,'Migrated student','L-2026-0010','New Lead',1,'2026-10-24 01:00:00',3);
SELECT setval('leads_id_seq',100);
CREATE TABLE clients(id bigserial PRIMARY KEY, full_name text, case_officer_id bigint);
INSERT INTO clients VALUES(1,'Migrated client',1);
CREATE TABLE documents(id bigserial PRIMARY KEY, client_id bigint, filename text, content bytea, size bigint);
INSERT INTO documents VALUES(1,1,'test.txt',decode('68656c6c6f','hex'),5);
CREATE TABLE appointments(id bigserial PRIMARY KEY, client_id bigint, client_visible integer);
INSERT INTO appointments VALUES(1,1,0);
CREATE TABLE user_access(user_id bigint PRIMARY KEY, access_level text, privileges jsonb);
INSERT INTO user_access VALUES(1,'assigned','["edit","download"]');
SQL
export SOURCE_JDBC_URL="jdbc:postgresql://127.0.0.1:$pg_port/postgres?user=$(id -un)"
(cd backend && clojure -M -m ecc-crm.postgres-check)
