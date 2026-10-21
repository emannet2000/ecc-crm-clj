# Production acceptance and recovery

Review the [operations rollout guide](OPERATIONS.md), including quarantine of existing files and initial ClamAV signature downloads. Verify clean/infected/outage behavior with the exact release. Run the quality workflow against the exact release before loading customer data. A failed security scan, skipped suite, or untested external integration is an open release blocker. This document records the checks; it does not certify a deployment.

## Build and release identity

Run `python3 scripts/build_release.py` on a Docker host. It pulls the GHC builder once, resolves its immutable digest, builds all four application images, and writes `release-images.json` with the builder digest and resulting image IDs. Runtime, Node, Python and proxy base images have digest pins in source. Retain the manifest with the release and the tested source revision. Haskell dependencies and the Hackage index date are recorded in `api/cabal.project.freeze`. Refresh pins and the freeze file deliberately, rerun the quality gate, and review vulnerability findings before release.

To use these locally built images, run `docker compose -f compose.yaml -f compose.release.yaml up --no-build -d`. Include `-f compose.offhost.yaml --profile monitoring` when off-host backup and monitoring are configured. Use the same overlays for all subsequent lifecycle commands to preserve the tested image selection. Record the actual image IDs after deployment and compare them to the manifest. Registry-based deployments should push those tested images and reference their repository digests. Do not rebuild after acceptance and assume that the result is identical: OS package repositories still supply current security updates at build time.

CI checks dependencies against the Haskell Security Advisory Database and scans each application image. Version matches are conservative and can include APIs this application does not use; resolve findings by updating or documenting a reviewed, narrowly scoped exception before release. There are no preconfigured vulnerability exceptions.

## Configuration and staging acceptance

1. Generate separate random `JWT_SECRET` and `PROXY_TOKEN` values (at least 32 bytes each). Use the supplied Caddy configuration: it overwrites client identity headers and authenticates them with `PROXY_TOKEN`. Keep the API port private. Arbitrary forwarded headers without that secret do not change rate-limit identity. Protect the shared secret like a credential.
2. Set real DNS, `SITE_HOST`, HTTPS `PUBLIC_URL`, SMTP settings and `ALERT_TO`. Start the monitoring profile. Verify hostname resolution, certificate issuance, HTTP-to-HTTPS redirects and browser security headers from outside the server.
3. Review the [workflow guide](WORKFLOWS.md), enroll administrator MFA and retain recovery codes offline. Verify scheduler/reminder emails, stale-save rejection, merge preservation, portal approval/revocation and invoice permissions on staging. Create an admin and verify an actual invitation, password reset, expiry, single use, logout and session revocation. SMTP acceptance alone is insufficient: confirm delivery to the intended inbox and follow the link on the public origin.
4. Test admin, consultant and viewer accounts with representative records. If using `ASSIGNED_ONLY=true`, verify that another consultant cannot read or mutate records, documents, tasks or cases belonging to someone else. Verify the intended behavior for client tasks versus the client's assigned officer. This is one workspace, not tenant isolation.
5. Run `scripts/load_test.py` against staging with a dedicated account and representative data. Record latency and errors at expected concurrent usage, including uploads and CSV exports. Set the acceptance thresholds according to your service objectives and available disk/memory; the sample defaults are starting thresholds, not capacity guarantees.
6. Connect request logs to your log service, with alerts for sustained 5xx rates and latency. Use an independently hosted uptime monitor for the public `/api/ready` URL and configure its own alert transport. The repository's SMTP-based monitor cannot detect loss of its own host or mail transport reliably.

## Encrypted off-host backup

Local snapshots default to hourly with the latest 24 retained. Both interval and retention are configurable. The initial recovery-point objective is at most one backup interval plus upload delay; hourly copies can lose about an hour of committed changes. Choose a shorter interval if necessary. Measure recovery time during the drill below and record it as your recovery-time objective.

Provision a separate remote restic repository, for example an S3 bucket on another host/account. Scope its access credentials to that repository. Keep the restic password in a private file readable by container UID 10001, and store a separate recovery copy of the password and credentials outside the application host. Retention deletes old remote snapshots: use a dedicated repository, and enable provider-side protections appropriate to your recovery policy.

Set `RESTIC_REPOSITORY`, `RESTIC_PASSWORD_PATH` and, for S3, `BACKUP_ACCESS_KEY_ID`, `BACKUP_SECRET_ACCESS_KEY`, and `BACKUP_REGION`. See `.env.example`. The restic password is mounted as a Compose secret, not embedded in an image. Initialize the empty repository once:

```sh
docker compose -f compose.yaml -f compose.release.yaml -f compose.offhost.yaml run --rm --no-deps --entrypoint restic backup init
docker compose -f compose.yaml -f compose.release.yaml -f compose.offhost.yaml --profile monitoring up --no-build -d
```

The worker uploads only verified SQLite snapshots using restic's encrypted repository format. Remote retention keeps 24 latest, 7 daily, 4 weekly and 12 monthly recovery points grouped by the application host/tag. It runs a repository metadata check after retention. It records success only after backup, retention and check all succeed. The monitor alerts if this marker is missing or older than two hours by default. Set `MAX_BACKUP_AGE_SECONDS` consistently with the backup interval. Local retention continues during remote outages to bound disk use; alert response must happen before the required recovery window expires.

## Restore drill

Use an isolated staging/recovery host, a separate destination, and no production traffic. Do this before initial launch and after migration or backup changes.

1. Record the start time, source snapshot timestamp and release identity. Stop the recovery application. Download a remote snapshot using the password and credentials stored outside the original host:

```sh
restic check --read-data
restic snapshots --tag ecc-crm --host ecc-crm
restic restore SNAPSHOT_ID --target /secure/recovery-snapshot
python3 scripts/restore_drill.py /secure/recovery-snapshot/ecc-crm.sqlite3 /recovery/ecc-crm.sqlite3 --report /secure/restore-evidence.json
```

2. The drill script refuses an existing destination, verifies integrity and foreign keys, and compares all table counts and document-content digests with the source snapshot. Its JSON report records timing and explicitly leaves application checks pending. Start the matching tested release against the recovery database; test migrations on a copy before changing versions.
3. Verify login, permissions, representative document bytes/downloads, lead conversion and conversion retry, tasks, audit actors and an invitation/reset email. Use a test SMTP destination to avoid emailing real users from the restored system.
4. Record elapsed recovery time, recovered snapshot age, data counts, verification results and the operator. Keep the acceptance evidence outside the application host. Investigate discrepancies before switching traffic.

A snapshot integrity check is not a substitute for this application-level drill. Real DNS/TLS, SMTP delivery, off-host access, independent monitoring and a timed restore must be verified with deployment credentials; they cannot be established by repository tests.

Implementation references: [restic backup](https://restic.readthedocs.io/en/stable/040_backup.html), [restic retention](https://restic.readthedocs.io/en/stable/060_forget.html), and the [Haskell advisory schema](https://github.com/haskell/security-advisories/blob/main/EXAMPLE_ADVISORY.md).
