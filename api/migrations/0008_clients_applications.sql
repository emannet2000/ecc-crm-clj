-- Restore the Clients + Applications workflow without deleting client records.
CREATE TABLE client_photos (
    client_id INTEGER PRIMARY KEY REFERENCES clients(id),
    document_id INTEGER NOT NULL UNIQUE REFERENCES documents(id)
);
INSERT INTO client_photos(client_id,document_id)
SELECT client_id,document_id FROM student_photos;
-- Keep any education notes already entered in the client's existing history.
INSERT INTO work_history(client_id,kind,note)
SELECT client_id,'profile_migration','Previous education profile: ' || json_object(
 'institution',institution,'program',program,'intakeDate',intake_date,
 'birthDate',birth_date,'nationality',nationality,'qualification',qualification,
 'status',status,'notes',notes,'sourceLeadId',source_lead_id)
FROM student_profiles;
DROP TABLE student_photos;
DROP TABLE student_profiles;
