# Business date and live clock

The CRM defaults to `CRM_TIMEZONE=Asia/Manila` (Philippine time, UTC+08:00).
`CRM_TIMEZONE=UTC` is also supported. An unsupported value prevents database
connections/startup rather than silently choosing another timezone. Set this on
the API service and restart after changing it. These two supported zones have no
seasonal daylight-saving changes. The business timezone is shared by all users,
independent of their device's timezone or the server's local timezone.

`GET /api/time` returns the server's current Unix milliseconds, UTC instant,
business date, timezone name and UTC offset. It contains no account data and is
available before login with `Cache-Control: no-store`. The UI synchronizes at
startup, every minute and on tab visibility changes. The prominent clock panel on every staff workspace page displays the current ISO date, 24-hour time with seconds, timezone/UTC offset and synchronization status on desktop and mobile. Its displayed clock advances
every second, with server/device clock differences accounted for. Date highlights
advance at business midnight without reloading or discarding drafts. The frontend also refreshes Today counts at business-date changes without resetting editors or replacing page errors; responses for an older requested date are ignored. If a sync
fails, the clock continues from its last correction and shows its unsynchronized
status until a later successful sync.

Deadlines, overdue balances, document expiry, reporting date ranges and posting
validation use the business date. UTC creation/issue timestamps are converted for
calendar-date report filters and invoice issue-month locks. Date-only due dates,
posting dates and bank dates retain the date entered by the user. Authentication,
expiry instants, audit timestamps, mail/scanning leases and backup evidence remain
in UTC. The browser clock never authorizes financial posting or session validity.

Migration `0014_business_clock.sql` updates payment/expense date validation and
invoice period-lock triggers. The API registers the `business_offset()` SQLite
function on every connection. Financial writes must use the API; external tooling
that writes these tables would need the same registered function and business
zone. Existing migrations are unchanged. Reports can group near-midnight historical
UTC entries under a different calendar date when moving from UTC to Philippine
time; posted amounts and stored timestamps are not rewritten.

Deploy the rebuilt backend/frontend together, apply migrations and restart the API.
Keep the production host's system clock synchronized using its time service/NTP;
the CRM reads that clock and does not set the operating system time or contact an
external time provider. No production deployment or time-service setup is performed
by editing these files.

Checks include deterministic Manila/UTC midnight, year and leap-day boundaries;
SQLite/Haskell agreement; business issue-month locking; today/tomorrow payment
validation; a current, noncacheable public clock endpoint; and compiled Elm tests
for device clock skew, midnight rollover, UTC configuration, offline ticking and
draft preservation.

Application/task deadlines currently use dates, not school-specific cutoff times. A date is overdue after that date in the configured business timezone. The live clock does not add time-of-day fields to those deadlines.

If the midnight summary refresh fails, the last counts remain visible and the next minute tick retries when the summary date is stale. One-second clock ticks do not repeatedly request summaries.
