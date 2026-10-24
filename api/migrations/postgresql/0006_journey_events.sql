ALTER TABLE work_history ADD COLUMN event_key TEXT;
CREATE UNIQUE INDEX work_history_event_key ON work_history(event_key);
