-- Document upload/management: file bytes live in SQLite (BLOB); each
-- document attaches to exactly one lead or client.

CREATE TABLE IF NOT EXISTS documents (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    lead_id     INTEGER REFERENCES leads(id) ON DELETE CASCADE,
    client_id   INTEGER REFERENCES clients(id) ON DELETE CASCADE,
    filename    VARCHAR(255) NOT NULL,
    mime_type   VARCHAR(255) NOT NULL DEFAULT 'application/octet-stream',
    size        INTEGER NOT NULL DEFAULT 0,
    content     BLOB NOT NULL,
    uploaded_by INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    CHECK (((lead_id IS NOT NULL) + (client_id IS NOT NULL)) = 1)
);
CREATE INDEX IF NOT EXISTS idx_documents_lead   ON documents(lead_id);
CREATE INDEX IF NOT EXISTS idx_documents_client ON documents(client_id);
