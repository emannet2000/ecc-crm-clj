The local frontend in `web/` uses the navy and gold motif from
`/home/eman/ecc-crm-myapp5/public/workspace.css`, adapted to this CRM's Elm
components. It retains this application's API integration and workflows.

Run `cabal run ecc-crm-api` from this directory. The API now prefers
`web/dist` when present. An explicit `WEB_DIST` still takes precedence.
Rebuild frontend changes with `bash scripts/build-themed-web.sh`.

Run `python3 scripts/add-sample-data.py` to add fictional sample leads,
clients, cases, tasks and activities to the configured `DATABASE_PATH`
(default `ecc-crm.sqlite3`). It requires the existing demo@northwind.dev
account, preserves credentials, assigns samples to that account, and skips
sample records already present. All sample email addresses use example.com.

`scripts/prepare-themed-web.py` is the initial import utility. Rerunning it
replaces the local frontend with a fresh copy from `../web`, then reapplies
the palette. Use the build script for ordinary frontend edits.

The local frontend is an installable PWA. Serve it over HTTPS (localhost also
works), then use **Install ECC app** when the browser offers it. On iPhone/iPad,
open the site in Safari and choose Share → Add to Home Screen. The manifest
uses standalone mode and includes maskable 192px and 512px icons.

The service worker caches only a public offline page and icons. CRM records,
API responses, attachments, credentials and form submissions are not cached;
working with records requires a connection. Opening the app while disconnected
shows an offline screen with a retry link. No offline editing or sync is provided.
Rebuild with `bash scripts/build-themed-web.sh`; restart the API after updating
its static-file middleware so the manifest is served with the correct MIME type.

PWA checks: `node --test scripts/pwa.test.cjs` and
`cabal test regression --test-show-details=direct`.
Phone browser checks (requires Chromium):
`CHROME_PATH=/usr/bin/chromium node scripts/mobile.browser.cjs`.
Screenshots are saved in `/tmp/ecc-pwa-*.png`.

Reports now include a custom report designer under Reports → Overview,
Application ageing, Bottlenecks and Historical workload. Apply the date range,
then filter text, set a minimum metric, sort and choose visible columns.
The on-screen table shows up to 100 matches; customized CSV and print preview
include all matches from the loaded report (maximum 10,000). Reaching the cap
shows a warning to narrow the date range. Reports remain administrator-only.

Print preview supports A4/Letter/Legal, portrait/landscape, compact/comfortable
spacing, report title, subtitle, footer, and a session-only header image.
Use Print / Save PDF in the preview; browser printer settings control final
margins, headers, page numbering and printer output. Save/load layout remembers
column visibility and layout settings on this device, without report contents,
search text, titles, notes or images.

Click an approved client photo or selected image-upload thumbnail for an enlarged
preview. A preview does not save an upload; client images still follow the existing
upload and malware-scanning workflow. Header images are not uploaded or persisted.

Reporting checks: `node --test scripts/report.test.cjs scripts/report-output.test.cjs`.
In environments that block Node child-process pipes, compile separately with
`(cd web && /usr/bin/elm make src/Main.elm --output=/tmp/ecc-report-checks.js)`
and run `ECC_ELM_REPORT_JS=/tmp/ecc-report-checks.js node --test scripts/report.test.cjs`.

Phone navigation now uses a fixed Home/Leads/Clients/Tasks/More bar at widths up
to 720px. More contains secondary workflows, administration (for admins), and
account controls; it closes after selecting an action, clicking outside, or
pressing Escape. The desktop sidebar remains available above that breakpoint.
Safe-area spacing keeps the bar, install prompt, and feedback above device edges.

Client lists and client application tables become labeled cards on phones while
retaining every field. Client details include email/call links and phone fields
use telephone keyboards. Forms use full-width bottom sheets with visible action
footers. The navigation bar yields to dialogs, and long contact values wrap.

`scripts/mobile.browser.cjs` covers 320/390/720px layouts, touch target sizes,
client cards, menu dismissal, dialog bounds, and switching back to the desktop
sidebar. The frontend build and state/report/offline suites pass locally. Browser
execution is pending an environment that permits Chromium's process startup;
this workspace blocks it before rendering, so no new screenshots were verified.
