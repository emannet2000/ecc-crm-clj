# Client application journey

ECC uses the existing Client → Case relationship. A case is presented as an application; proposals, contracts, meetings, invoices and payment instructions belong to that application.

Open a qualified lead and choose **Convert to Client**. Conversion retains the source lead and related history, moves documents and tasks, and opens the client workspace. Repeated conversion returns the existing client.

In the client workspace select an application in Scope, then use **Schedule Task**, **Schedule Zoom Meeting**, **Issue Proposal**, **Issue Contract**, **Create Invoice**, **Provide Payment Details**, **Record Payment**, **Upload Document** and **Update Application Status**. Existing role and financial privileges apply; invoice administration requires an administrator.

Tasks retain scheduled and due timestamps, assignment, priority and completion time. Schedule changes preserve previous and new values in the Activity Timeline. An incomplete task past its deadline is overdue. Notifications refresh every minute while signed in; unread overdue events produce an alert and remain in the notification center. Read and Dismiss affect the notification, not the task. Rescheduling creates a distinct deadline alert when that deadline passes.

Meeting times are entered in UTC. Staff can create meetings automatically with the Zoom adapter, or paste an existing HTTPS link, meeting ID and passcode. Meetings are internal by default; explicitly enable Client visible to publish an upcoming meeting to its client's portal. Automatic creation requires the configured Zoom provider worker.

Save a proposal or contract as a draft, select it and issue it. Drafts never appear in the portal. Issued terms are locked; corrections require another draft. Clients download a PDF and accept the terms, or reject a proposal. Acceptance records a timestamp and timeline entry and notifies the assigned consultant. Contracts may use portal consent or the configured DocuSign signature workflow. Accepted contracts can be completed by staff. Expired terms cannot be accepted.

Create an invoice draft in the application, then issue it. Payment instructions require an issued invoice in that same application and are internal until explicitly shared. Record receipts in Payments: exact minor-unit arithmetic updates the invoice balance. Posted receipts are retained; corrections use reversals. The portal shows payment requested, partially paid, overdue or paid from the ledger and due date. Clients can download their issued invoice PDFs and receipt PDFs; reversed receipts remain marked Reversed. Internal ledger notes, staff identity and financial audit data are excluded.

Use the existing Portal access tools to generate and privately share a one-use sign-in link. Client sessions are separate from staff sessions. Every portal download checks session ownership on the server. Approved documents must also pass malware scanning and an explicit document grant before download. The portal includes application progress, checklist and review feedback, uploads, shared files, published meetings, issued proposals/contracts, invoices, shared payment instructions and receipts. It excludes internal tasks, staff notes, audit data and other clients.

Before deploying, back up the database and apply pending migrations using the normal release procedure. SQLite migration 0017 and PostgreSQL migration 0004 add the journey records and timeline hooks. Build the API and themed frontend together and generate the verified release manifest. Do not run migrations against a live database without the deployment backup procedure.

Provider adapters are now implemented; see [provider integration and deployment instructions](../api/INTEGRATIONS.md). Account activation, sandbox smoke tests and live deployment remain dependent on the production environment. Provider status is polled using authenticated server requests; a browser redirect cannot confirm payment or a signature.

Validation: the JourneyTests regression suite covers proposal/contract lifecycles, exact totals, PDF output, portal ownership isolation, timed task history, overdue notification dismissal, meeting visibility, payment instruction visibility, invoice/receipt downloads and exclusion of internal receipt fields. Existing workflow, finance, authorization and frontend state suites remain part of the quality gate.
