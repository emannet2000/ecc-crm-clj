-- Dates use the configured business zone; stored audit instants remain UTC.
DROP TRIGGER payment_validate;
CREATE TRIGGER payment_validate BEFORE INSERT ON invoice_payments BEGIN
 SELECT CASE WHEN NEW.legacy<>0 OR NEW.paid_on IS NULL OR NEW.paid_on>date('now',business_offset()) THEN RAISE(ABORT,'Invalid payment date') END;
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM invoices WHERE id=NEW.invoice_id AND status IN ('Issued','Paid')) THEN RAISE(ABORT,'Issue the invoice first') END;
 SELECT CASE WHEN NEW.reverses_id IS NULL AND NEW.amount_minor<0 THEN RAISE(ABORT,'Negative payments require a reversal') END;
 SELECT CASE WHEN NEW.reverses_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM invoice_payments p WHERE p.id=NEW.reverses_id AND p.invoice_id=NEW.invoice_id AND p.reverses_id IS NULL AND NEW.amount_minor=-p.amount_minor AND (p.paid_on IS NULL OR NEW.paid_on>=p.paid_on) AND length(trim(NEW.reason))>0) THEN RAISE(ABORT,'Invalid payment reversal') END;
 SELECT CASE WHEN (SELECT paid_minor+NEW.amount_minor FROM invoice_balances WHERE id=NEW.invoice_id) NOT BETWEEN 0 AND (SELECT amount_minor FROM invoices WHERE id=NEW.invoice_id) THEN RAISE(ABORT,'Payment exceeds the invoice balance') END;
END;
DROP TRIGGER expense_entry_validate;
CREATE TRIGGER expense_entry_validate BEFORE INSERT ON expense_entries BEGIN
 SELECT CASE WHEN NEW.posted_on>date('now',business_offset()) THEN RAISE(ABORT,'Future expense payment') END;
 SELECT CASE WHEN NEW.reverses_id IS NULL AND NOT EXISTS(SELECT 1 FROM expenses WHERE id=NEW.expense_id AND status='Approved' AND amount_minor=NEW.amount_minor) THEN RAISE(ABORT,'Approve the expense before recording payment') END;
 SELECT CASE WHEN NEW.reverses_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM expense_entries p JOIN expenses e ON e.id=p.expense_id WHERE p.id=NEW.reverses_id AND p.expense_id=NEW.expense_id AND p.reverses_id IS NULL AND NEW.amount_minor=-p.amount_minor AND NEW.posted_on>=p.posted_on AND e.status='Paid' AND length(trim(NEW.reason))>0) THEN RAISE(ABORT,'Invalid expense reversal') END;
END;

DROP TRIGGER period_invoice_issue_lock;
CREATE TRIGGER period_invoice_issue_lock BEFORE UPDATE OF status ON invoices WHEN OLD.status='Draft' AND NEW.status IN ('Issued','Paid') AND EXISTS(SELECT 1 FROM financial_periods WHERE month=strftime('%Y-%m','now',business_offset()) AND closed=1) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;

DROP TRIGGER period_invoice_void_lock;
CREATE TRIGGER period_invoice_void_lock BEFORE UPDATE OF status ON invoices WHEN NEW.status='Void' AND OLD.status<>'Void' AND EXISTS(SELECT 1 FROM financial_periods WHERE month=strftime('%Y-%m',OLD.issued_at,business_offset()) AND closed=1) BEGIN SELECT RAISE(ABORT,'Reopen the issue month before voiding this invoice'); END;

DROP TRIGGER period_invoice_fields_lock;
CREATE TRIGGER period_invoice_fields_lock BEFORE UPDATE OF amount_minor,currency,description,due_date ON invoices WHEN EXISTS(SELECT 1 FROM financial_periods WHERE month=strftime('%Y-%m',OLD.issued_at,business_offset()) AND closed=1) AND (NEW.amount_minor<>OLD.amount_minor OR NEW.currency<>OLD.currency OR NEW.description<>OLD.description OR NEW.due_date<>OLD.due_date) BEGIN SELECT RAISE(ABORT,'Financial month is closed'); END;
