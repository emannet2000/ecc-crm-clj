-- Students share the client/case history while retaining education-specific data.
CREATE TABLE student_profiles (
    client_id INTEGER PRIMARY KEY REFERENCES clients(id),
    source_lead_id INTEGER UNIQUE REFERENCES leads(id),
    institution TEXT NOT NULL DEFAULT '',
    program TEXT NOT NULL DEFAULT '',
    intake_date TEXT,
    birth_date TEXT,
    nationality TEXT NOT NULL DEFAULT '',
    qualification TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'Preparing application' CHECK(status IN ('Preparing application','Applied','Offered','Enrolled','Graduated','On hold')),
    notes TEXT NOT NULL DEFAULT '',
    revision INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE TABLE student_photos (
    client_id INTEGER PRIMARY KEY REFERENCES student_profiles(client_id) ON UPDATE CASCADE,
    document_id INTEGER NOT NULL UNIQUE REFERENCES documents(id)
);
CREATE TRIGGER student_profile_insert AFTER INSERT ON student_profiles BEGIN
 UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id=NEW.client_id;
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('client',NEW.client_id,'Student profile','created',json_object('sourceLeadId',NEW.source_lead_id),(SELECT actor_id FROM request_context WHERE id=1));
END;
CREATE TRIGGER student_profile_update AFTER UPDATE ON student_profiles BEGIN
 UPDATE record_versions SET revision=revision+1 WHERE kind='clients' AND record_id IN (OLD.client_id,NEW.client_id);
 INSERT INTO audit_log(entity_type,entity_id,entity_name,action,changes,actor_id) VALUES ('client',NEW.client_id,'Student profile','updated',json_object('institution',NEW.institution,'program',NEW.program,'intakeDate',NEW.intake_date,'birthDate',NEW.birth_date,'nationality',NEW.nationality,'qualification',NEW.qualification,'status',NEW.status,'notes',NEW.notes),(SELECT actor_id FROM request_context WHERE id=1));
END;
