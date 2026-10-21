ALTER TABLE cases ADD COLUMN intake_date TEXT;
CREATE INDEX cases_intake ON cases(intake_date);
CREATE TABLE checklist_templates (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 150),
 category TEXT NOT NULL,
 destination TEXT NOT NULL DEFAULT '',
 revision INTEGER NOT NULL DEFAULT 1,
 UNIQUE(name,category,destination)
);
CREATE TABLE checklist_template_items (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 template_id INTEGER NOT NULL REFERENCES checklist_templates(id) ON DELETE CASCADE,
 title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 255),
 required INTEGER NOT NULL DEFAULT 1,
 UNIQUE(template_id,title COLLATE NOCASE)
);
CREATE TABLE applied_checklist_items (
 case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
 template_id INTEGER NOT NULL REFERENCES checklist_templates(id),
 title_key TEXT NOT NULL,
 request_id INTEGER NOT NULL REFERENCES document_requests(id) ON DELETE CASCADE,
 PRIMARY KEY(case_id,template_id,title_key)
);
