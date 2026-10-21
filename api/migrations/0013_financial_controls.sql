CREATE INDEX account_tokens_user_expiry ON account_tokens(user_id,expires_at);
CREATE TABLE financial_periods (
 month TEXT PRIMARY KEY CHECK(length(month)=7),
 closed INTEGER NOT NULL CHECK(closed IN (0,1)),
 revision INTEGER NOT NULL DEFAULT 1,
 reason TEXT NOT NULL,
 snapshot TEXT NOT NULL DEFAULT '[]' CHECK(json_valid(snapshot)),
 changed_by INTEGER NOT NULL,
 changed_name TEXT NOT NULL,
 changed_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE TABLE bank_statements (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 account TEXT NOT NULL,
 currency TEXT NOT NULL,
 import_hash TEXT NOT NULL UNIQUE,
 imported_by INTEGER NOT NULL,
 imported_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE TABLE bank_lines (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 statement_id INTEGER NOT NULL REFERENCES bank_statements(id),
 account TEXT NOT NULL,
 currency TEXT NOT NULL,
 transaction_id TEXT NOT NULL,
 posted_on TEXT NOT NULL,
 amount_minor INTEGER NOT NULL CHECK(typeof(amount_minor)='integer' AND amount_minor<>0),
 reference TEXT NOT NULL,
 description TEXT NOT NULL,
 revision INTEGER NOT NULL DEFAULT 1,
 UNIQUE(account,currency,transaction_id)
);
CREATE TABLE bank_matches (
 bank_line_id INTEGER PRIMARY KEY REFERENCES bank_lines(id),
 payment_id INTEGER UNIQUE REFERENCES invoice_payments(id),
 expense_entry_id INTEGER UNIQUE REFERENCES expense_entries(id),
 ignored INTEGER NOT NULL DEFAULT 0,
 reason TEXT NOT NULL,
 actor_id INTEGER NOT NULL,
 actor_name TEXT NOT NULL,
 matched_at TEXT NOT NULL DEFAULT(datetime('now')),
 CHECK((payment_id IS NOT NULL)+(expense_entry_id IS NOT NULL)+ignored=1)
);
CREATE TABLE financial_files (
 id INTEGER PRIMARY KEY AUTOINCREMENT,
 expense_id INTEGER NOT NULL REFERENCES expenses(id),
 filename TEXT NOT NULL,
 mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
 content BLOB NOT NULL,
 size INTEGER NOT NULL CHECK(size>0 AND size<=10485760),
 uploaded_by INTEGER NOT NULL,
 uploaded_name TEXT NOT NULL,
 scan_status TEXT NOT NULL DEFAULT 'Pending' CHECK(scan_status IN ('Pending','Scanning','Clean','Infected','Error')),
 scan_attempts INTEGER NOT NULL DEFAULT 0,
 scan_lease TEXT,
 scan_until TEXT,
 scan_detail TEXT,
 scanned_at TEXT,
 created_at TEXT NOT NULL DEFAULT(datetime('now'))
);
CREATE INDEX financial_files_expense ON financial_files(expense_id,id);
CREATE INDEX financial_files_scanning ON financial_files(scan_status,scan_until);
CREATE INDEX expenses_creator ON expenses(created_by,id);
CREATE INDEX expense_entries_expense ON expense_entries(expense_id,id);
CREATE INDEX bank_lines_posted ON bank_lines(posted_on,id);
CREATE TRIGGER period_payment_lock BEFORE INSERT ON invoice_payments WHEN EXISTS(SELECT 1 FROM financial_periods WHERE month=substr(NEW.paid_on,1,7) AND closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER period_expense_entry_lock BEFORE INSERT ON expense_entries WHEN EXISTS(SELECT 1 FROM financial_periods WHERE month=substr(NEW.posted_on,1,7) AND closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER period_expense_lock BEFORE INSERT ON expenses WHEN EXISTS(SELECT 1 FROM financial_periods WHERE month=substr(NEW.expense_on,1,7) AND closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER period_invoice_issue_lock BEFORE UPDATE OF status ON invoices WHEN OLD.status='Draft' AND NEW.status IN ('Issued','Paid') AND EXISTS(SELECT 1 FROM financial_periods WHERE month=strftime('%Y-%m','now') AND closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER period_invoice_void_lock BEFORE UPDATE OF status ON invoices WHEN NEW.status='Void' AND OLD.status<>'Void' AND EXISTS(SELECT 1 FROM financial_periods WHERE month=substr(OLD.issued_at,1,7) AND closed=1) BEGIN SELECT RAISE(ABORT,'Reopen the issue month before voiding this invoice'); END;
CREATE TRIGGER period_invoice_fields_lock BEFORE UPDATE OF amount_minor,currency,description,due_date ON invoices WHEN EXISTS(SELECT 1 FROM financial_periods WHERE month=substr(OLD.issued_at,1,7) AND closed=1) AND (NEW.amount_minor<>OLD.amount_minor OR NEW.currency<>OLD.currency OR NEW.description<>OLD.description OR NEW.due_date<>OLD.due_date) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER bank_match_period_insert BEFORE INSERT ON bank_matches WHEN EXISTS(SELECT 1 FROM bank_lines b JOIN financial_periods f ON f.month=substr(b.posted_on,1,7) WHERE b.id=NEW.bank_line_id AND f.closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER bank_match_period_delete BEFORE DELETE ON bank_matches WHEN EXISTS(SELECT 1 FROM bank_lines b JOIN financial_periods f ON f.month=substr(b.posted_on,1,7) WHERE b.id=OLD.bank_line_id AND f.closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER bank_line_period_insert BEFORE INSERT ON bank_lines WHEN EXISTS(SELECT 1 FROM financial_periods f WHERE f.month=substr(NEW.posted_on,1,7) AND f.closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
CREATE TRIGGER bank_match_validate BEFORE INSERT ON bank_matches BEGIN
 SELECT CASE WHEN NEW.payment_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM bank_lines b JOIN invoice_payments p ON p.id=NEW.payment_id JOIN invoices i ON i.id=p.invoice_id WHERE b.id=NEW.bank_line_id AND b.currency=i.currency AND b.amount_minor=p.amount_minor AND NOT EXISTS(SELECT 1 FROM invoice_payments r WHERE r.reverses_id=p.id)) THEN RAISE(ABORT,'Bank payment amount or currency mismatch') END;
 SELECT CASE WHEN NEW.expense_entry_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM bank_lines b JOIN expense_entries p ON p.id=NEW.expense_entry_id JOIN expenses e ON e.id=p.expense_id WHERE b.id=NEW.bank_line_id AND b.currency=e.currency AND b.amount_minor=-p.amount_minor AND NOT EXISTS(SELECT 1 FROM expense_entries r WHERE r.reverses_id=p.id)) THEN RAISE(ABORT,'Bank expense amount or currency mismatch') END;
END;
CREATE TRIGGER matched_payment_reverse_lock BEFORE INSERT ON invoice_payments WHEN NEW.reverses_id IS NOT NULL AND EXISTS(SELECT 1 FROM bank_matches WHERE payment_id=NEW.reverses_id) BEGIN SELECT RAISE(ABORT,'Unmatch the bank entry before reversing this receipt'); END;
CREATE TRIGGER matched_expense_reverse_lock BEFORE INSERT ON expense_entries WHEN NEW.reverses_id IS NOT NULL AND EXISTS(SELECT 1 FROM bank_matches WHERE expense_entry_id=NEW.reverses_id) BEGIN SELECT RAISE(ABORT,'Unmatch the bank entry before reversing this expense payment'); END;
CREATE TRIGGER bank_lines_immutable BEFORE UPDATE OF statement_id,account,currency,transaction_id,posted_on,amount_minor,reference,description ON bank_lines BEGIN SELECT RAISE(ABORT,'Imported bank transactions are immutable'); END;
CREATE TRIGGER bank_lines_no_delete BEFORE DELETE ON bank_lines BEGIN SELECT RAISE(ABORT,'Imported bank transactions are retained'); END;
CREATE TRIGGER bank_matches_no_update BEFORE UPDATE ON bank_matches BEGIN SELECT RAISE(ABORT,'Unmatch and create a new reconciliation'); END;
CREATE TRIGGER financial_files_content_immutable BEFORE UPDATE OF expense_id,filename,mime_type,content,size,uploaded_by,uploaded_name ON financial_files BEGIN SELECT RAISE(ABORT,'Financial evidence is retained'); END;
CREATE TRIGGER financial_files_no_delete BEFORE DELETE ON financial_files BEGIN SELECT RAISE(ABORT,'Financial evidence is retained'); END;
