# Sales reports and basic accounting

Open **More tools → Sales report** or **Payments and accounting**. The accounting
tabs provide invoices (administrators), payments, balances, expenses, receipts and
expenses, and the financial audit trail. Amounts use integer minor units with two
decimal places. PHP, USD, EUR, GBP, AUD, CAD and NZD remain separate throughout;
there is no currency conversion or combined multi-currency total.

## Sales

Sales reports show lead cohorts grouped by source and current consultant,
conversion counts/rates, and pipeline stages. Date filters apply to lead creation
for cohorts, invoice issuance for invoiced amounts, and payment posting for net
receipts. A conversion means the lead has a converted client. Merged duplicates
are excluded; archived leads remain in the cohort and unconverted archived leads
appear in an Archived stage. Current assignment determines staff grouping and
record visibility. Unpaid invoices are never counted as collected receipts.

Money tables distinguish invoiced amounts, net receipts, current outstanding
balances, current overdue balances, and legacy payments without a known date.
Outstanding and overdue balances are current figures, even when a report's date
range is historical. Date boundaries are inclusive; system timestamps use UTC.
Reports default to all dates. Reports exceeding 10,000 groups return an error
instead of silently truncating them.

## Invoices and receipts

1. An administrator creates a Draft invoice and issues it in **Invoices**. Amount,
   client, description and currency lock after issuance.
2. In **Payments**, select the invoice, enter a full or partial amount, posting
   date, method and optional reference, and confirm **Record payment**.
3. The remaining balance and Paid status derive from the immutable receipt ledger.
   Payments cannot exceed the outstanding amount. Invalid decimal amounts and
   future posting dates are rejected. This feature records payments made outside
   the CRM; it does not charge cards or move money.
4. To correct a receipt, select its invoice, choose the receipt, enter a reversal
   date and reason, and confirm **Reverse selected receipt**. The original remains
   intact and a matching negative entry reopens the invoice balance. Each receipt
   can be reversed once; reversal dates cannot precede the original payment.
5. An invoice with net payments cannot be voided. Reverse its receipts first, then
   void it and issue a replacement if necessary. Corrections use full receipt
   reversals; record a corrected receipt afterwards if required.

Invoice revisions reject simultaneous or retried submissions using stale data.
Ledger constraints also prevent overpayment, duplicate reversals, edits and deletes.
Balances and history remain accessible when a client is archived. Merging clients
moves invoices to the surviving client without rewriting their receipt entries.
The client portal and invoice email include net payments and outstanding balances.

The balance list provides an **Overdue accounts** filter. An amount is overdue
when its invoice due date has passed and its balance is positive. Invoice overview histories
show the latest 100 entries. The separate searchable Payment history view paginates
all accessible receipts without the former 500-choice cap. Payments CSV exports
contain individual ledger entries, including older entries and reversals.

## Expenses

Submit supplier/payee, description, category, currency, amount, expense date and
optional supplier reference in **Expenses**. Expense details are retained; reject
an incorrect submission or reverse a posted payment and submit a correction.

Select a Pending expense to approve or reject it. Rejection requires an explanation.
A non-admin approver cannot approve their own expense. Administrators may approve
their own submissions. Only Approved expenses can receive a payment entry. Recording
an expense payment requires its posting date, method and optional payment reference.
An approver can reverse a Paid expense with a date and reason, preserving both
entries. Reversed expenses cannot be paid again; submit a corrected expense.

Submission keys prevent duplicate creation on request retries. Revisions protect
approval/payment transitions, and a unique ledger constraint permits only one
original payment per expense. Approval, rejection, payment and reversal are audited.

The receipts and expenses report subtracts paid expense entries from net client
receipts in the period. Pending/Approved-but-unpaid expenses do not count as cash
outflow. Reversals are dated correcting entries. This report is cash activity,
not a profit statement, tax calculation, bank reconciliation or double-entry ledger.

## Privileges and visibility

Administrators have full access. New privileges default to denied for other users,
including existing accounts, until assigned in **Account security → Team access**.
Existing CRM privileges and roles are preserved.

| Privilege | Grants |
| --- | --- |
| sales_view | Read sales cohorts and currency summaries |
| finance_view | Read payment history, balances, visible expenses, cash activity and financial audit |
| payments_record | Record/reverse client receipts; also requires finance_view |
| expenses_record | Submit expenses and pay approved visible expenses; also requires finance_view |
| expenses_approve | Read all company expenses, approve/reject them and reverse their payments; also requires finance_view |
| export | CSV exports, in addition to the relevant report's view privilege |

Financial write privileges do not require the general CRM edit privilege. Viewer
accounts remain read-only even if a previous role had financial write grants.
Client financial records follow current assignment scope, including the server's
ASSIGNED_ONLY setting. Expense submitters see their own expenses; company approvers
see all expenses. Financial audit and exports use the same visibility checks.
A cash activity report for a non-approver includes only their visible expenses.

All new sections export CSV. List exports are limited to 10,000 entries; larger
results return an error so the user can narrow the search. CSV cells use the
existing spreadsheet-formula protection. Financial audit entries preserve the
actor's name even after user removal. Existing invoice creation/change audit
remains available in the main administration audit trail.

## Migration and compatibility

`0012_finance.sql` adds the payment ledger, balance view, expense workflow and ledger,
financial audit, submission keys and first-issue timestamps. Startup applies the
migration, or run `cabal run ecc-crm-api -- migrate`. The application must be restarted
with the newly built binary/frontend; no live database is modified by the tests.

Existing Paid invoices receive labelled Legacy opening payment entries. Known
paid_at dates are retained. Unknown payment dates stay NULL and appear under
**Legacy payments with unknown dates**, never in a fabricated cash period. Old
Issued/Paid invoice issuance dates use their creation timestamp because the old
schema did not record issuance separately. New invoices retain their first actual
issuance timestamp. Review historical inputs before using reports externally.

## Validation

The Haskell regression suite exercises migration of dated/undated legacy payments,
partial/full receipts, precision and overpayment rejection, receipt/expense reversals,
immutable ledger/audit data, expense approval and self-approval rules, duplicate
submissions, currency separation, sales conversion cohorts, archived balances,
scoped reads/exports and independent privileges. Frontend state tests exercise
payment revisions, required posting fields, submission-key retries and date filters.

## Financial controls added in migration 0013

**Payment history** is a separate searchable, paginated view (50 receipts per page),
including receipts older than the prior 500-choice cap. Invoice links filter the
history to that invoice. Select a specific unreversed receipt there to reverse it;
receipts and reversal acknowledgements can be printed or saved as PDF. Duplicate
references are flagged in history, and recording a repeated reference returns a
warning. Matching amounts/references still require operator verification.

**Period closing** requires `finance_view` and `finance_periods` with company-wide
record scope. Only completed months can be closed. Imported bank entries in the
month must first be matched or explicitly excluded. Closing records a currency
snapshot; closing and reopening require a reason and are audited. Closed months
reject new/backdated receipts, expense submissions/payments, bank imports and
reconciliation changes. Invoice issuance in a closed month, voiding an invoice from
its closed issue month, and changing issued financial fields in a closed month are
also blocked in database triggers. Current balances can still reflect payments
posted in later open months. Reopen the original month to correct locked records.

**Bank reconciliation** requires `finance_view` and `finance_reconcile`, also with
company-wide scope. Paste a CSV with `transactionId,date,amount,reference,description`
columns (1–1000 rows, at most 20,000 characters). Use positive amounts for credits
and negative amounts for debits. Transaction IDs must be stable and unique within
an account/currency. Identical imports are skipped; conflicting reused IDs and
invalid rows are rejected before any statement rows are written.

Select a bank entry to search/paginate candidate receipts and expense payments with
exact matching currency and signed amount. Client receipts match credits; expense
payments match debits. Review dates and references and enter a reason before
confirming. Entries outside CRM activity can be explicitly excluded with a reason.
Each ledger entry and bank line can have at most one match. Unmatching is audited
and prohibited in closed months. A matched payment must be unmatched before it can
be reversed. Matching does not create, charge or alter a payment amount.

**Expense supporting documents** accept PDF/PNG/JPEG files up to 10 MB each, with a
20-file cap per expense. Uploads are append-only evidence, use expense revisions
to prevent duplicate retries, and require `expenses_record` and expense visibility.
New files are quarantined; the updated `scripts/scan_worker.py` scans both normal
documents and financial files. Downloads require financial view, download privilege,
expense visibility and a Clean verdict. Failed scans can be retried by authorized
company expense approvers. Adding evidence does not change a closed month's amounts.

Printable invoice/payment endpoints require `finance_view`, export privilege and
invoice visibility. All user-controlled text is HTML-escaped. Print documents are
CRM records, not a payment operation or a claim of tax-document certification.

Production scheduling, off-site storage, worker deployment, monitoring and browser
verification are described in [OPERATIONS.md](OPERATIONS.md).

Business dates use the shared CRM timezone (Philippine time by default). See
[CLOCK.md](CLOCK.md) for the live clock, UTC audit instants, configuration and
migration `0014_business_clock.sql`.
