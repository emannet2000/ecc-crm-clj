-- Run against an isolated schema. Every assertion uses real PostgreSQL storage.
DO $acceptance$
DECLARE uid bigint; cid bigint; lid bigint; did bigint; iid bigint; pid bigint;
        eid bigint; rid bigint; appid bigint; version_before bigint; rejected boolean;
BEGIN
 INSERT INTO users(email,password_hash,name,role) VALUES('postgres-test@example.invalid','fixture-hash','Postgres test','admin') RETURNING id INTO uid;
 INSERT INTO request_context(id,actor_id,role,assigned_only) VALUES(1,uid,'admin','false')
 ON CONFLICT(id) DO UPDATE SET actor_id=excluded.actor_id,role=excluded.role;
 INSERT INTO clients(client_number,full_name,case_officer_id) VALUES('PG-TEST','Test student',uid) RETURNING id INTO cid;
 IF NOT EXISTS(SELECT 1 FROM audit_log WHERE entity_type='client' AND entity_id=cid AND actor_id=uid) THEN
  RAISE EXCEPTION 'Student audit must retain the actor';
 END IF;
 INSERT INTO cases(client_id,service_category,stage) VALUES(cid,'Student Visa','Submitted') RETURNING id INTO appid;
 UPDATE cases SET institution='Acceptance College',program='Nursing' WHERE id=appid;
 IF NOT EXISTS(SELECT 1 FROM audit_log WHERE entity_type='case' AND entity_id=appid AND changes::jsonb->'institution'->>'to'='Acceptance College') THEN RAISE EXCEPTION 'School changes must be audited'; END IF;
 SELECT revision INTO version_before FROM record_versions WHERE kind='cases' AND record_id=appid;
 INSERT INTO application_milestones(case_id,kind,title,planned_on) VALUES(appid,'Offer','Review offer','2020-01-01');
 IF (SELECT revision FROM record_versions WHERE kind='cases' AND record_id=appid)<>version_before+1 THEN RAISE EXCEPTION 'Milestone must update application revision'; END IF;
 INSERT INTO leads(lead_number,full_name,consultant_id) VALUES('PG-LEAD','Test lead',uid) RETURNING id INTO lid;
 SELECT revision INTO version_before FROM record_versions WHERE kind='leads' AND record_id=lid;
 UPDATE leads SET full_name='Updated lead' WHERE id=lid;
 IF (SELECT revision FROM record_versions WHERE kind='leads' AND record_id=lid)<>version_before+1 THEN
  RAISE EXCEPTION 'Lead revisions must advance exactly once';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM audit_log WHERE entity_type='lead' AND entity_id=lid AND action='updated' AND changes::jsonb->'full_name'->>'to'='Updated lead') THEN
  RAISE EXCEPTION 'Before/after audit values must be preserved';
 END IF;
 INSERT INTO documents(client_id,filename,content,uploaded_by) VALUES(cid,'fixture.bin',decode('00ff7f','hex'),uid) RETURNING id INTO did;
 IF (SELECT encode(content,'hex') FROM documents WHERE id=did)<>'00ff7f' THEN RAISE EXCEPTION 'Binary bytes changed'; END IF;
 UPDATE documents SET scan_status='Clean' WHERE id=did;
 UPDATE documents SET content=decode('fe01','hex') WHERE id=did;
 IF (SELECT scan_status FROM documents WHERE id=did)<>'Pending' THEN RAISE EXCEPTION 'Replacement bytes must return to quarantine'; END IF;
 INSERT INTO document_requests(client_id,title) VALUES(cid,'Transcript') RETURNING id INTO rid;
 UPDATE document_requests SET status='Received' WHERE id=rid;
 IF (SELECT revision FROM document_requests WHERE id=rid)<>2 THEN RAISE EXCEPTION 'Checklist revision must advance once'; END IF;
 INSERT INTO invoices(client_id,description,currency,amount_minor,due_date,status) VALUES(cid,'Tuition','PHP',10000,'2020-01-01','Issued') RETURNING id INTO iid;
 INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_id,actor_name) VALUES(iid,4000,'2020-01-01','Cash',uid,'Test admin') RETURNING id INTO pid;
 IF (SELECT paid_minor FROM invoice_balances WHERE id=iid)<>4000 OR (SELECT balance_minor FROM invoice_balances WHERE id=iid)<>6000 THEN
  RAISE EXCEPTION 'Payment balance is incorrect';
 END IF;
 rejected:=false;
 BEGIN
  INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_name) VALUES(iid,7000,'2020-01-01','Cash','Test');
 EXCEPTION WHEN check_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Overpayment must be rejected'; END IF;
 rejected:=false;
 BEGIN UPDATE invoice_payments SET amount_minor=1 WHERE id=pid;
 EXCEPTION WHEN check_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Posted receipt must be immutable'; END IF;
 INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,reason,reverses_id,actor_name) VALUES(iid,-4000,'2020-01-02','Cash','Correction',pid,'Test');
 IF (SELECT paid_minor FROM invoice_balances WHERE id=iid)<>0 THEN RAISE EXCEPTION 'Reversal must restore balance'; END IF;
 INSERT INTO expenses(supplier,description,category,currency,amount_minor,expense_on,status,created_by,created_name)
 VALUES('School','Fee','Education','PHP',500,'2020-01-01','Approved',uid,'Test') RETURNING id INTO eid;
 INSERT INTO expense_entries(expense_id,amount_minor,posted_on,method,actor_id,actor_name) VALUES(eid,500,'2020-01-01','Cash',uid,'Test');
 IF (SELECT status FROM expenses WHERE id=eid)<>'Paid' THEN RAISE EXCEPTION 'Expense payment must update status'; END IF;
 INSERT INTO financial_periods(month,closed,reason,changed_by,changed_name) VALUES('2020-01',1,'Closed',uid,'Test');
 rejected:=false;
 BEGIN
  INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,actor_name) VALUES(iid,100,'2020-01-03','Cash','Test');
 EXCEPTION WHEN check_violation THEN rejected:=true; END;
 IF NOT rejected THEN RAISE EXCEPTION 'Closed financial period must block payments'; END IF;
 INSERT INTO sessions(token_hash,user_id,expires_at) VALUES('fixture-session',uid,'2099-01-01');
 UPDATE users SET password_hash='replacement-hash' WHERE id=uid;
 IF EXISTS(SELECT 1 FROM sessions WHERE user_id=uid) THEN RAISE EXCEPTION 'Password change must revoke sessions'; END IF;
 IF EXISTS(SELECT 1 FROM audit_log WHERE changes LIKE '%replacement-hash%') THEN RAISE EXCEPTION 'Audit must redact passwords'; END IF;
 PERFORM set_config('ecc.timezone','Asia/Manila',false);
 IF ecc_date('2026-10-21 20:00:00',business_offset())<>'2026-10-22' THEN RAISE EXCEPTION 'Manila business date is incorrect'; END IF;
 IF (SELECT ecc_json_group_array(value) FROM jsonb_array_elements('[]'::jsonb))<>'[]'::jsonb THEN RAISE EXCEPTION 'Empty lists must encode as arrays'; END IF;
END $acceptance$;
