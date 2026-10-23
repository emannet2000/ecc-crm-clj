# ECC client application specification: acceptance review

Review date: 23 October 2026. Scope: all 23 numbered sections, the three concurrent workflows, and the additional provider/deployment request. This is a code and local-test acceptance review, **not production sign-off**.

**Implemented** means the behavior is present in the source and has a stated verification path. **Partial** means specific requested behavior is missing or differs. **Operationally pending** means code exists but account/configuration/deployment evidence is unavailable. No blanket claim of full specification completion is made.

## Verification evidence

- `test/JourneyTests.hs`: actual WAI/SQLite API requests cover commercial lifecycle, totals, timed tasks/history, overdue dismissal, meeting visibility, payment instructions, invoice/receipt PDFs, portal ownership and unauthenticated access. New checks cover provider enablement, optimistic revisions, request duplication, application scope, durable queue records, electronic-signature acceptance restrictions and signed-document ownership/scan gating.
- `scripts/test_integrations.py`: provider protocol fixtures and real SQLite migrations/transactions cover OAuth request shape, Zoom creation and ambiguous outcomes, exact Checkout minor units and idempotency, payment identity/amount/currency checks, duplicate receipt prevention, manual-payment conflicts, Google outbound privacy and inbound conflicts, signature sending, signed bytes and scan state, lease ownership and immutable provider events. These fixtures do **not** call real providers.
- `scripts/test_provider_deployment.py`: read-only planning, unverified-release rejection, service command validation, backup/stop/migrate/start order and failed-deployment handling. These tests do **not** migrate production.
- `test/FeatureTests.hs`, `ClientApplicationTests.hs`, `FinanceTests.hs`, `AccessTests.hs`, `ControlsTests.hs`, `GeneratedTests.hs`: existing conversion, permissions, case/application, finance and consistency checks.
- `test/frontend-state.test.cjs`: real compiled Elm update behavior, drafts, stale responses, mutation conflicts and notification refresh.
- `test/browser-acceptance.test.cjs`: browser workflow and mobile portal fixture coverage. Fixtures cover rendering; backend authorization evidence comes from WAI tests.
- PostgreSQL has separate migration and `postgres-regression` coverage; its run result must be recorded separately. Neither SQLite fixtures nor a passing compiler imply a PostgreSQL or production run passed.

## Recorded local validation

The complete `scripts/check.sh` release gate passed on the disposable local PostgreSQL 18 instance and temporary SQLite databases. It built the API and optimized frontend, ran SQLite/PostgreSQL API regression suites, 1,000 generated Haskell checks, 1,103 Python checks, 16 provider-worker checks on PostgreSQL, frontend/report/PWA checks, PostgreSQL worker/recovery checks, real HTTP bootstrap/startup checks and browser/mobile/finance journeys. The final browser phase passed 24 checks. The gate sealed `web/dist/release.json` for the exact local binary, assets and migrations.

This does not establish live Zoom/Google/Stripe/DocuSign account readiness, production deployment, provider legal/account approval, DNS/TLS/SMTP delivery or built-container vulnerability scan results. Those require the external deployment environment and account smoke tests. The CI workflow includes scanning the new integrations worker image.

## 1–3. Objective, lead conversion and client/application workspace

| Requirement | Assessment | Evidence / precise limitation |
|---|---|---|
| Connected Lead → Client → Application | Implemented | `DB.convertToClient`, existing cases reused as applications |
| Rename Convert to Student | Implemented | Lead action reads Convert to Client |
| Prevent duplicate conversion / retry safely | Implemented | Existing converted client returned transactionally; regression/concurrency tests |
| Copy name, email, phone, service, destination and assigned staff | Implemented | Conversion creates client and initial case with these fields |
| Copy address | Partial | Current lead/client schema has no dedicated address field |
| Preserve lead notes and history | Implemented with representation difference | Source lead retained; original history attached/preserved rather than every source field copied to a second client column |
| Link client to source lead, set Converted, record actor/time, redirect | Implemented | Converted source relationship, conversion event and frontend navigation |
| Exact proposed lead status vocabulary | Partial | Existing CRM status vocabulary is retained; not every proposed label is normalized |
| Client ID, name, contact, country/service, consultant, creation date | Implemented | Client details plus scoped application/case fields |
| Separate application number/type/destination/stage/target date | Implemented | Application identifiers, category, destination, stage, next deadline |
| Current status separately from current stage | Partial | Primary application workflow uses stage; no independent general-purpose application status axis |
| Client address / application-specific assigned consultant | Partial | Address missing; consultant primarily belongs to client rather than a separate assignment per application |
| Documents and tasks in the same workspace | Implemented | Scoped workspace panels and related record authorization |
| Task title, description, assignee, schedule, due time/date, priority, status, completion time | Implemented | Timed-task fields and completion timestamp |
| Task notes separate from description/history | Partial | Description and activity history serve this purpose; no dedicated notes field |
| Pending → In Progress → Completed | Implemented with label difference | Stored completion value is Done |
| Cancelled task state | Partial | Existing task constraint supports Pending/In Progress/Done only |
| Derived Overdue | Implemented | Due timestamp preferred; due date fallback; completed tasks excluded |

## 4–6. Activity history, task history and meetings

| Requirement | Assessment | Evidence / precise limitation |
|---|---|---|
| Chronological unified client/application timeline | Implemented | Work history scoped to client and optional application |
| Automatic conversion, case stage, task, meeting, commercial and payment events | Implemented | Triggers/application commands plus provider reconciliation |
| Scheduled task with assignment, schedule and current status | Implemented | Task-created event and task panel |
| Preserve previous/new dates on rescheduling | Implemented | Database task-reschedule hooks; JourneyTests |
| Completion actor and timestamp | Implemented | Completion history and completed_at |
| Preserve all original task state transitions as named immutable events | Partial | Important events retained; not every status/assignment change has its own immutable typed event |
| `task.overdue` timeline event | Partial | Persistent overdue notification exists; overdue itself is not a dedicated timeline event |
| Staff-created Zoom URL, ID, passcode, visibility | Implemented | Appointment fields; HTTPS validation |
| Meeting title, client, start/end, staff, related task | Implemented | Appointments with client/case/task links |
| Dedicated meeting notes | Partial | No separate appointment notes field beyond location/history |
| Join from client, task-associated meeting, timeline and portal | Implemented with UI limitation | Client/timeline/portal links exist; association is stored but task card is not a complete embedded meeting workspace |
| Automatically create/update/cancel Zoom meeting | Implemented; operationally pending | Server-to-Server OAuth adapter, queue and provider ownership mapping; no live account smoke test yet |
| Never disclose host start URL or internal credentials to other clients | Implemented | Only join_url retained; portal allowlist/ownership checks |

## 7–11. Proposals, contracts, payments and invoices

| Requirement | Assessment | Evidence / precise limitation |
|---|---|---|
| Draft/issue/view/accept/complete contract lifecycle | Implemented | Commercial document state transitions, timestamps and locked issued terms |
| Contract ID/client/application/title/type/expiry/creator | Implemented with representation difference | Type uses title/terms; no separate structured type catalog |
| Contract file and signed file | Implemented | Generated terms PDF plus exact provider-signed PDF/certificate; scanned before portal access |
| Issue/accept contract timeline and consultant notification | Implemented | Internal commands/provider completion history; acceptance notifications |
| Real electronic signatures | Implemented; operationally pending | DocuSign envelopes, signer tabs, polling, signed PDF/certificate retrieval; account consent and production approval unverified |
| Exact CRM contract-expiry date mapped to provider envelope expiration | Partial | Contract validity is checked before dispatch; subsequent envelope expiration follows the sender account policy rather than an exact CRM midnight deadline |
| Portal acceptance cannot bypass pending DocuSign envelope | Implemented | API rejects click acceptance while signing is pending/sent/uncertain |
| Proposal number, description, fees, other charges, discount, tax, currency, total, validity | Implemented | Exact integer minor-unit totals and commercial draft fields |
| Proposal Draft/Issued/Viewed/Accepted/Rejected/Expired | Implemented | Expiry is computed from validity for open terms |
| Separate proposal service field | Partial | Service described through title/body and linked application rather than separate service field |
| Proposal download and portal acceptance/rejection | Implemented | Authorized PDF and lifecycle endpoints |
| Proposal PDF itemized fee breakdown | Partial | Data model has fee components; current PDF emphasizes terms and total, not a full line-item rendering |
| Payment details bank/name/reference/method/instructions/visibility | Implemented | Issued invoice must belong to selected application |
| Payment requested vs received | Implemented | Instructions/request separate from immutable receipt ledger |
| Partial payments, exact balances, overdue/paid views | Implemented | Invoice payment ledger and derived display states |
| Every proposed payment state (Failed/Refunded/Cancelled/Pending etc.) | Partial | Not a complete standalone payment-state machine; provider requests and ledger have distinct states |
| Payment date, method, reference, recorded actor, invoice link, receipt | Implemented | Receipt ledger and portal PDFs; internal actor omitted from client projection |
| Gateway checkout and verified posting | Implemented; operationally pending | Stripe hosted Checkout; server-side status verification; no live merchant smoke test |
| Gateway refunds, chargebacks and disputes | Partial | Not automatically synchronized; existing manual reversals retain ledger history |
| Invoice create/draft/issue/payment/history/email | Implemented | Existing invoice and finance modules extended by application scope |
| Preview/download PDF and portal invoice access | Implemented | Existing staff print view and new authorized portal PDF |
| Invoice quantity/unit-price/line-items/subtotal/discount/tax calculations | Partial | Existing invoice remains description plus total, not the complete requested line-item invoice model |
| Invoice overdue/partially-paid display and voiding | Implemented | Derived balances/overdue and existing Void workflow |
| Separate Cancelled and Voided invoice states | Partial | Stored state is Void; no separate Cancelled state |

## 12–14. Client portal, files and application status

| Requirement | Assessment | Evidence / precise limitation |
|---|---|---|
| Client authentication without staff/admin access | Implemented | One-use magic link exchange; separate HttpOnly portal session |
| Permanent username/password ClientPortalAccount | Partial / design choice | Access links and sessions are used instead of a persistent password account |
| Own application status and progress | Implemented | Explicit portal projection and stage display |
| Checklist, uploads, review feedback and approved downloads | Implemented | Existing document versioning/quarantine plus per-link grants |
| Upcoming shared meetings and Zoom links | Implemented | Client visible and future scheduled meetings only |
| Proposals/contracts/invoices/payment instructions/status/receipts | Implemented | Explicit ownership-bound portal projections |
| Online payment action and signed document download | Implemented | Provider links and scan-gated signed download endpoint |
| Approved messages/updates portal feed | Partial | Internal communication history is not a separately approved client message feed |
| Hide internal notes/tasks/discussions/audit/admin/AI/other clients | Implemented | Portal uses explicit field allowlists, separate authentication and repeated download ownership checks |
| Document ID/client/application/type/file/version/status/upload details | Implemented with representation difference | Existing documents + document_requests + versions + grants form the model; not one flat table |
| Internal Only / Client Visible enforcement | Implemented with representation difference | Explicit approval/version/scan/grant checks, plus meeting/payment visibility flags |
| Change document ID cannot access another client's file | Implemented | WAI cross-client and unauthenticated access tests |
| All requested application stages plus terminal states | Implemented | Extended stage choices; legacy stages retained for compatibility |
| Each stage change records old/new values and actor/time | Implemented | Existing case history hooks and notification extension |
| Separate client-friendly status mapping | Partial | Portal progress is simplified but mostly uses the internal stage labels |

## 15–20. Notifications, architecture, events and permissions

| Requirement | Assessment | Evidence / precise limitation |
|---|---|---|
| Due-at overdue detection for incomplete tasks | Implemented | Worker plus API refresh; date fallback |
| Overdue popup and persistent notification | Implemented | Minute refresh, unread alert and notification center |
| Open task / complete / reschedule / dismiss actions all in popup | Partial | Open record and dismiss/read supported; complete/reschedule occur in task workspace rather than directly inside popup |
| Dismiss never completes task | Implemented | Notification archive is separate from task status; regression test |
| Unread → Read → Archived | Implemented | Per-user persistent notification state |
| Due soon, uploads, proposal/contract acceptance and payment notifications | Implemented | Existing scheduler/document events plus commercial/provider events |
| Every suggested notification type, including upcoming Zoom and invoice overdue | Partial | Some surfaced as existing reminders/report states rather than dedicated notification types |
| All recommended current-client actions | Implemented | Scoped action area plus provider actions and Integration status |
| Lead/Client/Application relationships with related entities | Implemented | Existing Case serves Application, with scoped records and durable provider jobs/links |
| Immutable history for all significant business events | Partial | Provider events/payment ledger immutable; general work_history has not been replaced with a universally append-only event store |
| Exact event taxonomy from specification | Partial | New named provider/payment events coexist with established case/task/document naming |
| Admin/staff/client backend authorization | Implemented | Existing record/finance privileges plus integration ownership/revision/scope checks |
| Assigned-only visibility | Implemented configurable policy | Existing workspace policy retained; shared staff access remains configurable |

## 21–23. Example journey, connected process, priorities and deployment

| Requirement | Assessment | Evidence / precise limitation |
|---|---|---|
| Maria example from conversion through completion can be operated in one workspace | Implemented at core workflow level | Staff select stages and scoped actions; it is not a mandatory state machine forcing every business step |
| Automatically move Awaiting Payment → Document Collection after payment | Partial | Staff-controlled stage change retained; payment does not automatically choose the next stage |
| Main workflow, independent task workflow, restricted portal operate together | Implemented | Shared client/application IDs, histories and permissions |
| Every significant action updates record/history/notification/audit | Partial | Major actions covered; not every save/visibility/status change has every event/notification from the proposed universal architecture |
| Automated email/reminders | Implemented; operationally pending | Existing SMTP mail/scheduler workers and DocuSign email; actual SMTP/provider delivery not verified here |
| Calendar synchronization | Implemented; operationally pending | Managed appointment two-way sync with Google Calendar; not Microsoft 365 or general personal calendar ingestion |
| Requirement-by-requirement review | Completed by this document | Includes explicit partial requirements and evidence limits |
| SQLite/PostgreSQL provider migrations | Implemented | Additive migration 0018 / PostgreSQL 0005; disposable migration tests required before release |
| Backup-first deployment tooling and worker packaging | Implemented | Plan/apply tool, service unit, Docker/Compose worker, private config templates, recovery tests |
| Provider sandbox acceptance | Operationally pending | No provider credentials/account access available |
| Production migration, deployment, TLS/DNS/live smoke test | Operationally pending | No production target or runtime access supplied; no live migration/deployment performed |

## Acceptance decision

The four requested provider adapters and backup-first deployment mechanism are implemented. Local tests can verify protocol construction, persistence, permissions and failure handling. Live account activation, OAuth consent, provider eligibility, sandbox transactions/signatures, remote production migration and production acceptance remain pending external access and configuration.

The original specification also has the explicit Partial items above. Production readiness must not be presented as complete solely because the local adapter, workflow or browser suites pass. For activation and exact operating limits, see [INTEGRATIONS.md](../INTEGRATIONS.md).
