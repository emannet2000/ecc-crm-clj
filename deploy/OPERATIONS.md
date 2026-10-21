# Daily operations improvements

## Client and case work

Each client page now contains **Work on this client or case**. Choose the whole client or a particular case, then switch between task editing, conversation history and document checklists. The panels use server-side permissions, filtering and pagination. Converted lead tasks remain visible. Create tasks directly in the chosen scope, edit assignment/deadlines/priority/recurrence, or add an attributed case conversation without leaving the client page.

Checklist uploads attach directly to a requirement using the revision displayed when the page loaded. A stale upload is rejected before a new version is saved. Whole-client views preserve an item's original case association. Required/outstanding/review/expiry counts cover the selected client/case, beyond the current page. Review queue, expiring and outstanding filters are available both inline and in Workspace tools.

## Conflict recovery

A conflicting save keeps the draft and opens a comparison showing the original, draft and current values for changed fields. Task/checklist/reminder fields can adopt individual current values. Lead/client/case/account forms show the comparison and keep their editable draft. Accepting a comparison adopts the current version number and returns to the form; it never submits automatically. Review the draft and save separately. If a colleague writes again meanwhile, another comparison is required.

Related task/file/history activity can change a parent version without changing its contact fields. The comparison explains this when there are no changed fields. Field validation and scan errors appear in the work panel. Loading responses are bound to the active record, scope and generation, and are discarded after navigation/logout.

## Quarantine and malware scanning

Migration `0006_operations.sql` quarantines **all existing and future documents**, including legacy files that previously downloaded without scanning. Files cannot be downloaded by staff or portal clients, approved, or shared until their current bytes have a successful scan. Older versions retain their own scan verdicts. Content changes reset quarantine and invalidate in-flight scan results.

Compose now starts `clamav` and `scanner`. ClamAV downloads initial signatures and runs its updater; the scanner starts after its health check succeeds. It uses the official [ClamAV INSTREAM protocol](https://docs.clamav.net/manual/Usage/ClamdProtocol.html), scans outside database write transactions, and commits results only for its active lease. Archive limits/encrypted archives are configured to alert. Keep the daemon's TCP port private; no host port is published. Persist signatures in `clamav_signatures` and permit signature-update network access.

For local operation, supervise `DATABASE_PATH=/path/to/app.sqlite3 CLAMD_HOST=127.0.0.1 CLAMD_PORT=3310 python3 scripts/scan_worker.py` against a configured ClamAV daemon. Keep it on a private interface/network. Compose builds the antivirus image from the pinned Python base and distribution packages and adds it to release manifests and vulnerability scanning.

Scanner outages/errors leave files blocked. Errors retry after five minutes, up to five attempts; administrators can select a checklist item and **Retry failed scan for selected item** after resolving the outage. An infected result rejects the latest requirement version and notifies its responsible staff member. Infected files require a replacement; there is no UI override to mark them clean. A scanner cannot guarantee that a clean file is harmless.

Before enabling uploads in production, verify daemon startup/signature updates, a clean sample, an antivirus test sample, outage behavior, staff/portal download blocking and recovery. Mocked protocol tests prove framing and failure handling, not real antivirus operation. Allow for daemon resources in deployment load testing. Pending/error/infected states are visible beside each version and in checklist rows.

## Email delivery visibility

**Workspace tools → Email delivery** shows queued, sending, retry-scheduled, failed and accepted-by-SMTP messages. Administrators see the queue; other staff see messages they authored for records they can still access. Bodies and account/reset tokens are not exposed. The mail worker retains successful queue rows for 30 days and removes successful message bodies.

SMTP acceptance is not proof of inbox delivery, reading or absence of later bounces. Provider delivery/bounce webhooks are not configured. A failure uses exponential backoff (starting at two minutes, capped at one hour) for five automatic attempts. Only administrators can retry an exhausted, unclaimed failure, at most three times and at least 15 minutes apart. Retries reuse the queue row and are audited. A retry may resend mail accepted before a connection failed; SMTP remains at-least-once. Successful sends cannot be retried through this action.

## Notifications and preferences

**Notification centre** combines task assignments, upcoming task/case deadlines, rejected/expiring documents and overdue escalation. Open the related record, select a notification and mark it read. Events have durable unique keys so repeated scheduler runs do not create copies. Read state and preferences belong to the signed-in user. Record access is checked again when listing notifications, so revoked/archived records disappear.

Preferences control assignment/deadline/document/escalation categories and task reminder emails. Account invitation/recovery messages are mandatory and unaffected. Viewers can manage their own preferences/read state. Disabling a category hides existing notices without deleting history; re-enabling shows them again. Disabling email prevents future task/escalation queue entries; it does not cancel messages already queued.

## Reports

Management summary reports now export CSV. Additional administrator reports cover open-case ageing, overdue days, bottlenecks by stage, and historical workload by staff. Date filters apply to case creation for ageing/bottlenecks and snapshot dates for trends. Bottleneck time uses the most recent recorded stage transition; legacy cases without history use creation time. This limitation appears in the report description.

The scheduler captures the current day's workload every cycle; past days retain their last observation. Trend data begins at rollout and cannot reconstruct missing prior days or scheduler outages. Staff names and snapshots survive account deletion. Exports cap detailed reports at 10,000 rows; narrow the date range for larger datasets. CSV cells protect against spreadsheet formula injection. Lead cohort conversions and completion-date calculations remain available in the summary.

## Keyboard and mobile behavior

Inline controls have labels, scope controls announce selected sections, errors use alert regions, and conflict comparisons have captions/row/column headers. Focus outlines remain visible on inputs, buttons and links. The focus trap selects the topmost dialog, makes earlier dialogs inert, supports Escape on dismissible dialogs and returns focus on close. Touch controls use larger targets; comparisons scroll within their panel and menus have bounded mobile height. Reduced-motion behavior is retained.

Run the browser suite on a normal runner to verify keyboard, touch/responsive layout, contrast and screen-reader behavior before claiming accessibility conformance. This environment cannot start Chromium, so no such conformance claim is made.
