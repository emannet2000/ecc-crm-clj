ALTER TABLE invoices ADD COLUMN issued_at TEXT;
UPDATE invoices SET issued_at=created_at WHERE status IN ('Issued','Paid');
CREATE TABLE invoice_payments (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 invoice_id INTEGER NOT NULL REFERENCES invoices(id),
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor<>0),
 paid_on TEXT,
 method TEXT NOT NULL,
 reference TEXT NOT NULL DEFAULT '',
 reason TEXT NOT NULL DEFAULT '',
 reverses_id INTEGER UNIQUE REFERENCES invoice_payments(id),
 legacy INTEGER NOT NULL DEFAULT 0,
 actor_id INTEGER,
 actor_name TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT(datetime('now'))
);
INSERT INTO invoice_payments(invoice_id,amount_minor,paid_on,method,reference,reason,legacy,actor_name)
 SELECT id,amount_minor,date(paid_at),'Legacy','Previously marked Paid','Opening payment imported from the previous manual Paid status',1,'Legacy import' FROM invoices WHERE status='Paid';
CREATE INDEX payments_invoice ON invoice_payments(invoice_id,id);
CREATE INDEX payments_date ON invoice_payments(paid_on);
CREATE VIEW invoice_balances AS
 SELECT i.*,coalesce((SELECT sum(p.amount_minor) FROM invoice_payments p WHERE p.invoice_id=i.id),0) AS paid_minor,
 i.amount_minor-coalesce((SELECT sum(p.amount_minor) FROM invoice_payments p WHERE p.invoice_id=i.id),0) AS balance_minor
 FROM invoices i;
CREATE TABLE expenses (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 supplier TEXT NOT NULL CHECK(length(trim(supplier)) BETWEEN 1 AND 255),
 description TEXT NOT NULL CHECK(length(trim(description)) BETWEEN 1 AND 1000),
 category TEXT NOT NULL CHECK(length(trim(category)) BETWEEN 1 AND 100),
 currency TEXT NOT NULL CHECK(currency IN ('PHP','USD','EUR','GBP','AUD','CAD','NZD')),
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor>0 AND amount_minor<=100000000000),
 expense_on TEXT NOT NULL,
 reference TEXT NOT NULL DEFAULT '',
 status TEXT NOT NULL DEFAULT 'Pending' CHECK(status IN ('Pending','Approved','Rejected','Paid','Reversed')),
 created_by INTEGER NOT NULL,
 created_name TEXT NOT NULL,
 reviewed_by INTEGER,
 review_note TEXT,
 revision INTEGER NOT NULL DEFAULT 1,
 created_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE TABLE expense_entries (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 expense_id INTEGER NOT NULL REFERENCES expenses(id),
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor<>0),
 posted_on TEXT NOT NULL,
 method TEXT NOT NULL,
 reference TEXT NOT NULL DEFAULT '',
 reason TEXT NOT NULL DEFAULT '',
 reverses_id INTEGER UNIQUE REFERENCES expense_entries(id),
 actor_id INTEGER NOT NULL,
 actor_name TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE UNIQUE INDEX expense_one_payment ON expense_entries(expense_id) WHERE reverses_id IS NULL;
CREATE INDEX expense_entries_date ON expense_entries(posted_on);
CREATE TABLE finance_audit (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 kind TEXT NOT NULL,
 record_id INTEGER NOT NULL,
 action TEXT NOT NULL,
 details TEXT NOT NULL,
 actor_id INTEGER,
 actor_name TEXT NOT NULL,
 created_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE TRIGGER payments_immutable_update BEFORE UPDATE ON invoice_payments BEGIN SELECT RAISE(ABORT,'Posted payments cannot be edited'); END;
CREATE TRIGGER payments_immutable_delete BEFORE DELETE ON invoice_payments BEGIN SELECT RAISE(ABORT,'Posted payments require a reversal'); END;
CREATE TRIGGER payment_validate BEFORE INSERT ON invoice_payments BEGIN
 SELECT CASE WHEN NEW.legacy<>0 OR NEW.paid_on IS NULL OR NEW.paid_on>date('now') THEN RAISE(ABORT,'Invalid payment date') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM invoices WHERE id=NEW.invoice_id AND status IN ('Issued','Paid')) THEN RAISE(ABORT,'Issue the invoice first') END;
 SELECT CASE WHEN NEW.reverses_id IS NULL AND NEW.amount_minor<0 THEN RAISE(ABORT,'Negative payments require a reversal') END;
 SELECT CASE WHEN NEW.reverses_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM invoice_payments p WHERE p.id=NEW.reverses_id AND p.invoice_id=NEW.invoice_id AND p.reverses_id IS NULL AND NEW.amount_minor=-p.amount_minor AND (p.paid_on IS NULL OR NEW.paid_on>=p.paid_on) AND length(trim(NEW.reason))>0) THEN RAISE(ABORT,'Invalid payment reversal') END;
 SELECT CASE WHEN (SELECT paid_minor+NEW.amount_minor FROM invoice_balances WHERE id=NEW.invoice_id) NOT BETWEEN 0 AND (SELECT amount_minor FROM invoices WHERE id=NEW.invoice_id) THEN RAISE(ABORT,'Payment exceeds the invoice balance') END;
END;
CREATE TRIGGER payment_posted AFTER INSERT ON invoice_payments BEGIN
 UPDATE invoices SET status=CASE WHEN (SELECT balance_minor FROM invoice_balances WHERE id=NEW.invoice_id)=0 THEN 'Paid' ELSE 'Issued' END,paid_at=CASE WHEN (SELECT balance_minor FROM invoice_balances WHERE id=NEW.invoice_id)=0 THEN datetime('now') ELSE NULL END,revision=revision+1 WHERE id=NEW.invoice_id;
 INSERT INTO finance_audit(kind,record_id,action,details,actor_id,actor_name) VALUES ('payment',NEW.id,CASE WHEN NEW.reverses_id IS NULL THEN 'receipt' ELSE 'reversal' END,json_object('invoiceId',NEW.invoice_id,'amountMinor',NEW.amount_minor,'paidOn',NEW.paid_on,'method',NEW.method,'reference',NEW.reference,'reason',NEW.reason,'reversesId',NEW.reverses_id),NEW.actor_id,NEW.actor_name);
 INSERT INTO work_history(client_id,actor_id,kind,note) SELECT client_id,NEW.actor_id,'payment',CASE WHEN NEW.reverses_id IS NULL THEN 'Payment recorded for invoice ' ELSE 'Payment reversed for invoice ' END||NEW.invoice_id||': '||printf('%.2f',NEW.amount_minor/100.0)||' '||currency||' · '||NEW.actor_name FROM invoices WHERE id=NEW.invoice_id;
END;
CREATE TRIGGER invoice_paid_requires_ledger BEFORE UPDATE OF status ON invoices BEGIN
 SELECT CASE WHEN NEW.status='Paid' AND (SELECT balance_minor FROM invoice_balances WHERE id=OLD.id)<>0 THEN RAISE(ABORT,'Record payments before marking Paid') END;
 SELECT CASE WHEN NEW.status IN ('Draft','Void') AND (SELECT paid_minor FROM invoice_balances WHERE id=OLD.id)<>0 THEN RAISE(ABORT,'Reverse payments before voiding') END;
END;
CREATE TRIGGER invoice_first_issue AFTER UPDATE OF status ON invoices WHEN NEW.status IN ('Issued','Paid') AND NEW.issued_at IS NULL BEGIN UPDATE invoices SET issued_at=datetime('now') WHERE id=NEW.id; END;
CREATE TRIGGER expense_fields_immutable BEFORE UPDATE OF supplier,description,category,currency,amount_minor,expense_on,reference,created_by,created_name ON expenses BEGIN SELECT RAISE(ABORT,'Expense details are retained; reject or reverse and create a correction'); END;
CREATE TRIGGER expense_no_delete BEFORE DELETE ON expenses BEGIN SELECT RAISE(ABORT,'Expenses are retained for audit'); END;
CREATE TRIGGER expense_entries_no_update BEFORE UPDATE ON expense_entries BEGIN SELECT RAISE(ABORT,'Posted expenses cannot be edited'); END;
CREATE TRIGGER expense_entries_no_delete BEFORE DELETE ON expense_entries BEGIN SELECT RAISE(ABORT,'Posted expenses require a reversal'); END;
CREATE TRIGGER expense_entry_validate BEFORE INSERT ON expense_entries BEGIN
 SELECT CASE WHEN NEW.posted_on>date('now') THEN RAISE(ABORT,'Future expense payment') END;
 SELECT CASE WHEN NEW.reverses_id IS NULL AND NOT EXISTS(SELECT 1 FROM expenses WHERE id=NEW.expense_id AND status='Approved' AND amount_minor=NEW.amount_minor) THEN RAISE(ABORT,'Approve the expense before recording payment') END;
 SELECT CASE WHEN NEW.reverses_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM expense_entries p JOIN expenses e ON e.id=p.expense_id WHERE p.id=NEW.reverses_id AND p.expense_id=NEW.expense_id AND p.reverses_id IS NULL AND NEW.amount_minor=-p.amount_minor AND NEW.posted_on>=p.posted_on AND e.status='Paid' AND length(trim(NEW.reason))>0) THEN RAISE(ABORT,'Invalid expense reversal') END;
END;
CREATE TRIGGER expense_entry_posted AFTER INSERT ON expense_entries BEGIN
 UPDATE expenses SET status=CASE WHEN NEW.reverses_id IS NULL THEN 'Paid' ELSE 'Reversed' END,revision=revision+1 WHERE id=NEW.expense_id;
 INSERT INTO finance_audit(kind,record_id,action,details,actor_id,actor_name) VALUES ('expense',NEW.expense_id,CASE WHEN NEW.reverses_id IS NULL THEN 'payment' ELSE 'reversal' END,json_object('entryId',NEW.id,'amountMinor',NEW.amount_minor,'postedOn',NEW.posted_on,'method',NEW.method,'reference',NEW.reference,'reason',NEW.reason,'reversesId',NEW.reverses_id),NEW.actor_id,NEW.actor_name);
END;
CREATE TRIGGER finance_audit_no_update BEFORE UPDATE ON finance_audit BEGIN SELECT RAISE(ABORT,'Financial audit is immutable'); END;
CREATE TRIGGER finance_audit_no_delete BEFORE DELETE ON finance_audit BEGIN SELECT RAISE(ABORT,'Financial audit is immutable'); END;
CREATE TABLE expense_submissions (
 actor_id INTEGER NOT NULL,
 submission_key TEXT NOT NULL,
 expense_id INTEGER NOT NULL REFERENCES expenses(id),
 PRIMARY KEY(actor_id,submission_key)
);
