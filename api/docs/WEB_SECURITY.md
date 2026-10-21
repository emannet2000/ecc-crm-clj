# Web security controls and acceptance

This is hardening against common attack classes, not a certification or a guarantee against every attack. The hosted Render configuration and independent live security checks remain to be verified.

| Attack class | Current controls and checks |
| --- | --- |
| Broken access control / IDOR | Server-side role, privilege and record-assignment checks; portal grants tied to a student/link, approved current version, scan result and expiry; regression tests for hidden records and denied actions |
| SQL injection | Bound query parameters; dynamic identifiers limited to code-owned choices; existing injection and persistence regressions |
| Cross-site scripting | Elm text rendering, escaped printed documents, DOM text content for reports; CSP blocks external/inline scripts and active object embedding; arbitrary uploaded content served as an attachment |
| CSRF / cross-origin writes | Exact origin check; cross-site and sibling-site browser writes rejected; cookie-authenticated mutations require the application's version header; no permissive CORS; JSON/multipart media types required |
| Credential stuffing / brute force | Persistent IP/account limits, generic login errors, bcrypt cost 10, dummy bcrypt work for unknown accounts, MFA support and replay protection |
| Session/JWT abuse | Signed HS256 tokens with strict header/canonical encoding, size/expiry/subject/nonce checks; database session revocation and suspended-user checks; HttpOnly/SameSite Strict/Secure production cookies |
| Parser/resource abuse | 1 MiB non-multipart request cap, 27 MiB multipart envelope cap, JSON depth cap of 64, upload/body deadlines and bounded request/connection capacity; application upload limits remain smaller |
| File traversal / accidental file exposure | Static configuration/database/hidden files rejected; canonical-path check prevents symlink escape, including SPA fallback; static files accept GET/HEAD only |
| Malicious uploads | Quarantine and ClamAV scanning before downloads, separate review/approval, photo signature/dimension/size checks, portal quotas and access-bound financial evidence |
| Clickjacking / cross-origin leaks | Frame denial, CSP frame ancestors, same-origin resource/opener policy, no-referrer, no-store sensitive responses and production HSTS |
| Spreadsheet injection | CSV formula neutralization and generated roundtrip tests |

The application request header is a browser CSRF boundary, not a secret or an alternative to authentication. CLI clients using cookies must send the current X-ECC-Contract value, available in release.json. Bearer clients remain subject to authorization and origin checks. JSON is limited to 1 MiB; use the existing multipart import/upload workflows for files. The new contract is ecc-crm-20261022-v2, so older pages must reload before saving.

## Deployment requirements

- Rotate the previously shared database password in Render and update every service using it. Generate and set a fresh JWT secret privately; changing it invalidates existing staff JWTs. Do not paste replacement secrets in chat or commit them.
- Set APP_ENV=production, the correct HTTPS PUBLIC_URL, a TLS DATABASE_URL and SEED_DEMO=false. Verify the deployed frontend and API are the same tested release. Use the read-only `scripts/render_preflight.py` checks described in the Render deployment guide.
- Confirm the database belongs to this ECC CRM before migrations. Back it up and verify restoration first. Use the existing live database only after schema compatibility is established; do not initialize a different application's database.
- Keep the scanner private and current, keep PostgreSQL/runtime dependencies updated, use least-privilege accounts, and protect backup encryption keys independently. Enable MFA for administrators and check Flor's actual privileges.
- Verify backup failure alerts and an independent uptime monitor. The app's request limits are not a replacement for provider/network DDoS protection.

## Verification and remaining checks

The regression suite covers authentication/session revocation, MFA replay, permissions, hidden-record visibility, print/CSV escaping, quarantine and new hardening cases. The new cases exercise forbidden origins, cookie writes without the app header, simple-form/parser rejection, large/deep JSON, JWT header/encoding confusion, security headers, unsafe static files and symlink escapes.

Run the full `scripts/check.sh` gate in CI, including real PostgreSQL, HTTP and browser tests. Before live approval, run a credentialed access-control and upload review on an isolated deployed environment, inspect dependency/container vulnerability reports, and confirm the Render proxy/TLS/network settings. No live penetration test or dependency audit has been completed in this workspace. Do not scan unrelated services or run destructive attack tools against Flor's live data.

References: [OWASP REST security](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html), [CSRF prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html), [file uploads](https://cheatsheetseries.owasp.org/cheatsheets/File_Upload_Cheat_Sheet.html), [HTTP headers](https://cheatsheetseries.owasp.org/cheatsheets/HTTP_Headers_Cheat_Sheet.html).
