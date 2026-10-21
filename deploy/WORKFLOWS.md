# Workspace workflows

Open **Workspace tools** in the header. Viewers can read accessible records and manage personal security and saved views. Reports, merging, invoicing and team access administration require an administrator.

| Page | How to use it |
|---|---|
| Edit and assign tasks | Select an existing task; edit title, description, deadline, priority, status, assignee and a 1–366 day recurrence. Create tasks from the task board or parent record. |
| Client and case history | Select a lead, client or case; add an attributed conversation, decision or next action. Client/case changes, emails and reviews also create history. Client detail combines this with original lead activity. |
| Document checklist and review | Create a Missing requirement, upload directly into a requirement or attach a previously uploaded file as a version. Approve or reject with feedback and optional expiry. Each new version requires review again. |
| Email reminders | Select a task; set reminder lead time and overdue escalation delay. The scheduler queues email to the assignee and escalates to active administrators. |
| Merge duplicates | Select two active leads or two active clients, preview child counts, type MERGE and confirm. Children and history move to the surviving record. |
| Management reports | Choose dates for lead cohorts, conversions and case completion/turnaround. Open/overdue tasks show current workload by staff member. |
| Search and saved views | Search contacts, phone numbers, tasks and cases. Save personal filters by record type, owner and overdue status; page through saved results. |
| Account security | Enroll a SHA-256 compatible authenticator; save eight single-use recovery codes immediately. Review/revoke sessions. Administrators can suspend/resume accounts and revoke their sessions. |
| Appointments | Schedule in UTC; overlapping scheduled appointments for one staff member are rejected. Download ICS for import into another calendar application. |
| Email a contact | Queue email to the address on an accessible record and retain its conversation history. |
| Client portal access | Create a one-use private link for 1–30 days. Explicitly grant approved document versions and revoke access when needed. |
| Invoices | Create drafts using exact minor currency units, issue/email them, and record payment manually. Issued amounts/client/description/currency are locked; void incorrect invoices and create replacements. |

## Conflicting edits and merging

Lead, client, user, case and task forms carry loaded versions. Checklist, reminder, appointment and invoice forms also use versions. A stale save returns HTTP 409 and retains the form. Review the original/draft/current comparison, accept the current version and save separately when ready. Original update endpoints return HTTP 428 for missing versions. Integrations must send `expectedRevision` from their last GET. Task board status updates include versions too.

Merge previews include both parent versions. Child writes invalidate those versions, preventing newly added notes/files from silently changing a confirmed preview. The source remains archived with original fields and audit entries; independent restoration is blocked. Source portal links/sessions are revoked to avoid expanding client access. In assigned-only mode, first give both records the same responsible staff member. Lead/client cross-type merging is not supported; use conversion instead.

## Documents and client portal

Versions retain their own bytes and cannot be deleted through the document API. Expired documents cannot be shared/downloaded through the portal. Clients see their case stages/deadlines, checklist and feedback, issued/paid invoices and explicitly granted latest approved files. They cannot see internal notes, other clients or unapproved files.

Portal tokens are hashed. Activation consumes a link once and sets a four-hour HttpOnly cookie; production cookies are Secure and SameSite=Strict. Activation tokens travel in fragments, which are cleared after activation. Revocation removes sessions immediately. Replacement versions or withdrawn approval remove older download access, including previously granted files.

Uploads are limited to 25 MB/file and 100 MB/20 files per link/day, plus a per-client request rate limit. Downloads are attachments. ClamAV scanning is required for approval/download; pending, infected and failed scans remain quarantined. See the [operations guide](OPERATIONS.md). Links are not automatically emailed: share them privately through an approved channel.

## Services and policy

Compose starts `scheduler` alongside `mail`. The scheduler runs every 15 seconds against the shared SQLite database. Locally, supervise `DATABASE_PATH=/path/to/app.sqlite3 python3 scripts/workflow_worker.py` and the existing SMTP mail worker. Unique claims prevent duplicate reminder queue entries and recurring tasks on retries; SMTP retains at-least-once delivery semantics.

Completed recurring tasks create one new Pending task. The next deadline is the later of the previous deadline and today, plus the interval. Assignment and reminder settings carry forward. Archived/converted source records are excluded. Reminders queue once per task/deadline/recipient, with separate overdue escalation.

Compose defaults `REQUIRE_ADMIN_MFA=true`. Administrators can sign in to enroll but cannot open records before enrollment. Enabling MFA revokes other sessions; disabling it revokes all sessions. An operator can run `ecc-crm-api reset-mfa EMAIL`, revoking sessions/recovery codes and requiring enrollment again under the policy. Keep recovery codes offline and database/backups private: server-readable authenticator secrets are not protected against a database operator. Audits record enable/disable and suspension flags without secrets.

## Integration scope and acceptance

Email uses SMTP; calendar integration exports ICS. Bidirectional Google/Microsoft calendar or mailbox synchronization requires a selected provider, OAuth application and credentials and is not included. Invoices support internal tracking, client visibility and email; they do not charge cards, calculate taxes or replace jurisdiction-specific accounting software.

Run [production acceptance](PRODUCTION.md) against a clean deployment. Repository tests cannot prove real SMTP delivery, browser interaction, clean vulnerability scans or an off-host restore. See [validation results](VALIDATION.md).

MFA follows [RFC 6238](https://www.rfc-editor.org/rfc/rfc6238), using SHA-256, six digits and 30-second steps; tests include its SHA-256 vectors. ICS follows [RFC 5545](https://www.rfc-editor.org/rfc/rfc5545) escaping and UTF-8 line folding.

For inline work, conflict recovery, scanning, email status, notifications and extended reports, read [Daily operations](OPERATIONS.md).
