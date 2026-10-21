-- Student applications retain school/program and admission status per application.
ALTER TABLE cases ADD COLUMN institution TEXT NOT NULL DEFAULT '' CHECK(length(institution)<=255);
ALTER TABLE cases ADD COLUMN program TEXT NOT NULL DEFAULT '' CHECK(length(program)<=255);
ALTER TABLE cases ADD COLUMN offer_status TEXT NOT NULL DEFAULT 'Not requested' CHECK(offer_status IN ('Not requested','Requested','Conditional offer','Unconditional offer','Declined'));
ALTER TABLE cases ADD COLUMN enrollment_status TEXT NOT NULL DEFAULT 'Not enrolled' CHECK(enrollment_status IN ('Not enrolled','Pending','Confirmed','Deferred','Withdrawn'));
CREATE TABLE application_milestones (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 case_id INTEGER NOT NULL REFERENCES cases(id) ON DELETE CASCADE,
 kind TEXT NOT NULL CHECK(kind IN ('Offer','Deposit','Visa submission','Visa decision','Arrival','Other')),
 title TEXT NOT NULL CHECK(length(trim(title)) BETWEEN 1 AND 255),
 planned_on TEXT,
 completed_on TEXT,
 status TEXT NOT NULL DEFAULT 'Planned' CHECK(status IN ('Planned','In progress','Completed','Cancelled')),
 note TEXT NOT NULL DEFAULT '' CHECK(length(note)<=20000),
 revision INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL DEFAULT(datetime('now')),
 CHECK(status<>'Completed' OR completed_on IS NOT NULL)
);
CREATE INDEX application_milestones_case ON application_milestones(case_id,planned_on,id);
CREATE TRIGGER milestone_created AFTER INSERT ON application_milestones BEGIN
 UPDATE record_versions SET revision=revision+1 WHERE kind='cases' AND record_id=NEW.case_id;
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES('case',NEW.case_id,NEW.title,'updated',json_object('milestoneId',NEW.id,'kind',NEW.kind,'status',NEW.status),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER milestone_updated AFTER UPDATE ON application_milestones BEGIN
 UPDATE record_versions SET revision=revision+1 WHERE kind='cases' AND record_id=NEW.case_id;
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES('case',NEW.case_id,NEW.title,'updated',json_object('milestoneId',NEW.id,'status',json_object('from',OLD.status,'to',NEW.status)),(SELECT actor_id FROM request_context WHERE id=1));
END;
-- Editable starter examples: staff must verify each school's current requirements.
INSERT INTO checklist_templates(name,category,destination) VALUES('Student visa — starter checklist','Student Visa','') ON CONFLICT DO NOTHING;
INSERT INTO checklist_templates(name,category,destination) VALUES('School admission — starter checklist','School Admission','') ON CONFLICT DO NOTHING;
INSERT INTO checklist_template_items(template_id,title,required) SELECT id,'Identity document / passport',1 FROM checklist_templates WHERE name IN ('Student visa — starter checklist','School admission — starter checklist') ON CONFLICT DO NOTHING;
INSERT INTO checklist_template_items(template_id,title,required) SELECT id,'Academic transcripts',1 FROM checklist_templates WHERE name IN ('Student visa — starter checklist','School admission — starter checklist') ON CONFLICT DO NOTHING;
INSERT INTO checklist_template_items(template_id,title,required) SELECT id,'Offer or acceptance letter',1 FROM checklist_templates WHERE name='Student visa — starter checklist' ON CONFLICT DO NOTHING;
INSERT INTO checklist_template_items(template_id,title,required) SELECT id,'Evidence of financial support',0 FROM checklist_templates WHERE name='Student visa — starter checklist' ON CONFLICT DO NOTHING;
INSERT INTO checklist_template_items(template_id,title,required) SELECT id,'Language test result, if required',0 FROM checklist_templates WHERE name IN ('Student visa — starter checklist','School admission — starter checklist') ON CONFLICT DO NOTHING;

CREATE TRIGGER audit_application_details AFTER UPDATE OF institution,program,offer_status,enrollment_status ON cases WHEN OLD.institution IS NOT NEW.institution OR OLD.program IS NOT NEW.program OR OLD.offer_status IS NOT NEW.offer_status OR OLD.enrollment_status IS NOT NEW.enrollment_status BEGIN
 INSERT INTO audit_log(entity_type,entity_id,action,changes,actor_id) VALUES('case',NEW.id,'updated',(SELECT json_group_object(key,json(value)) FROM json_each(json_object('institution',json_object('from',OLD.institution,'to',NEW.institution),'program',json_object('from',OLD.program,'to',NEW.program),'offer_status',json_object('from',OLD.offer_status,'to',NEW.offer_status),'enrollment_status',json_object('from',OLD.enrollment_status,'to',NEW.enrollment_status))) WHERE json_extract(value,'$.from') IS NOT json_extract(value,'$.to')),(SELECT actor_id FROM request_context WHERE id=1));
END;
