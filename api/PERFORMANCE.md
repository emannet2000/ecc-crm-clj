Performance changes
===================

Client authorization now uses `getClient`, a single client/assigned-officer lookup.
Previously `getClientDetail` also loaded cases, documents, tasks, converted-lead
activities and work history. The client detail handler then loaded those again;
profile/photo and workflow authorization also paid this cost.

Response enrichment now collects unique record keys and retrieves revisions in
batches of 200 through SQLite's json_each. User MFA flags and document scan states
are fetched in one query per entity type. Revision defaults and security metadata
remain unchanged. A 50-client response needs one revision query rather than 50.

Migration 0010 indexes converted-client history, client application deadlines,
client task deadlines and lead work history. It is applied by the existing startup
migration runner. On synthetic data containing 100,000 converted leads, the lookup
of one client's source lead measured about 5.9 ms before and 0.006 ms after indexing
(median of 25 runs, in-memory SQLite). This measures that lookup, not page latency.
Run `python3 scripts/performance.py` to reproduce the query-plan and batching checks.

The server now negotiates gzip for API responses and static files. The current
706,407-byte Elm bundle compresses to approximately 116 KB. Existing security and
cache policies are retained.

Validation: `cabal build`, `cabal test regression --test-show-details=direct`, and
`python3 scripts/performance.py`. Regression checks cover batched revision values,
gzip delivery, existing authorization, conversion, document quarantine and workflows.

These are source-level and synthetic findings. No production request logs or live
browser session were available to establish end-to-end page timings. Existing
structured request logs include durationMs and can identify remaining expensive
routes under production data and concurrent traffic. Restart the rebuilt API to
activate the changes and apply migration 0010.

Client Record follow-up
-----------------------

The client task panel and profile next-step queries now evaluate visibility using
indexed, correlated owner lookups for the selected client's tasks. Previously they
materialized lists of visible tasks, leads and clients across the whole database.
The legacy detail task query also uses owner point lookups instead of global lists.
No records are truncated and the existing assignment and archive rules are retained.
Existing task indexes are sufficient; this fix needs no additional migration.

With 100,000 synthetic tasks across 10,000 clients, the task-panel query measured
50.9 ms before and 0.022 ms after; the next-step query measured 50.8 ms before and
0.028 ms after (median of 25 in-memory SQLite runs). The performance script checks
identical scoped results and an indexed client lookup without list subqueries.
These are query timings, not production page-load measurements.

The frontend requests the core Client Record first, then its profile and embedded
panel, so those supplementary reads cannot queue ahead of the initial record.
An already loaded staff roster is reused. Switching panels, changing the application
owner, searching and paging request only the panel instead of all record resources.
Regression tests exercise assigned-task visibility in the record, panel and profile;
compiled Elm state tests verify the request ordering/count and panel-only updates.
