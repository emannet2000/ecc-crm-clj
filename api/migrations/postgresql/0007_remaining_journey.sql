ALTER TABLE tasks ADD COLUMN notes TEXT NOT NULL DEFAULT '';
ALTER TABLE tasks ADD COLUMN cancelled_at TEXT;
ALTER TABLE appointments ADD COLUMN notes TEXT NOT NULL DEFAULT '';
ALTER TABLE cases ADD COLUMN consultant_id BIGINT REFERENCES users(id);
ALTER TABLE invoices ADD COLUMN line_items TEXT NOT NULL DEFAULT '';
ALTER TABLE invoices ADD COLUMN subtotal_minor BIGINT NOT NULL DEFAULT 0;
ALTER TABLE invoices ADD COLUMN discount_minor BIGINT NOT NULL DEFAULT 0;
ALTER TABLE invoices ADD COLUMN tax_minor BIGINT NOT NULL DEFAULT 0;
UPDATE invoices SET subtotal_minor=amount_minor;
ALTER TABLE leads ADD COLUMN address_line1 TEXT NOT NULL DEFAULT '';
ALTER TABLE leads ADD COLUMN address_line2 TEXT NOT NULL DEFAULT '';
ALTER TABLE leads ADD COLUMN city TEXT NOT NULL DEFAULT '';
ALTER TABLE leads ADD COLUMN province TEXT NOT NULL DEFAULT '';
ALTER TABLE leads ADD COLUMN postal_code TEXT NOT NULL DEFAULT '';
ALTER TABLE leads ADD COLUMN address_country TEXT NOT NULL DEFAULT '';
ALTER TABLE clients ADD COLUMN address_line1 TEXT NOT NULL DEFAULT '';
ALTER TABLE clients ADD COLUMN address_line2 TEXT NOT NULL DEFAULT '';
ALTER TABLE clients ADD COLUMN city TEXT NOT NULL DEFAULT '';
ALTER TABLE clients ADD COLUMN province TEXT NOT NULL DEFAULT '';
ALTER TABLE clients ADD COLUMN postal_code TEXT NOT NULL DEFAULT '';
ALTER TABLE clients ADD COLUMN address_country TEXT NOT NULL DEFAULT '';
CREATE TABLE client_messages (
 id BIGSERIAL PRIMARY KEY,
 client_id BIGINT NOT NULL REFERENCES clients(id),
 case_id BIGINT REFERENCES cases(id),
 title TEXT NOT NULL,
 body TEXT NOT NULL,
 status TEXT NOT NULL DEFAULT 'Draft' CHECK(status IN ('Draft','Published','Withdrawn')),
 created_by BIGINT NOT NULL REFERENCES users(id),
 approved_by BIGINT REFERENCES users(id),
 published_at TEXT,
 created_at TEXT NOT NULL DEFAULT(ecc_datetime('now')),
 revision BIGINT NOT NULL DEFAULT 1
);
CREATE INDEX client_messages_scope ON client_messages(client_id,case_id,id);
CREATE TABLE business_events (
 id BIGSERIAL PRIMARY KEY,
 entity TEXT NOT NULL,
 record_id BIGINT NOT NULL,
 operation TEXT NOT NULL,
 actor_id BIGINT,
 before_state TEXT,
 after_state TEXT,
 created_at TEXT NOT NULL DEFAULT(ecc_datetime('now'))
);
CREATE INDEX business_events_record ON business_events(entity,record_id,id);
CREATE FUNCTION business_events_immutable_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'Business events are append-only'; END $$;
CREATE TRIGGER business_events_immutable BEFORE UPDATE OR DELETE ON business_events FOR EACH ROW EXECUTE FUNCTION business_events_immutable_fn();
CREATE FUNCTION invoice_components_locked_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF OLD.status<>'Draft' AND (NEW.line_items IS DISTINCT FROM OLD.line_items OR NEW.subtotal_minor IS DISTINCT FROM OLD.subtotal_minor OR NEW.discount_minor IS DISTINCT FROM OLD.discount_minor OR NEW.tax_minor IS DISTINCT FROM OLD.tax_minor) THEN RAISE EXCEPTION 'Issued invoice components are immutable'; END IF; RETURN NEW; END $$;
CREATE TRIGGER invoice_components_locked BEFORE UPDATE ON invoices FOR EACH ROW EXECUTE FUNCTION invoice_components_locked_fn();
CREATE FUNCTION payment_application_progress_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF NEW.amount_minor>0 THEN UPDATE cases SET stage='Document Collection' WHERE stage='Awaiting Payment' AND id IN (SELECT case_id FROM invoice_balances WHERE id=NEW.invoice_id AND balance_minor=0); END IF; RETURN NEW; END $$;
CREATE TRIGGER payment_application_progress AFTER INSERT ON invoice_payments FOR EACH ROW EXECUTE FUNCTION payment_application_progress_fn();
CREATE FUNCTION conversion_address_fn() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
 IF OLD.converted_client_id IS NULL AND NEW.converted_client_id IS NOT NULL THEN UPDATE clients SET address_line1=NEW.address_line1,address_line2=NEW.address_line2,city=NEW.city,province=NEW.province,postal_code=NEW.postal_code,address_country=NEW.address_country WHERE id=NEW.converted_client_id; END IF; RETURN NEW; END $$;
CREATE TRIGGER conversion_address AFTER UPDATE OF converted_client_id ON leads FOR EACH ROW EXECUTE FUNCTION conversion_address_fn();
CREATE FUNCTION capture_business_event_fn() RETURNS trigger LANGUAGE plpgsql AS $$ DECLARE pre json; post json; rid BIGINT; BEGIN
 IF TG_OP<>'INSERT' THEN pre=row_to_json(OLD); END IF;
 IF TG_OP<>'DELETE' THEN post=row_to_json(NEW); END IF;
 rid=coalesce((post->>'id')::bigint,(pre->>'id')::bigint,(post->>'document_id')::bigint,(pre->>'document_id')::bigint);
 INSERT INTO business_events(entity,record_id,operation,actor_id,before_state,after_state) VALUES(TG_TABLE_NAME,rid,lower(TG_OP),(SELECT actor_id FROM request_context WHERE id=1),pre::text,post::text);
 RETURN NULL; END $$;
CREATE TRIGGER events_leads AFTER INSERT OR UPDATE OR DELETE ON leads FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_clients AFTER INSERT OR UPDATE OR DELETE ON clients FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_cases AFTER INSERT OR UPDATE OR DELETE ON cases FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_tasks AFTER INSERT OR UPDATE OR DELETE ON tasks FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_appointments AFTER INSERT OR UPDATE OR DELETE ON appointments FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_invoices AFTER INSERT OR UPDATE OR DELETE ON invoices FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_invoice_payments AFTER INSERT OR UPDATE OR DELETE ON invoice_payments FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_commercial_documents AFTER INSERT OR UPDATE OR DELETE ON commercial_documents FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_payment_instructions AFTER INSERT OR UPDATE OR DELETE ON payment_instructions FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_document_requests AFTER INSERT OR UPDATE OR DELETE ON document_requests FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_work_history AFTER INSERT OR UPDATE OR DELETE ON work_history FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_client_messages AFTER INSERT OR UPDATE OR DELETE ON client_messages FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER events_portal_document_grants AFTER INSERT OR UPDATE OR DELETE ON portal_document_grants FOR EACH ROW EXECUTE FUNCTION capture_business_event_fn();
CREATE TRIGGER ecc_lock BEFORE INSERT OR UPDATE OR DELETE ON client_messages FOR EACH STATEMENT EXECUTE FUNCTION ecc_write_lock();
CREATE TRIGGER ecc_lock BEFORE INSERT OR UPDATE OR DELETE ON business_events FOR EACH STATEMENT EXECUTE FUNCTION ecc_write_lock();
CREATE OR REPLACE VIEW invoice_balances AS
 SELECT i.id,i.client_id,i.description,i.currency,i.amount_minor,i.due_date,i.status,i.paid_at,i.revision,i.created_at,i.issued_at,
 coalesce((SELECT sum(p.amount_minor) FROM invoice_payments p WHERE p.invoice_id=i.id),0) AS paid_minor,
 i.amount_minor-coalesce((SELECT sum(p.amount_minor) FROM invoice_payments p WHERE p.invoice_id=i.id),0) AS balance_minor,i.case_id,
 i.line_items,i.subtotal_minor,i.discount_minor,i.tax_minor FROM invoices i;
