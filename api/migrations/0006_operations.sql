-- All new uploads are quarantined until an antivirus worker verifies their bytes.
ALTER TABLE documents ADD COLUMN scan_status TEXT NOT NULL DEFAULT 'Pending' CHECK(scan_status IN ('Pending','Scanning','Clean','Infected','Error'));
ALTER TABLE documents ADD COLUMN scan_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE documents ADD COLUMN scan_lease TEXT;
ALTER TABLE documents ADD COLUMN scan_until TEXT;
ALTER TABLE documents ADD COLUMN scan_detail TEXT;
ALTER TABLE documents ADD COLUMN scanned_at TEXT;
CREATE INDEX documents_scan_queue ON documents(scan_status,scan_until,id);
ALTER TABLE tasks ADD COLUMN case_id INTEGER REFERENCES cases(id) ON DELETE SET NULL;
ALTER TABLE mail_outbox ADD COLUMN actor_id INTEGER REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE mail_outbox ADD COLUMN lead_id INTEGER REFERENCES leads(id);
ALTER TABLE mail_outbox ADD COLUMN client_id INTEGER REFERENCES clients(id);
ALTER TABLE mail_outbox ADD COLUMN retry_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE mail_outbox ADD COLUMN retried_at TEXT;
ALTER TABLE mail_outbox ADD COLUMN next_attempt_at TEXT;
CREATE TABLE notification_preferences(user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,assignments INTEGER NOT NULL DEFAULT 1,deadlines INTEGER NOT NULL DEFAULT 1,documents INTEGER NOT NULL DEFAULT 1,escalations INTEGER NOT NULL DEFAULT 1,email_enabled INTEGER NOT NULL DEFAULT 1,revision INTEGER NOT NULL DEFAULT 1);
CREATE TABLE notifications(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,kind TEXT NOT NULL,title TEXT NOT NULL,lead_id INTEGER REFERENCES leads(id),client_id INTEGER REFERENCES clients(id),case_id INTEGER REFERENCES cases(id) ON DELETE SET NULL,created_at TEXT NOT NULL DEFAULT(datetime('now')),read_at TEXT,event_key TEXT NOT NULL,UNIQUE(user_id,event_key));
CREATE INDEX notifications_user ON notifications(user_id,id);
CREATE TABLE workload_snapshots(day TEXT NOT NULL,user_id INTEGER NOT NULL,staff_name TEXT NOT NULL,open_tasks INTEGER NOT NULL,overdue_tasks INTEGER NOT NULL,open_cases INTEGER NOT NULL,PRIMARY KEY(day,user_id));
CREATE TRIGGER notify_task_created AFTER INSERT ON tasks WHEN NEW.assigned_to_id IS NOT NULL BEGIN
 INSERT OR IGNORE INTO notifications(user_id,kind,title,lead_id,client_id,case_id,event_key) VALUES (NEW.assigned_to_id,'assignments','Assigned task: '||NEW.title,NEW.lead_id,NEW.client_id,NEW.case_id,'task:'||NEW.id||':assigned:'||NEW.assigned_to_id);
END;
CREATE TRIGGER notify_task_assigned AFTER UPDATE OF assigned_to_id ON tasks WHEN NEW.assigned_to_id IS NOT NULL AND NEW.assigned_to_id IS NOT OLD.assigned_to_id BEGIN
 INSERT OR IGNORE INTO notifications(user_id,kind,title,lead_id,client_id,case_id,event_key) VALUES (NEW.assigned_to_id,'assignments','Assigned task: '||NEW.title,NEW.lead_id,NEW.client_id,NEW.case_id,'task:'||NEW.id||':assigned:'||NEW.assigned_to_id||':'||(SELECT revision FROM record_versions WHERE kind='tasks' AND record_id=NEW.id));
END;
CREATE TRIGGER notify_document_rejected AFTER UPDATE OF status ON document_requests WHEN NEW.status='Rejected' AND OLD.status<>'Rejected' BEGIN
 INSERT OR IGNORE INTO notifications(user_id,kind,title,lead_id,client_id,case_id,event_key) SELECT coalesce((SELECT case_officer_id FROM clients WHERE id=NEW.client_id),(SELECT consultant_id FROM leads WHERE id=NEW.lead_id)),'documents','Document rejected: '||NEW.title,NEW.lead_id,NEW.client_id,NEW.case_id,'document:'||NEW.id||':rejected:'||OLD.revision WHERE coalesce((SELECT case_officer_id FROM clients WHERE id=NEW.client_id),(SELECT consultant_id FROM leads WHERE id=NEW.lead_id)) IS NOT NULL;
END;
CREATE TRIGGER task_case_owner_insert BEFORE INSERT ON tasks WHEN NEW.case_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM cases WHERE id=NEW.case_id AND client_id=NEW.client_id) BEGIN SELECT RAISE(ABORT,'Task case must belong to its client'); END;
CREATE TRIGGER task_case_owner_update BEFORE UPDATE OF case_id,client_id ON tasks WHEN NEW.case_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM cases WHERE id=NEW.case_id AND client_id=NEW.client_id) BEGIN SELECT RAISE(ABORT,'Task case must belong to its client'); END;
-- Approvals already in the database also wait for a successful scan before downloads.
CREATE TRIGGER scan_content_changed AFTER UPDATE OF content ON documents BEGIN UPDATE documents SET scan_status='Pending',scan_attempts=0,scan_lease=NULL,scan_until=NULL,scan_detail=NULL,scanned_at=NULL WHERE id=NEW.id; END;
