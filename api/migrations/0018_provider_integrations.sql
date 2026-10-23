CREATE TABLE integration_jobs (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 provider TEXT NOT NULL CHECK(provider IN ('zoom','google','stripe','docusign')),
 record_kind TEXT NOT NULL CHECK(record_kind IN ('appointment','invoice','contract')),
 record_id INTEGER NOT NULL,
 source_revision INTEGER NOT NULL,
 client_id INTEGER NOT NULL REFERENCES clients(id),
 case_id INTEGER REFERENCES cases(id),
 actor_id INTEGER REFERENCES users(id),
 status TEXT NOT NULL DEFAULT 'Queued' CHECK(status IN ('Queued','Running','Succeeded','Failed','Review')),
 attempts INTEGER NOT NULL DEFAULT 0,
 lease_token TEXT,
 lease_until TEXT,
 next_attempt_at TEXT,
 error_code TEXT,
 created_at TEXT NOT NULL DEFAULT(datetime('now')),
 updated_at TEXT NOT NULL DEFAULT(datetime('now')),
 UNIQUE(provider,record_kind,record_id,source_revision)
);
CREATE INDEX integration_jobs_pending ON integration_jobs(status,next_attempt_at,id);
CREATE TABLE integration_links (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 job_id INTEGER NOT NULL UNIQUE REFERENCES integration_jobs(id),
 provider TEXT NOT NULL,
 record_kind TEXT NOT NULL,
 record_id INTEGER NOT NULL,
 client_id INTEGER NOT NULL REFERENCES clients(id),
 case_id INTEGER REFERENCES cases(id),
 remote_id TEXT NOT NULL,
 url TEXT NOT NULL DEFAULT '',
 status TEXT NOT NULL,
 source_revision INTEGER NOT NULL,
 amount_minor INTEGER,
 currency TEXT,
 payment_id INTEGER REFERENCES invoice_payments(id),
 signed_document_id INTEGER REFERENCES documents(id),
 remote_etag TEXT,
 checked_at TEXT,
 created_at TEXT NOT NULL DEFAULT(datetime('now')),
 UNIQUE(provider,remote_id)
);
CREATE INDEX integration_links_record ON integration_links(provider,record_kind,record_id,id);
CREATE TABLE integration_events (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 link_id INTEGER NOT NULL REFERENCES integration_links(id),
 event_key TEXT NOT NULL UNIQUE,
 status TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE TRIGGER integration_event_no_update BEFORE UPDATE ON integration_events BEGIN SELECT RAISE(ABORT,'Integration events are immutable'); END;
CREATE TRIGGER integration_event_no_delete BEFORE DELETE ON integration_events BEGIN SELECT RAISE(ABORT,'Integration events are retained'); END;

CREATE TABLE integration_worker_state (id INTEGER PRIMARY KEY CHECK(id=1), last_success_at TEXT);
INSERT INTO integration_worker_state(id) VALUES (1);
