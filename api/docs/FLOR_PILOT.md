# Flor's controlled pilot

Status: prepared; Flor's account, live deployment and acceptance results have not been verified here.

Use a small group of test records first. Keep the existing manual process as the official record throughout the pilot. Do not copy sensitive student documents into a staging system without authorizing that use. Agree on a pilot start date and who handles issues.

## Account and access

An administrator creates Flor's named account through Team, with Consultant access unless she needs administrative duties. Give her the required finance/document permissions explicitly. An email invitation needs working email delivery; otherwise use a temporary private password and change it at first use. Do not share the administrator account. Enroll MFA under Account security and verify recovery codes privately. Check that a Viewer cannot edit, and that restricted staff cannot see another officer's students or documents.

For the first operator account, the API provides `ecc-crm-api create-user-env`. Supply `ECC_USER_EMAIL`, `ECC_USER_NAME`, `ECC_USER_ROLE` and `ECC_USER_PASSWORD` privately in the service environment. The command does not overwrite an existing account, and the password is not a process argument. Remove these temporary variables after use. Create a separate named account for Flor using Team or the same operator command; her actual email has not been provided in this session.

## Trial checklist

For each item, record the date, person testing, result and any issue. These boxes are deliberately unchecked.

- [ ] Sign in as Flor and confirm her permitted screens. Sign out and confirm protected pages need authentication again.
- [ ] Add a test lead, search for it, update its details, and convert it to a student. Confirm notes/documents/tasks are retained.
- [ ] Add a separate student, check a duplicate warning, and verify the assigned officer.
- [ ] Create/update an application with school, program, intake and next deadline. Add and complete a milestone.
- [ ] Apply a tailored checklist. Upload a harmless test PDF and student photo. Confirm quarantine first, then a clean scan, then review/download. Test missing/expired requirements.
- [ ] Check Today against the full task/application/document lists. Create a due task, assign it and mark it Done.
- [ ] Log a call or manual WhatsApp/SMS conversation. Confirm that logging alone sends no message. Record messages sent manually so they are not repeated.
- [ ] Record a test invoice/payment, verify its balance, reverse an incorrect entry with a reason, and compare the corrected balance with the manual record.
- [ ] Open the same record in two tabs. Save one change and confirm the stale tab asks for conflict review rather than overwriting it.
- [ ] Interrupt a save with a connection failure. Confirm the draft remains, inspect whether the first save succeeded, then retry as appropriate. Check payment history before resubmitting money entries.
- [ ] Confirm the manual, how-to guide and FAQ are accessible from Help on desktop and mobile.
- [ ] Restart/redeploy the service and verify test records, photos and PDFs remain.
- [ ] Restore a backup to a separate database and compare student counts, document bytes and balances. Confirm an actual backup failure produces an alert.

## Daily comparison and issue log

Compare the pilot group's application stages, missing requirements, due tasks and payment totals with the manual records each day. Record an issue using: time, screen, action, expected result, actual result and whether a retry was attempted. Do not include passwords or copies of private documents in general issue reports.

Pause use of the affected function if information goes missing, another person's private record is visible, or balances differ. Keep the original evidence and report it to the administrator. During the pilot, corrections in the manual record remain the official result.

## Ending the pilot

Move to the app as the official operational record only after the checks above pass, the verified deployment is running, backup restoration is demonstrated, and Flor and the responsible administrator agree on the cutover. Document how existing manual records will be reconciled and how a problem will be handled after cutover. Automated tests alone do not approve that decision.
