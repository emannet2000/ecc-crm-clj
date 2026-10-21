-- Converted-client history previously searched every lead on each client read.
CREATE INDEX leads_converted_client ON leads(converted_client_id) WHERE converted_client_id IS NOT NULL;
-- Client profile selects the earliest open application and task.
CREATE INDEX cases_client_deadline ON cases(client_id,next_deadline,id);
CREATE INDEX tasks_client_due ON tasks(client_id,due_date,id);
CREATE INDEX work_history_lead ON work_history(lead_id,id);
