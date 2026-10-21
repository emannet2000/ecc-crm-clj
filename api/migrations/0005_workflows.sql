-- Expand audit categories while preserving existing entries and identifiers.
DROP TRIGGER audit_cases_delete;
DROP TRIGGER audit_cases_insert;
DROP TRIGGER audit_cases_update;
DROP TRIGGER audit_clients_delete;
DROP TRIGGER audit_clients_insert;
DROP TRIGGER audit_clients_update;
DROP TRIGGER audit_documents_delete;
DROP TRIGGER audit_documents_insert;
DROP TRIGGER audit_documents_update;
DROP TRIGGER audit_leads_delete;
DROP TRIGGER audit_leads_insert;
DROP TRIGGER audit_leads_update;
DROP TRIGGER audit_tasks_delete;
DROP TRIGGER audit_tasks_insert;
DROP TRIGGER audit_tasks_update;
DROP TRIGGER audit_users_delete;
DROP TRIGGER audit_users_insert;
DROP TRIGGER audit_users_update;
CREATE TABLE audit_log_next (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    entity_type VARCHAR(20)  NOT NULL CHECK (entity_type IN
                  ('lead', 'client', 'case', 'task', 'user', 'document', 'history', 'document_request', 'reminder_rule', 'saved_view', 'appointment', 'invoice', 'portal', 'session')),
    entity_id   INTEGER      NOT NULL,
    entity_name VARCHAR(300),
    action      VARCHAR(20)  NOT NULL CHECK (action IN
                  ('created', 'updated', 'deleted', 'access_changed', 'mfa_changed', 'revoked')),
    changes     TEXT,       -- {"Field": {"from": …, "to": …}} for updates
    actor_id    INTEGER REFERENCES users(id) ON DELETE SET NULL,
    created_at  TEXT  NOT NULL DEFAULT (datetime('now'))
);
INSERT INTO audit_log_next SELECT * FROM audit_log;
DROP TABLE audit_log;
ALTER TABLE audit_log_next RENAME TO audit_log;
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_actor  ON audit_log(actor_id);
CREATE INDEX idx_audit_time   ON audit_log(created_at);
CREATE TRIGGER audit_cases_delete AFTER DELETE ON cases BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('case',OLD.id,NULL,'deleted',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NULL),'client_id',json_object('from',OLD.client_id,'to',NULL),'service_category',json_object('from',OLD.service_category,'to',NULL),'destination',json_object('from',OLD.destination,'to',NULL),'stage',json_object('from',OLD.stage,'to',NULL),'next_deadline',json_object('from',OLD.next_deadline,'to',NULL),'created_at',json_object('from',OLD.created_at,'to',NULL))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_cases_insert AFTER INSERT ON cases BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('case',NEW.id,NULL,'created',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',NULL,'to',NEW.id),'client_id',json_object('from',NULL,'to',NEW.client_id),'service_category',json_object('from',NULL,'to',NEW.service_category),'destination',json_object('from',NULL,'to',NEW.destination),'stage',json_object('from',NULL,'to',NEW.stage),'next_deadline',json_object('from',NULL,'to',NEW.next_deadline),'created_at',json_object('from',NULL,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_cases_update AFTER UPDATE ON cases BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('case',NEW.id,NULL,'updated',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NEW.id),'client_id',json_object('from',OLD.client_id,'to',NEW.client_id),'service_category',json_object('from',OLD.service_category,'to',NEW.service_category),'destination',json_object('from',OLD.destination,'to',NEW.destination),'stage',json_object('from',OLD.stage,'to',NEW.stage),'next_deadline',json_object('from',OLD.next_deadline,'to',NEW.next_deadline),'created_at',json_object('from',OLD.created_at,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_clients_delete AFTER DELETE ON clients BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('client',OLD.id,OLD.full_name,'deleted',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NULL),'client_number',json_object('from',OLD.client_number,'to',NULL),'full_name',json_object('from',OLD.full_name,'to',NULL),'email',json_object('from',OLD.email,'to',NULL),'phone',json_object('from',OLD.phone,'to',NULL),'case_officer_id',json_object('from',OLD.case_officer_id,'to',NULL),'created_at',json_object('from',OLD.created_at,'to',NULL),'deleted_at',json_object('from',OLD.deleted_at,'to',NULL))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_clients_insert AFTER INSERT ON clients BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('client',NEW.id,NEW.full_name,'created',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',NULL,'to',NEW.id),'client_number',json_object('from',NULL,'to',NEW.client_number),'full_name',json_object('from',NULL,'to',NEW.full_name),'email',json_object('from',NULL,'to',NEW.email),'phone',json_object('from',NULL,'to',NEW.phone),'case_officer_id',json_object('from',NULL,'to',NEW.case_officer_id),'created_at',json_object('from',NULL,'to',NEW.created_at),'deleted_at',json_object('from',NULL,'to',NEW.deleted_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_clients_update AFTER UPDATE ON clients BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('client',NEW.id,NEW.full_name,'updated',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NEW.id),'client_number',json_object('from',OLD.client_number,'to',NEW.client_number),'full_name',json_object('from',OLD.full_name,'to',NEW.full_name),'email',json_object('from',OLD.email,'to',NEW.email),'phone',json_object('from',OLD.phone,'to',NEW.phone),'case_officer_id',json_object('from',OLD.case_officer_id,'to',NEW.case_officer_id),'created_at',json_object('from',OLD.created_at,'to',NEW.created_at),'deleted_at',json_object('from',OLD.deleted_at,'to',NEW.deleted_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_documents_delete AFTER DELETE ON documents BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('document',OLD.id,OLD.filename,'deleted',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NULL),'lead_id',json_object('from',OLD.lead_id,'to',NULL),'client_id',json_object('from',OLD.client_id,'to',NULL),'filename',json_object('from',OLD.filename,'to',NULL),'mime_type',json_object('from',OLD.mime_type,'to',NULL),'size',json_object('from',OLD.size,'to',NULL),'uploaded_by',json_object('from',OLD.uploaded_by,'to',NULL),'created_at',json_object('from',OLD.created_at,'to',NULL))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_documents_insert AFTER INSERT ON documents BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('document',NEW.id,NEW.filename,'created',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',NULL,'to',NEW.id),'lead_id',json_object('from',NULL,'to',NEW.lead_id),'client_id',json_object('from',NULL,'to',NEW.client_id),'filename',json_object('from',NULL,'to',NEW.filename),'mime_type',json_object('from',NULL,'to',NEW.mime_type),'size',json_object('from',NULL,'to',NEW.size),'uploaded_by',json_object('from',NULL,'to',NEW.uploaded_by),'created_at',json_object('from',NULL,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_documents_update AFTER UPDATE ON documents BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('document',NEW.id,NEW.filename,'updated',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NEW.id),'lead_id',json_object('from',OLD.lead_id,'to',NEW.lead_id),'client_id',json_object('from',OLD.client_id,'to',NEW.client_id),'filename',json_object('from',OLD.filename,'to',NEW.filename),'mime_type',json_object('from',OLD.mime_type,'to',NEW.mime_type),'size',json_object('from',OLD.size,'to',NEW.size),'uploaded_by',json_object('from',OLD.uploaded_by,'to',NEW.uploaded_by),'created_at',json_object('from',OLD.created_at,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_leads_delete AFTER DELETE ON leads BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('lead',OLD.id,OLD.full_name,'deleted',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NULL),'lead_number',json_object('from',OLD.lead_number,'to',NULL),'full_name',json_object('from',OLD.full_name,'to',NULL),'email',json_object('from',OLD.email,'to',NULL),'phone',json_object('from',OLD.phone,'to',NULL),'source',json_object('from',OLD.source,'to',NULL),'consultant_id',json_object('from',OLD.consultant_id,'to',NULL),'quality',json_object('from',OLD.quality,'to',NULL),'stage',json_object('from',OLD.stage,'to',NULL),'destination',json_object('from',OLD.destination,'to',NULL),'service',json_object('from',OLD.service,'to',NULL),'notes',json_object('from',OLD.notes,'to',NULL),'last_contact',json_object('from',OLD.last_contact,'to',NULL),'next_followup',json_object('from',OLD.next_followup,'to',NULL),'created_at',json_object('from',OLD.created_at,'to',NULL),'updated_at',json_object('from',OLD.updated_at,'to',NULL),'deleted_at',json_object('from',OLD.deleted_at,'to',NULL),'converted_client_id',json_object('from',OLD.converted_client_id,'to',NULL))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_leads_insert AFTER INSERT ON leads BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('lead',NEW.id,NEW.full_name,'created',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',NULL,'to',NEW.id),'lead_number',json_object('from',NULL,'to',NEW.lead_number),'full_name',json_object('from',NULL,'to',NEW.full_name),'email',json_object('from',NULL,'to',NEW.email),'phone',json_object('from',NULL,'to',NEW.phone),'source',json_object('from',NULL,'to',NEW.source),'consultant_id',json_object('from',NULL,'to',NEW.consultant_id),'quality',json_object('from',NULL,'to',NEW.quality),'stage',json_object('from',NULL,'to',NEW.stage),'destination',json_object('from',NULL,'to',NEW.destination),'service',json_object('from',NULL,'to',NEW.service),'notes',json_object('from',NULL,'to',NEW.notes),'last_contact',json_object('from',NULL,'to',NEW.last_contact),'next_followup',json_object('from',NULL,'to',NEW.next_followup),'created_at',json_object('from',NULL,'to',NEW.created_at),'updated_at',json_object('from',NULL,'to',NEW.updated_at),'deleted_at',json_object('from',NULL,'to',NEW.deleted_at),'converted_client_id',json_object('from',NULL,'to',NEW.converted_client_id))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_leads_update AFTER UPDATE ON leads BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('lead',NEW.id,NEW.full_name,'updated',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NEW.id),'lead_number',json_object('from',OLD.lead_number,'to',NEW.lead_number),'full_name',json_object('from',OLD.full_name,'to',NEW.full_name),'email',json_object('from',OLD.email,'to',NEW.email),'phone',json_object('from',OLD.phone,'to',NEW.phone),'source',json_object('from',OLD.source,'to',NEW.source),'consultant_id',json_object('from',OLD.consultant_id,'to',NEW.consultant_id),'quality',json_object('from',OLD.quality,'to',NEW.quality),'stage',json_object('from',OLD.stage,'to',NEW.stage),'destination',json_object('from',OLD.destination,'to',NEW.destination),'service',json_object('from',OLD.service,'to',NEW.service),'notes',json_object('from',OLD.notes,'to',NEW.notes),'last_contact',json_object('from',OLD.last_contact,'to',NEW.last_contact),'next_followup',json_object('from',OLD.next_followup,'to',NEW.next_followup),'created_at',json_object('from',OLD.created_at,'to',NEW.created_at),'updated_at',json_object('from',OLD.updated_at,'to',NEW.updated_at),'deleted_at',json_object('from',OLD.deleted_at,'to',NEW.deleted_at),'converted_client_id',json_object('from',OLD.converted_client_id,'to',NEW.converted_client_id))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_tasks_delete AFTER DELETE ON tasks BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('task',OLD.id,OLD.title,'deleted',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NULL),'lead_id',json_object('from',OLD.lead_id,'to',NULL),'client_id',json_object('from',OLD.client_id,'to',NULL),'title',json_object('from',OLD.title,'to',NULL),'description',json_object('from',OLD.description,'to',NULL),'due_date',json_object('from',OLD.due_date,'to',NULL),'priority',json_object('from',OLD.priority,'to',NULL),'status',json_object('from',OLD.status,'to',NULL),'assigned_to_id',json_object('from',OLD.assigned_to_id,'to',NULL),'created_at',json_object('from',OLD.created_at,'to',NULL))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_tasks_insert AFTER INSERT ON tasks BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('task',NEW.id,NEW.title,'created',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',NULL,'to',NEW.id),'lead_id',json_object('from',NULL,'to',NEW.lead_id),'client_id',json_object('from',NULL,'to',NEW.client_id),'title',json_object('from',NULL,'to',NEW.title),'description',json_object('from',NULL,'to',NEW.description),'due_date',json_object('from',NULL,'to',NEW.due_date),'priority',json_object('from',NULL,'to',NEW.priority),'status',json_object('from',NULL,'to',NEW.status),'assigned_to_id',json_object('from',NULL,'to',NEW.assigned_to_id),'created_at',json_object('from',NULL,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_tasks_update AFTER UPDATE ON tasks BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('task',NEW.id,NEW.title,'updated',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NEW.id),'lead_id',json_object('from',OLD.lead_id,'to',NEW.lead_id),'client_id',json_object('from',OLD.client_id,'to',NEW.client_id),'title',json_object('from',OLD.title,'to',NEW.title),'description',json_object('from',OLD.description,'to',NEW.description),'due_date',json_object('from',OLD.due_date,'to',NEW.due_date),'priority',json_object('from',OLD.priority,'to',NEW.priority),'status',json_object('from',OLD.status,'to',NEW.status),'assigned_to_id',json_object('from',OLD.assigned_to_id,'to',NEW.assigned_to_id),'created_at',json_object('from',OLD.created_at,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_users_delete AFTER DELETE ON users BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',OLD.id,OLD.name,'deleted',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NULL),'email',json_object('from',OLD.email,'to',NULL),'name',json_object('from',OLD.name,'to',NULL),'role',json_object('from',OLD.role,'to',NULL),'created_at',json_object('from',OLD.created_at,'to',NULL))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_users_insert AFTER INSERT ON users BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',NEW.id,NEW.name,'created',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',NULL,'to',NEW.id),'email',json_object('from',NULL,'to',NEW.email),'name',json_object('from',NULL,'to',NEW.name),'role',json_object('from',NULL,'to',NEW.role),'created_at',json_object('from',NULL,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_users_update AFTER UPDATE ON users BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',NEW.id,NEW.name,'updated',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('id',json_object('from',OLD.id,'to',NEW.id),'email',json_object('from',OLD.email,'to',NEW.email),'name',json_object('from',OLD.name,'to',NEW.name),'role',json_object('from',OLD.role,'to',NEW.role),'created_at',json_object('from',OLD.created_at,'to',NEW.created_at))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
-- Version counters are transactional, including direct SQL and background work.
CREATE TABLE record_versions(kind TEXT NOT NULL,record_id INTEGER NOT NULL,revision INTEGER NOT NULL DEFAULT 1,PRIMARY KEY(kind,record_id));
INSERT INTO record_versions(kind,record_id) SELECT 'leads',id FROM leads;
CREATE TRIGGER version_leads_insert AFTER INSERT ON leads BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('leads',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
CREATE TRIGGER version_leads_update AFTER UPDATE ON leads BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('leads',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
INSERT INTO record_versions(kind,record_id) SELECT 'clients',id FROM clients;
CREATE TRIGGER version_clients_insert AFTER INSERT ON clients BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('clients',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
CREATE TRIGGER version_clients_update AFTER UPDATE ON clients BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('clients',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
INSERT INTO record_versions(kind,record_id) SELECT 'cases',id FROM cases;
CREATE TRIGGER version_cases_insert AFTER INSERT ON cases BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('cases',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
CREATE TRIGGER version_cases_update AFTER UPDATE ON cases BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('cases',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
INSERT INTO record_versions(kind,record_id) SELECT 'tasks',id FROM tasks;
CREATE TRIGGER version_tasks_insert AFTER INSERT ON tasks BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('tasks',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
CREATE TRIGGER version_tasks_update AFTER UPDATE ON tasks BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('tasks',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
INSERT INTO record_versions(kind,record_id) SELECT 'documents',id FROM documents;
CREATE TRIGGER version_documents_insert AFTER INSERT ON documents BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('documents',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
CREATE TRIGGER version_documents_update AFTER UPDATE ON documents BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('documents',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
INSERT INTO record_versions(kind,record_id) SELECT 'users',id FROM users;
CREATE TRIGGER version_users_insert AFTER INSERT ON users BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('users',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;
CREATE TRIGGER version_users_update AFTER UPDATE ON users BEGIN INSERT INTO record_versions(kind,record_id,revision) VALUES ('users',NEW.id,1) ON CONFLICT(kind,record_id) DO UPDATE SET revision=revision+1; END;

ALTER TABLE users ADD COLUMN suspended INTEGER NOT NULL DEFAULT 0 CHECK(suspended IN (0,1));
ALTER TABLE users ADD COLUMN mfa_secret TEXT;
ALTER TABLE users ADD COLUMN mfa_pending TEXT;
ALTER TABLE users ADD COLUMN mfa_last_step INTEGER NOT NULL DEFAULT -1;
ALTER TABLE sessions ADD COLUMN mfa_verified INTEGER NOT NULL DEFAULT 0;
CREATE TABLE mfa_recovery_codes(user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,code_hash TEXT NOT NULL,PRIMARY KEY(user_id,code_hash));
CREATE TRIGGER revoke_suspended AFTER UPDATE OF suspended ON users WHEN NEW.suspended=1 BEGIN DELETE FROM sessions WHERE user_id=NEW.id; DELETE FROM account_tokens WHERE user_id=NEW.id; END;
ALTER TABLE tasks ADD COLUMN recurrence_days INTEGER CHECK(recurrence_days BETWEEN 1 AND 366);
ALTER TABLE tasks ADD COLUMN recurrence_parent INTEGER REFERENCES tasks(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX task_recurrence_once ON tasks(recurrence_parent) WHERE recurrence_parent IS NOT NULL;
CREATE TABLE work_history(id INTEGER PRIMARY KEY AUTOINCREMENT,lead_id INTEGER REFERENCES leads(id),client_id INTEGER REFERENCES clients(id),case_id INTEGER REFERENCES cases(id) ON DELETE SET NULL,actor_id INTEGER REFERENCES users(id) ON DELETE SET NULL,kind TEXT NOT NULL,note TEXT NOT NULL CHECK(length(trim(note)) BETWEEN 1 AND 20000),created_at TEXT NOT NULL DEFAULT (datetime('now')),CHECK(lead_id IS NOT NULL OR client_id IS NOT NULL));
CREATE INDEX work_history_client ON work_history(client_id,id);
CREATE TABLE document_requests(id INTEGER PRIMARY KEY AUTOINCREMENT,lead_id INTEGER REFERENCES leads(id),client_id INTEGER REFERENCES clients(id),case_id INTEGER REFERENCES cases(id) ON DELETE SET NULL,title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 255),required INTEGER NOT NULL DEFAULT 1,status TEXT NOT NULL DEFAULT 'Missing' CHECK(status IN ('Missing','Received','Approved','Rejected')),expires_on TEXT,review_note TEXT,reviewed_by INTEGER REFERENCES users(id),revision INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL DEFAULT(datetime('now')),CHECK((lead_id IS NOT NULL)+(client_id IS NOT NULL)=1));
CREATE TABLE document_versions(request_id INTEGER NOT NULL REFERENCES document_requests(id) ON DELETE CASCADE,document_id INTEGER NOT NULL UNIQUE REFERENCES documents(id) ON DELETE CASCADE,version INTEGER NOT NULL,created_at TEXT NOT NULL DEFAULT(datetime('now')),PRIMARY KEY(request_id,version));
CREATE TRIGGER document_request_version AFTER UPDATE ON document_requests WHEN NEW.revision=OLD.revision BEGIN UPDATE document_requests SET revision=revision+1 WHERE id=NEW.id; END;
CREATE TABLE reminder_rules(id INTEGER PRIMARY KEY AUTOINCREMENT,task_id INTEGER NOT NULL UNIQUE REFERENCES tasks(id) ON DELETE CASCADE,days_before INTEGER NOT NULL DEFAULT 1 CHECK(days_before BETWEEN 0 AND 365),escalate_after INTEGER NOT NULL DEFAULT 2 CHECK(escalate_after BETWEEN 1 AND 365),enabled INTEGER NOT NULL DEFAULT 1,revision INTEGER NOT NULL DEFAULT 1);
CREATE TABLE reminder_deliveries(task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,due_date TEXT NOT NULL,kind TEXT NOT NULL,recipient_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,PRIMARY KEY(task_id,due_date,kind,recipient_id));
CREATE TABLE merge_log(id INTEGER PRIMARY KEY AUTOINCREMENT,kind TEXT NOT NULL,source_id INTEGER NOT NULL,target_id INTEGER NOT NULL,actor_id INTEGER REFERENCES users(id),created_at TEXT NOT NULL DEFAULT(datetime('now')),UNIQUE(kind,source_id));
ALTER TABLE leads ADD COLUMN merged_into INTEGER REFERENCES leads(id);
ALTER TABLE clients ADD COLUMN merged_into INTEGER REFERENCES clients(id);
CREATE TABLE saved_views(id INTEGER PRIMARY KEY AUTOINCREMENT,user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),entity TEXT NOT NULL CHECK(entity IN ('leads','clients','tasks','cases')),query TEXT NOT NULL DEFAULT '',overdue INTEGER NOT NULL DEFAULT 0,mine INTEGER NOT NULL DEFAULT 0,revision INTEGER NOT NULL DEFAULT 1);
CREATE TABLE appointments(id INTEGER PRIMARY KEY AUTOINCREMENT,lead_id INTEGER REFERENCES leads(id),client_id INTEGER REFERENCES clients(id),owner_id INTEGER NOT NULL REFERENCES users(id),title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 255),starts_at TEXT NOT NULL,ends_at TEXT NOT NULL,location TEXT NOT NULL DEFAULT '',status TEXT NOT NULL DEFAULT 'Scheduled' CHECK(status IN ('Scheduled','Completed','Cancelled')),revision INTEGER NOT NULL DEFAULT 1,CHECK(ends_at>starts_at),CHECK((lead_id IS NOT NULL)+(client_id IS NOT NULL)=1));
CREATE INDEX appointments_owner_time ON appointments(owner_id,starts_at,ends_at);
CREATE TABLE invoices(id INTEGER PRIMARY KEY AUTOINCREMENT,client_id INTEGER NOT NULL REFERENCES clients(id),description TEXT NOT NULL CHECK(length(trim(description)) BETWEEN 1 AND 1000),currency TEXT NOT NULL CHECK(length(currency)=3),amount_minor INTEGER NOT NULL CHECK(amount_minor>0),due_date TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'Draft' CHECK(status IN ('Draft','Issued','Paid','Void')),paid_at TEXT,revision INTEGER NOT NULL DEFAULT 1,created_at TEXT NOT NULL DEFAULT(datetime('now')));
CREATE TABLE portal_links(id INTEGER PRIMARY KEY AUTOINCREMENT,client_id INTEGER NOT NULL REFERENCES clients(id),token_hash TEXT NOT NULL UNIQUE,expires_at TEXT NOT NULL,revoked INTEGER NOT NULL DEFAULT 0,created_by INTEGER REFERENCES users(id),created_at TEXT NOT NULL DEFAULT(datetime('now')));
CREATE TABLE portal_sessions(token_hash TEXT PRIMARY KEY,link_id INTEGER NOT NULL REFERENCES portal_links(id) ON DELETE CASCADE,expires_at TEXT NOT NULL);
CREATE TABLE portal_document_grants(link_id INTEGER NOT NULL REFERENCES portal_links(id) ON DELETE CASCADE,document_id INTEGER NOT NULL REFERENCES documents(id) ON DELETE CASCADE,PRIMARY KEY(link_id,document_id));
CREATE TRIGGER audit_work_history_insert AFTER INSERT ON work_history BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('history',NEW.id,NEW.note,'created',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_work_history_update AFTER UPDATE ON work_history BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('history',NEW.id,NEW.note,'updated',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_work_history_delete AFTER DELETE ON work_history BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('history',OLD.id,OLD.note,'deleted',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_document_requests_insert AFTER INSERT ON document_requests BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('document_request',NEW.id,NEW.title,'created',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_document_requests_update AFTER UPDATE ON document_requests BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('document_request',NEW.id,NEW.title,'updated',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_document_requests_delete AFTER DELETE ON document_requests BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('document_request',OLD.id,OLD.title,'deleted',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_reminder_rules_insert AFTER INSERT ON reminder_rules BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('reminder_rule',NEW.id,NEW.id,'created',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_reminder_rules_update AFTER UPDATE ON reminder_rules BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('reminder_rule',NEW.id,NEW.id,'updated',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_reminder_rules_delete AFTER DELETE ON reminder_rules BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('reminder_rule',OLD.id,OLD.id,'deleted',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_saved_views_insert AFTER INSERT ON saved_views BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('saved_view',NEW.id,NEW.name,'created',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_saved_views_update AFTER UPDATE ON saved_views BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('saved_view',NEW.id,NEW.name,'updated',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_saved_views_delete AFTER DELETE ON saved_views BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('saved_view',OLD.id,OLD.name,'deleted',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_appointments_insert AFTER INSERT ON appointments BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('appointment',NEW.id,NEW.title,'created',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_appointments_update AFTER UPDATE ON appointments BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('appointment',NEW.id,NEW.title,'updated',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_appointments_delete AFTER DELETE ON appointments BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('appointment',OLD.id,OLD.title,'deleted',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_invoices_insert AFTER INSERT ON invoices BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('invoice',NEW.id,NEW.description,'created',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_invoices_update AFTER UPDATE ON invoices BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('invoice',NEW.id,NEW.description,'updated',(SELECT actor_id FROM request_context WHERE id=1)); END;
CREATE TRIGGER audit_invoices_delete AFTER DELETE ON invoices BEGIN INSERT INTO audit_log(entity_type,entity_id,entity_name,action,actor_id) VALUES ('invoice',OLD.id,OLD.description,'deleted',(SELECT actor_id FROM request_context WHERE id=1)); END;
ALTER TABLE portal_links ADD COLUMN activated_at TEXT;
CREATE TRIGGER history_case_created AFTER INSERT ON cases BEGIN
 INSERT INTO work_history(client_id,case_id,actor_id,kind,note) VALUES (NEW.client_id,NEW.id,(SELECT actor_id FROM request_context WHERE id=1),CASE WHEN NEW.stage IN ('Approved','Completed') THEN 'case_completed' ELSE 'case_created' END,'Case created: '||coalesce(NEW.service_category,'Case')||' · '||NEW.stage);
END;
CREATE TRIGGER history_case_stage AFTER UPDATE OF stage ON cases WHEN NEW.stage IS NOT OLD.stage BEGIN
 INSERT INTO work_history(client_id,case_id,actor_id,kind,note) VALUES (NEW.client_id,NEW.id,(SELECT actor_id FROM request_context WHERE id=1),CASE WHEN NEW.stage IN ('Approved','Completed') THEN 'case_completed' ELSE 'case_updated' END,'Case stage: '||OLD.stage||' → '||NEW.stage);
END;
CREATE TRIGGER history_client_update AFTER UPDATE OF full_name,email,phone,case_officer_id ON clients BEGIN
 INSERT INTO work_history(client_id,actor_id,kind,note) VALUES (NEW.id,(SELECT actor_id FROM request_context WHERE id=1),'client_updated','Client contact or assignment updated');
END;
CREATE TABLE portal_upload_limits(link_id INTEGER NOT NULL REFERENCES portal_links(id) ON DELETE CASCADE,day TEXT NOT NULL,bytes INTEGER NOT NULL,files INTEGER NOT NULL,PRIMARY KEY(link_id,day));
CREATE TRIGGER audit_account_suspension AFTER UPDATE OF suspended ON users WHEN NEW.suspended IS NOT OLD.suspended BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',NEW.id,NEW.name,'access_changed',json_object('suspended',json_object('from',OLD.suspended,'to',NEW.suspended)),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER audit_account_mfa AFTER UPDATE OF mfa_secret ON users WHEN NEW.mfa_secret IS NOT OLD.mfa_secret BEGIN
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('user',NEW.id,NEW.name,'mfa_changed',json_object('enabled',json_object('from',OLD.mfa_secret IS NOT NULL,'to',NEW.mfa_secret IS NOT NULL)),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER parent_revision_tasks_insert AFTER INSERT ON tasks BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (NEW.client_id); END;
CREATE TRIGGER parent_revision_tasks_update AFTER UPDATE ON tasks BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id,NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id); END;
CREATE TRIGGER parent_revision_tasks_delete AFTER DELETE ON tasks BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id); END;
CREATE TRIGGER parent_revision_documents_insert AFTER INSERT ON documents BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (NEW.client_id); END;
CREATE TRIGGER parent_revision_documents_update AFTER UPDATE ON documents BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id,NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id); END;
CREATE TRIGGER parent_revision_documents_delete AFTER DELETE ON documents BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id); END;
CREATE TRIGGER parent_revision_cases_insert AFTER INSERT ON cases BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (NEW.client_id); END;
CREATE TRIGGER parent_revision_cases_update AFTER UPDATE ON cases BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id); END;
CREATE TRIGGER parent_revision_cases_delete AFTER DELETE ON cases BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id); END;
CREATE TRIGGER parent_revision_work_history_insert AFTER INSERT ON work_history BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (NEW.client_id); END;
CREATE TRIGGER parent_revision_work_history_update AFTER UPDATE ON work_history BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id,NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id); END;
CREATE TRIGGER parent_revision_work_history_delete AFTER DELETE ON work_history BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id); END;
CREATE TRIGGER parent_revision_document_requests_insert AFTER INSERT ON document_requests BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (NEW.client_id); END;
CREATE TRIGGER parent_revision_document_requests_update AFTER UPDATE ON document_requests BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id,NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id); END;
CREATE TRIGGER parent_revision_document_requests_delete AFTER DELETE ON document_requests BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id); END;
CREATE TRIGGER parent_revision_appointments_insert AFTER INSERT ON appointments BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (NEW.client_id); END;
CREATE TRIGGER parent_revision_appointments_update AFTER UPDATE ON appointments BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id,NEW.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id); END;
CREATE TRIGGER parent_revision_appointments_delete AFTER DELETE ON appointments BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id); UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id); END;
CREATE TRIGGER parent_revision_invoices_insert AFTER INSERT ON invoices BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (NEW.client_id); END;
CREATE TRIGGER parent_revision_invoices_update AFTER UPDATE ON invoices BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id); END;
CREATE TRIGGER parent_revision_invoices_delete AFTER DELETE ON invoices BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id); END;
CREATE TRIGGER parent_revision_activities_insert AFTER INSERT ON activities BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (NEW.lead_id); END;
CREATE TRIGGER parent_revision_activities_update AFTER UPDATE ON activities BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id,NEW.lead_id); END;
CREATE TRIGGER parent_revision_activities_delete AFTER DELETE ON activities BEGIN UPDATE record_versions SET revision=revision+1 WHERE kind='leads' AND record_id IN (OLD.lead_id); END;

CREATE INDEX history_case_completed ON work_history(case_id,kind,id);
CREATE INDEX document_requests_client ON document_requests(client_id,id);
CREATE INDEX document_requests_lead ON document_requests(lead_id,id);
CREATE INDEX portal_sessions_expiry ON portal_sessions(expires_at);
