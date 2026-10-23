ALTER TABLE work_history ADD COLUMN task_id INTEGER;
ALTER TABLE work_history ADD COLUMN meeting_id INTEGER REFERENCES appointments(id) ON DELETE SET NULL;
ALTER TABLE invoices ADD COLUMN case_id INTEGER REFERENCES cases(id) ON DELETE SET NULL;
-- Extend the existing case, appointment and invoice records; no parallel CRM.
ALTER TABLE tasks ADD COLUMN scheduled_at TEXT;
ALTER TABLE tasks ADD COLUMN due_at TEXT;
ALTER TABLE tasks ADD COLUMN completed_at TEXT;
ALTER TABLE appointments ADD COLUMN case_id INTEGER REFERENCES cases(id) ON DELETE SET NULL;
ALTER TABLE appointments ADD COLUMN task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL;
ALTER TABLE appointments ADD COLUMN meeting_url TEXT NOT NULL DEFAULT '';
ALTER TABLE appointments ADD COLUMN meeting_id TEXT NOT NULL DEFAULT '';
ALTER TABLE appointments ADD COLUMN passcode TEXT NOT NULL DEFAULT '';
ALTER TABLE appointments ADD COLUMN client_visible INTEGER NOT NULL DEFAULT 0 CHECK(client_visible IN (0,1));
ALTER TABLE notifications ADD COLUMN archived_at TEXT;
CREATE TABLE commercial_documents (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 client_id INTEGER NOT NULL REFERENCES clients(id),
 case_id INTEGER NOT NULL REFERENCES cases(id),
 kind TEXT NOT NULL CHECK(kind IN ('proposal','contract')),
 title TEXT NOT NULL,
 body TEXT NOT NULL,
 currency TEXT NOT NULL DEFAULT 'PHP',
 fee_minor INTEGER NOT NULL DEFAULT 0 CHECK(fee_minor>=0),
 third_party_minor INTEGER NOT NULL DEFAULT 0 CHECK(third_party_minor>=0),
 other_minor INTEGER NOT NULL DEFAULT 0 CHECK(other_minor>=0),
 discount_minor INTEGER NOT NULL DEFAULT 0 CHECK(discount_minor>=0),
 tax_minor INTEGER NOT NULL DEFAULT 0 CHECK(tax_minor>=0),
 total_minor INTEGER NOT NULL DEFAULT 0 CHECK(total_minor>=0),
 valid_until TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'Draft' CHECK(status IN ('Draft','Issued','Viewed','Accepted','Rejected','Completed','Expired')),
 created_by INTEGER NOT NULL REFERENCES users(id),
 created_at TEXT NOT NULL DEFAULT(datetime('now')),
 issued_at TEXT,
 viewed_at TEXT,
 accepted_at TEXT,
 revision INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX commercial_client ON commercial_documents(client_id,case_id,id);
CREATE TABLE payment_instructions (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 client_id INTEGER NOT NULL REFERENCES clients(id),
 case_id INTEGER NOT NULL REFERENCES cases(id),
 invoice_id INTEGER NOT NULL REFERENCES invoices(id),
 bank TEXT NOT NULL,
 account_name TEXT NOT NULL,
 account_number TEXT NOT NULL,
 method TEXT NOT NULL,
 instructions TEXT NOT NULL,
 client_visible INTEGER NOT NULL DEFAULT 0 CHECK(client_visible IN (0,1)),
 created_by INTEGER NOT NULL REFERENCES users(id),
 created_at TEXT NOT NULL DEFAULT(datetime('now')),
 revision INTEGER NOT NULL DEFAULT 1,
 UNIQUE(invoice_id)
);
CREATE TRIGGER journey_task_created AFTER INSERT ON tasks BEGIN INSERT INTO work_history(lead_id,client_id,case_id,task_id,actor_id,kind,note) VALUES (NEW.lead_id,NEW.client_id,NEW.case_id,NEW.id,(SELECT actor_id FROM request_context WHERE id=1),'task.created','Task scheduled: '||NEW.title||' · Scheduled: '||coalesce(NEW.scheduled_at,'Not set')||' · Due: '||coalesce(NEW.due_at,NEW.due_date,'Not set')||' · Assigned: '||coalesce((SELECT name FROM users WHERE id=NEW.assigned_to_id),'Unassigned')||' · '||NEW.status); END;
CREATE TRIGGER journey_task_rescheduled AFTER UPDATE ON tasks WHEN NEW.scheduled_at IS NOT OLD.scheduled_at OR NEW.due_at IS NOT OLD.due_at OR NEW.due_date IS NOT OLD.due_date BEGIN INSERT INTO work_history(lead_id,client_id,case_id,task_id,actor_id,kind,note) VALUES (NEW.lead_id,NEW.client_id,NEW.case_id,NEW.id,(SELECT actor_id FROM request_context WHERE id=1),'task.rescheduled',NEW.title||' rescheduled · Previous: '||coalesce(OLD.scheduled_at,'Not set')||' / '||coalesce(OLD.due_at,OLD.due_date,'Not set')||' · New: '||coalesce(NEW.scheduled_at,'Not set')||' / '||coalesce(NEW.due_at,NEW.due_date,'Not set')); END;
CREATE TRIGGER journey_task_completed AFTER UPDATE ON tasks WHEN NEW.status='Done' AND OLD.status<>'Done' BEGIN INSERT INTO work_history(lead_id,client_id,case_id,task_id,actor_id,kind,note) VALUES (NEW.lead_id,NEW.client_id,NEW.case_id,NEW.id,(SELECT actor_id FROM request_context WHERE id=1),'task.completed',NEW.title||' completed'); UPDATE tasks SET completed_at=datetime('now') WHERE id=NEW.id; END;
CREATE TRIGGER journey_task_reopened AFTER UPDATE ON tasks WHEN NEW.status<>'Done' AND OLD.status='Done' BEGIN UPDATE tasks SET completed_at=NULL WHERE id=NEW.id; END;
CREATE TRIGGER journey_converted AFTER UPDATE ON leads WHEN OLD.converted_client_id IS NULL AND NEW.converted_client_id IS NOT NULL BEGIN INSERT INTO work_history(client_id,actor_id,kind,note) VALUES (NEW.converted_client_id,(SELECT actor_id FROM request_context WHERE id=1),'lead.converted','Lead converted to Client: '||NEW.full_name); END;

CREATE TRIGGER journey_stage_notification AFTER UPDATE OF stage ON cases WHEN NEW.stage IS NOT OLD.stage BEGIN INSERT OR IGNORE INTO notifications(user_id,kind,title,client_id,case_id,event_key) SELECT c.case_officer_id,'deadlines','Application status: '||OLD.stage||' -> '||NEW.stage,NEW.client_id,NEW.id,'journey-stage:'||NEW.id||':'||(SELECT revision FROM record_versions WHERE kind='cases' AND record_id=NEW.id)||':'||NEW.stage FROM clients c WHERE c.id=NEW.client_id AND c.case_officer_id IS NOT NULL; END;
