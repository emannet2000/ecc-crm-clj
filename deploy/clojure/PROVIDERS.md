# Provider configuration and acceptance

Set credentials in the untracked `integrations.env`, enable only configured providers in `INTEGRATIONS_ENABLED=zoom,google,stripe,docusign`, and choose a unique `INTEGRATION_NAMESPACE`. Namespace and persistent job IDs are provider-operation identities; preserve them across restarts and retries. Use isolated provider test accounts for staging.

| Provider | Configuration |
|---|---|
| Zoom | `ZOOM_ACCOUNT_ID`, `ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET`, `ZOOM_HOST_USER` for server-to-server OAuth and meetings |
| Google Calendar | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REFRESH_TOKEN`, `GOOGLE_CALENDAR_ID` |
| Stripe | `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, HTTPS `PUBLIC_URL`; configure `/api/webhooks/stripe` for checkout completion/async-success events |
| DocuSign | `DOCUSIGN_CLIENT_ID`, `DOCUSIGN_CLIENT_SECRET`, `DOCUSIGN_ACCOUNT_ID`, `DOCUSIGN_BASE_URL`, optional allowed `DOCUSIGN_AUTH_HOST`, and `DOCUSIGN_REFRESH_TOKEN_FILE` |

The DocuSign base URL must be HTTPS under `.docusign.net` with `/restapi`. Its private refresh-token file must be writable by UID 10001 for atomic rotation. `deploy/clojure/compose.docusign.yaml` mounts a private directory supplied through `DOCUSIGN_SECRET_DIRECTORY`; give the file mode 0600. A read-only Docker secret cannot support token rotation.

Zoom create retries search for the original marker before another create. Google uses deterministic event IDs and ETags. Stripe retains one checkout idempotency key, validates signed raw webhook bytes/timestamps, verifies namespace/invoice/job/amount/currency, and posts a receipt atomically with event deduplication. Polling reconciles payments independently of browser redirects. DocuSign uses a stable transaction identity and downloads exact completed bytes with the completion certificate before malware scanning.

Ambiguous create outcomes enter Review rather than silently creating another meeting, charge, or envelope. Retry preserves the original identity and respects the provider retention window. Resolve operations outside their safe recovery window with the provider account before requesting a replacement.

Before production, verify creation, update/cancellation, expired credentials, timeouts, duplicate delivery, retries, paid-checkout mismatch, closed-period handling, envelope completion/decline, clean/infected/unavailable scanner behavior, and portal ownership against the actual configured accounts. No live provider delivery is claimed by local fixture tests.

Primary API references: [Zoom meetings](https://developers.zoom.us/docs/api/meetings/), [Google event creation](https://developers.google.com/workspace/calendar/api/guides/create-events), [Stripe webhook verification](https://github.com/stripe/stripe-node/blob/master/src/Webhooks.ts), and [DocuSign envelopes](https://developers.docusign.com/docs/esign-rest-api/reference/envelopes/envelopes/create/).
