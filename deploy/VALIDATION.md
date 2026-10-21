# Validation record — 2026-10-18

Repository fixes are implemented. Production acceptance remains open until the deployment checks below pass.

## Passed locally

- Optimized frontend compilation using Elm 0.19.1.
- Thirteen tests executing the actual compiled Elm update function: stale and repeated searches, navigation/mutation invalidation, staff directory loads during searches, stale authentication errors/session expiration, operational/feature pagination, nested document form versions, clearing MFA/link data on logout, rejecting portal data arriving after logout, inline client/case scope isolation, baseline capture, conflict rebasing without automatic submission, and discarded conflict responses after logout.
- Twenty-five Python database/operations tests, including migration/query validation, concurrent numbering, audit redaction, revocation, read/write concurrency, online backups, retention, remote failure/success markers, monitoring, restore counts/document parity, advisory version matching, idempotent reminder/recurrence scheduling, parent revisions, workflow audit categories, MFA redaction, ClamAV stream framing, fail-closed scanning/content replacement, infection notifications, preference-aware scheduling/snapshots and SMTP backoff and quarantine of legacy files without losing bytes, approval history or audit records.
- Haskell authentication and SQLite/WAI regression executable, including conversion/rollback, permissions, revocation, spoofed versus trusted proxy headers, independent account/source buckets, reads during an external write lock, and archive/reminder/duplicate results beyond their former fixed caps.
- Workflow WAI acceptance: full task updates and stale-save rejection, document versions/retention, explicit portal grants, uploads/quotas, and revoked old versions, one-use activation, merge invalidation/preservation, invoice amounts/status/email, appointment collision/UTF-8 ICS, paginated saved views, suspension, RFC 6238 vectors, MFA enrollment and single-use recovery codes.
- Expanded WAI checks: converted tasks in inline client panels, case-scoped task creation, direct checklist upload and stale revision rejection, quarantine download/approval gates, scan retries, cross-record permission denial, conflict field retrieval, notification preference revisions, controlled mail retries, and CSV/ageing/bottleneck/trend endpoints.
- Static contrast calculations for updated styles: table headers 7.21:1, error text 8.02:1, focus outline against white 5.75:1, and dark table headers 9.3:1. These checks cover those color pairs, not full application accessibility.
- Python compilation, JavaScript syntax checks and shell syntax checks.

The preinstalled Haskell package cache contains missing/incompatible libraries. Dependencies were rebuilt in `/tmp`; a mismatched system `os-string` library was also rebuilt there and supplied to the linker without changing the system installation. The API and regression sources compiled, the API CLI initialized a test database, and the regression executable exited successfully. The committed freeze file matches the dependency versions used for this verification (including hashable 1.5.1.0, random 1.3.1 and splitmix 0.1.3.2). A standard clean CI/container build is still required; the local workaround does not certify a deployment image.

## Blocked in this environment

- Real HTTP transport tests: socket creation fails with `PermissionError: Operation not permitted`, before tests execute.
- Browser tests, including inline client/case work, conflict dialogs, direct-upload controls, delayed responses and pagination: Chromium fails during startup because sandbox IPC operations are prohibited. State tests pass independently; browser rendering/interaction is unverified here.
- Actual ClamAV daemon/signature updates, antivirus test sample detection and scanner-network outage behavior require a running deployment. Mocked protocol/worker tests pass; no live antivirus result is claimed.
- Docker image builds, Compose validation and image vulnerability scans: Docker is not installed. The Haskell advisory checker has regression coverage, but its scan against the live advisory database also requires CI/network access. No clean vulnerability result is claimed.

The quality workflow runs the complete application suites, advisory check, release builds, Compose validation and high/critical image scans on a normal CI runner. Resolve all failures before release.

## Deployment acceptance pending

Follow [the production runbook](PRODUCTION.md). Supply the staging hostname and existing configuration paths to verify DNS/TLS, actual invitation/reset delivery, off-host repository access, independent uptime alerts, representative load and a timed application-level restore. Local restore tests verify integrity, counts and document bytes; they do not verify real deployment recovery credentials or workflows.

## Operations rollout

Review [the operations guide](OPERATIONS.md). Migration 0006 quarantines existing files as well as new uploads; scans must finish before downloads and approval resume. The release now includes the ClamAV image, scanner worker, updated mail/scheduler services and required shared volumes. Live antivirus, keyboard/screen-reader/contrast verification, SMTP delivery and deployment recovery remain acceptance requirements.
