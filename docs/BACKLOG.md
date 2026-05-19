# Backlog

Deliberately deferred to keep the MVP tight. Nothing here blocks the assessment requirements; everything here is reasonable next-step polish, captured at the moment we chose to defer.

## Stats page polish

- **Time-series chart of clicks per day** (last 30 days). The query data is already in `ShortLinkStatsQuery` shape; would land via `chartkick` + Chart.js. Removed from MVP because the totals + country table + recent visits already cover the brief's "clicks, geolocation, timestamps" requirement.
- **Unique-visitors counter**. `COUNT(DISTINCT ip_hash) WHERE short_link_id = ?` — already supported by the existing `(short_link_id, ip_hash)` composite index. Surface in `ShortLinkStatsQuery::Result` and the stats view.
- **Pagination on recent visits**. Currently capped at 50 via `RecentClicksQuery#call(limit: 50)`. Trivial to add a `page:` parameter.

## Data lifecycle

- **`PurgeOldClicksJob`** — scheduled deletion of clicks older than 90 days for retention compliance. The composite `(short_link_id, occurred_at DESC)` index supports a fast purge.
- **Materialized-view rollup** for stats — once `clicks` exceeds millions of rows. Documented in `docs/WIKI.md` §3 as scalability step 3.

## Auth + ownership

- **Owner-only stats** with magic-link sign-in. Closes the §2.3 "stats are public" deliberately-deferred limit, while keeping the no-account simplicity for visitors. Adds a `user_id` (nullable) FK on `short_links` and gates `StatsController#show`.

## UI

- **Copy-to-clipboard button** on the result card and the stats-page header. Stimulus controller, ~10 lines.
- **Animated title transition** when the Turbo Stream replaces the placeholder — Turbo's built-in `data-turbo-action="advance"` doesn't help here; would need a small CSS transition on the swap.
