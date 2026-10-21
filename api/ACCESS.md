# Access levels and privileges

Administrators manage access at **Account security → Team access**, also linked
from **Users → Manage access and privileges**. Select an account, set each control,
enter your current password in the security form, and choose **Save access and
privileges**. Selecting a different account discards the entered password.

Roles remain the upper limit:

- **Admin:** full access, user administration and management reports. Admin
  accounts cannot be restricted here; change their role in Users first. Existing
  protections prevent removing the last active administrator.
- **Consultant:** record access and actions allowed by their individual settings.
- **Viewer:** read-only record access. Only download and export privileges can be
  granted; write privileges require a role change first.

Record access can be **all** workspace records or **assigned** records. The
`ASSIGNED_ONLY=true` server setting always restricts non-admins to assigned records,
regardless of their individual selection. Existing ownership and task-assignment
checks still apply. Administrators continue to see all records.

Privileges restrict these operations:

| Privilege | Operations |
| --- | --- |
| edit | Create, edit, import, upload and other record changes |
| delete | Delete/archive records and bulk lead operations; also requires edit |
| download | Download document contents and profile photos |
| export | CSV exports and calendar downloads |
| email | Send email to contacts; also requires edit |
| portal | Create/revoke portal links and share approved documents; also requires edit |

Accounts retain password changes, MFA settings, personal saved searches,
notification preferences and their permitted read access when edit is disabled.
Client portal sessions keep their separate existing authorization rules.

Existing accounts keep the previous role permissions and server record scope until
an administrator saves individual settings. Access is checked from the database
on each authenticated request, so changes apply to existing sessions immediately.
They are audited and protected against conflicting updates.

Migration `0011_user_access.sql` adds the settings table. Normal startup or
`cabal run ecc-crm-api -- migrate` applies it. No existing credentials or account
roles change.

The admin operation is `POST /api/workspace/security/access`. It accepts `user`,
`expectedRevision` (zero before the first save), `password`, `accessLevel`
(`all`/`assigned`) and `edit`, `delete`, `download`, `export`, `email`, `portal`
(each `allowed`/`denied`). All privilege fields are required. Security workspace
team rows include these fields and the current `revision`. Successful saves
return 200; unauthorized callers receive 403, invalid role combinations 400,
and stale revisions 409.

## Sales and accounting privileges

Sales and accounting add `sales_view`, `finance_view`, `payments_record`,
`expenses_record` and `expenses_approve`. These default to denied for non-admins;
older API clients that omit them on access saves also leave them denied. Viewer
accounts may receive sales/financial viewing but cannot receive financial write
privileges. Financial writes use their dedicated privileges rather than CRM edit.
See [FINANCE.md](FINANCE.md) for workflows and financial visibility rules.

Financial controls also add `finance_periods` and `finance_reconcile`. Both require
financial view and company-wide record scope; they cannot override ASSIGNED_ONLY
for non-admins. Both default to denied and are forbidden for Viewer accounts.
