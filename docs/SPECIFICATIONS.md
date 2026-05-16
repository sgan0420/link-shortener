# Link Shortener — Design Specification

**Status:** Approved (brainstorming complete)
**Source brief:** [`docs/REQUIREMENTS.md`](./REQUIREMENTS.md)
**Implementation plan:** [`docs/PLAN.md`](./PLAN.md) (to be written next)

This document captures the agreed design for the CoinGecko URL Shortener take-home. Decisions here are the source of truth for implementation; if reality forces a deviation during build, update this file in the same PR.

---

## 1. Goals and posture

Build the URL shortener described in `REQUIREMENTS.md`. L1 baseline, deliberately punching up toward L2/L3 in:
- **Strategic design patterns**: service objects, query objects, presenters/decorators
- **Error and edge-case handling**: SSRF protection, validation, retries, graceful degradation
- **Scalability writeup**: documented growth path, no premature optimization
- **Security writeup**: validation, CSRF/headers, rate limiting, PII minimization

Non-goals (deliberately out of scope):
- User accounts / ownership of links
- Custom slugs
- Link expiry / deletion UI
- API for programmatic shortening (the form is the API)

---

## 2. Tech stack

| Layer | Choice |
|---|---|
| Language / framework | Ruby 3.x · Rails 8.x |
| Database | PostgreSQL |
| Background jobs | Solid Queue (Puma plugin in prod — `SOLID_QUEUE_IN_PUMA=true`) |
| Cache | Solid Cache (used for geolocation lookups) |
| Frontend | ERB · Turbo · Stimulus · Tailwind (via `tailwindcss-rails` standalone binary) |
| JS asset pipeline | `importmap-rails` (no Node, no bundler) |
| Test | RSpec · FactoryBot · Capybara · Cuprite · WebMock · VCR · Shoulda Matchers · SimpleCov |
| Lint / security | RuboCop (Rails Omakase) · Brakeman |
| Slug generation | `nanoid` gem · 7 chars · default 64-char URL-safe alphabet |
| Geolocation provider | ipapi.co (HTTPS, no signup) — wrapped behind `GeolocationService` for swap-ability |
| Rate limiting | `rack-attack` |
| Deployment | Render — `render.yaml` Blueprint; single web service running web + jobs |
| CI | GitHub Actions: RSpec + RuboCop + Brakeman |

---

## 3. Architecture

Single Rails monolith, layered:

```
┌─────────────────────────────────────────────────────┐
│  UI (ERB + Turbo Streams + Stimulus + Tailwind)     │
├─────────────────────────────────────────────────────┤
│  Controllers (thin)                                 │
│    ShortLinksController · RedirectsController       │
│    StatsController · ErrorsController               │
├─────────────────────────────────────────────────────┤
│  Service Objects                                    │
│    UrlShortener · TitleFetcher · GeolocationService │
├─────────────────────────────────────────────────────┤
│  Background Jobs (Solid Queue)                      │
│    FetchTitleJob · RecordClickJob                   │
├─────────────────────────────────────────────────────┤
│  Models                                             │
│    ShortLink · Click                                │
├─────────────────────────────────────────────────────┤
│  Query Objects                                      │
│    ShortLinkStatsQuery · RecentClicksQuery          │
├─────────────────────────────────────────────────────┤
│  Decorators / Presenters                            │
│    ShortLinkPresenter · ClickPresenter              │
└─────────────────────────────────────────────────────┘
```

**Boundaries / interfaces:**

- **Controllers** parse params, dispatch to a service, render. No business logic.
- **Services** are plain Ruby objects, `.call`-style, raising typed errors. Dependency-injectable so jobs can stub the geo provider in tests.
- **Jobs** orchestrate side effects (HTTP + DB write + Turbo broadcast). The "right amount" of indirection: a job per real-world event, not a job per operation.
- **Query objects** own non-trivial SQL for the stats page so models stay slim.
- **Presenters** format model data for views (short URL string, formatted timestamps, masked IP hash prefix) without polluting models or views.

**Explicit non-inclusion:** No `ClickRecorder` service. `RecordClickJob` calls `GeolocationService` and writes the `Click` row directly. A service object here would be pure indirection.

---

## 4. Data model

### `short_links`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `slug` | string(15) | unique index; nanoid, default 7 chars |
| `target_url` | string(2048) | validated `http`/`https` only |
| `title` | string(512) | nullable until fetched |
| `title_status` | enum (`pending`, `fetched`, `failed`) | drives UI rendering of the title slot |
| `created_at` / `updated_at` | timestamps | |

**Indexes:** `unique(slug)`, `index(created_at desc)`.

### `clicks`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `short_link_id` | bigint FK | on_delete: cascade |
| `country` | string(2) | ISO-3166 alpha-2, nullable |
| `city` | string(128) | nullable |
| `ip_hash` | string(64) | `SHA256(ip + ENV['CLICK_IP_SALT'])` hex |
| `occurred_at` | timestamptz | captured by controller before enqueue |
| `created_at` | timestamptz | row write time |

**Indexes:**
- `index(short_link_id, occurred_at desc)` — recent visits, time-series
- `index(short_link_id, country)` — country breakdown
- `index(short_link_id, ip_hash)` — unique visitor count

**Design notes:**

- `occurred_at` is distinct from `created_at` so analytics stay honest if the queue backs up.
- `title_status` is explicit (not nil-vs-empty) so the Turbo Stream partial can render distinct states unambiguously.
- `ip_hash` is privacy-preserving but still supports unique-visitor counts. Per-deployment salt means hashes don't cross environments.
- No rollup table. The wiki documents migration to materialized view or hourly rollup as the scalability workaround.

---

## 5. Routing

```ruby
root "short_links#new"
post "short_links" => "short_links#create"
constraints slug: /[A-Za-z0-9_-]{1,15}/ do
  get ":slug/stats" => "stats#show",     as: :stats
  get ":slug"       => "redirects#show", as: :short_link
end
```

- `/:slug/stats` is declared **before** `/:slug` — Rails router resolves top-to-bottom.
- Reserved-slug check happens at *creation* time (not in the router) via `ShortLink::RESERVED_SLUGS`. Reserved: `up`, `stats`, `about`, `admin`, `rails`, `assets`, `short_links`.
- Slug regex constrains routing to valid slug characters; non-matches fall through to a 404.

---

## 6. Request flows

### 6.1 Shorten a URL (`POST /short_links`)

1. Controller validates params present.
2. `UrlShortener.call(target_url)`:
   - Validates scheme (`http`/`https`), length (≤2048), parse-ability.
   - Generates 7-char nanoid, attempts insert; on `slug taken` retries up to 3× (belt-and-suspenders with the unique index).
   - Returns persisted `ShortLink` with `title_status: :pending`.
3. `FetchTitleJob.perform_later(short_link.id)` enqueued.
4. Controller renders Turbo Stream that appends a result card partial to `#results`. The title slot is targeted by `dom_id(short_link, :title)` and shows a "Fetching title…" placeholder.

Later, async:

5. `FetchTitleJob` runs `TitleFetcher.call(target_url)`:
   - SSRF guard: resolve hostname → reject private/loopback/link-local IPs (RFC1918, 127/8, 169.254/16, ::1, fc00::/7, fe80::/10).
   - HTTP GET with 5s open + 5s read timeout, max 1 MB body, max 3 redirects.
   - Parse `<title>` with Nokogiri, strip/squish, truncate to 512.
6. Job updates `short_links` row (`title`, `title_status: :fetched` or `:failed`).
7. `Turbo::StreamsChannel.broadcast_replace_to(short_link, target: dom_id(short_link, :title), partial: "short_links/title", locals: { short_link: })` pushes the title (or "Title unavailable") to any subscribed browser.

### 6.2 Visit a short URL (`GET /:slug`)

1. `RedirectsController#show` finds the `ShortLink` by slug; 404 (branded) on miss.
2. Capture `occurred_at = Time.current` and `ip = request.remote_ip` (Rails handles X-Forwarded-For).
3. `RecordClickJob.perform_later(short_link.id, ip, occurred_at)`.
4. `redirect_to short_link.target_url, status: 302, allow_other_host: true`.

Status `302` (not `301`) so browsers don't cache the redirect — every visit hits us and is counted.

Later, async:

5. `RecordClickJob` calls `GeolocationService.lookup(ip)`:
   - Private/loopback IP → return `Unknown` without HTTP.
   - `Rails.cache.fetch("geo:#{ip}", expires_in: 24.h) { ipapi.co GET, 2s timeout }`.
   - Returns `{ country:, city: }` or `Unknown` on error/timeout.
6. Job writes `Click.create!(short_link_id:, country:, city:, ip_hash:, occurred_at:)`.

### 6.3 Stats page (`GET /:slug/stats`)

1. `StatsController#show` finds the `ShortLink`; 404 on miss.
2. `ShortLinkStatsQuery.new(short_link).call` → `{ total_clicks, first_at, last_at, by_country: [...] }`.
3. `RecentClicksQuery.new(short_link).call(limit: 50)` → ordered list of recent click rows.
4. View renders summary card, country table, recent visits table (timestamps, country/city, `ip_hash[0..7]` masked prefix).

**Note:** Unique-visitors counter and time-series chart are deferred to `docs/BACKLOG.md` to keep MVP tight.

---

## 7. Async jobs and error handling

### 7.1 Solid Queue topology

- Single `:default` queue at this scale.
- Run via Puma plugin (`SOLID_QUEUE_IN_PUMA=true`) — one Render web service runs both web and worker.
- Wiki documents migration to a separate `bin/jobs` worker process when web latency competes with job throughput.

### 7.2 Job behavior

| Job | Retry policy | Idempotency | Failure mode |
|---|---|---|---|
| `FetchTitleJob` | `retry_on` `Net::OpenTimeout`, `Net::ReadTimeout`, `OpenURI::HTTPError` (5xx) — exponential backoff, ≤3 attempts | `UPDATE` keyed on `short_link.id`; second success is a no-op | After max attempts → `title_status: :failed`; UI shows "Title unavailable" |
| `RecordClickJob` | Retry on transient errors, ≤3 attempts | Retries reuse the original `occurred_at`; worst-case duplicate row, which is acceptable | After max attempts → drop the click + log it. Documented trade-off: rare loss preferred over blocking redirect |

**Non-retryable errors** (`discard_on`):
- `URI::InvalidURIError`, `Addressable::URI::InvalidURIError`
- `TitleFetcher::PrivateAddressError` (SSRF guard)
- `Resolv::ResolvError` (DNS) — after first attempt, mark failed

### 7.3 Timeout matrix (defense in depth)

| Operation | Timeout |
|---|---|
| Title fetch open + read | 5s each |
| Title fetch response body | capped at 1 MB |
| Title fetch redirects | ≤3 |
| Geolocation HTTP | 2s |
| Solid Queue job wall-clock | 30s soft cap |

### 7.4 Controller error responses

| Scenario | Response |
|---|---|
| `ShortLink.find_by!(slug:)` miss → `ActiveRecord::RecordNotFound` | 404 + branded "Link not found" page |
| `UrlShortener::ValidationError` (invalid target URL) | 422 Turbo Stream that replaces the form with inline error messages, preserving user input |
| Unhandled server error | 500 + branded page; `Rails.error.report` |
| Rate-limit trip (rack-attack) | 429 with `Retry-After` and a polite response |

### 7.5 Slug collision retry

`UrlShortener` wraps the insert in a 3-attempt loop. Unique index on `slug` is the source of truth; application-level retry is best-effort to keep UX clean. If the loop exhausts (never observed in practice), raise `CollisionExhaustedError` and surface a generic "please retry" error.

### 7.6 Logging discipline

- Structured tags via `config.log_tags = [:request_id]`.
- Never log raw IPs — log `ip_hash[0..7]` if useful for debugging.
- Job logs include `short_link_id`, attempt number, outcome.

---

## 8. Security

| Area | Implementation |
|---|---|
| **URL validation** | Allowlist scheme (`http`, `https`); length ≤2048; parse via `URI.parse`; reject `javascript:`, `data:`, `file:` and any non-allowlisted scheme |
| **SSRF protection** | Before any HTTP fetch (title), resolve hostname and reject if any A/AAAA record is private/loopback/link-local/multicast/reserved |
| **Rate limiting** | rack-attack: throttle `POST /short_links` to 20/min/IP; throttle redirect bursts; safelist localhost in dev/test |
| **CSRF + headers** | Rails default CSRF on; add `Content-Security-Policy` (script-src self + Turbo's inline policy), `Referrer-Policy: no-referrer-when-downgrade`, `X-Content-Type-Options: nosniff`, `Strict-Transport-Security` in prod |
| **PII minimization** | Store `SHA256(ip + ENV['CLICK_IP_SALT'])` instead of raw IP; country/city retained; per-environment salt; documented retention story |
| **Public stats** | Intentional for the demo; documented in wiki as a production gap (would gate behind ownership/auth) |

---

## 9. Testing strategy

| Layer | Spec dir | Focus |
|---|---|---|
| Models | `spec/models` | validations, enums, scopes, associations |
| Services | `spec/services` | per-service: happy path + each error branch. WebMock stubs all outbound HTTP |
| Queries | `spec/queries` | SQL correctness across factory-built fixtures |
| Jobs | `spec/jobs` | enqueue assertions, `perform_now` behavior, retry/discard configuration |
| Requests | `spec/requests` | controller status codes, params, Turbo Stream MIME, 404/422/429 paths |
| System | `spec/system` | one Capybara golden-path walkthrough (rack_test for non-JS; cuprite for the Turbo Stream test) |
| Routing | `spec/routing` | reserved-slug protection; `/:slug/stats` matches before `/:slug` |

**Tooling:**
- FactoryBot factories with traits (`:fetched_title`, `:failed_title`, `:from_country`)
- WebMock blocks all real HTTP; allowed list empty
- VCR cassette for one ipapi.co contract spec (proves real-response shape parses correctly)
- Shoulda Matchers for terse validation/association specs
- SimpleCov for coverage reporting

**Deliberately not tested:**
- Tailwind class names (visual, brittle)
- ipapi.co response variations beyond happy + timeout + 5xx
- Solid Queue internals

Coverage target: organic ~90%+ line coverage as a by-product of layered testing, not a goal in itself.

---

## 10. Deployment

### 10.1 Render

- `render.yaml` Blueprint at repo root: one web service, one Postgres instance.
- Build: `bundle install && rails db:migrate && rails assets:precompile` (no Node).
- Start: `bin/rails server` with `SOLID_QUEUE_IN_PUMA=true`.
- Health check: `/up` (Rails 8 default). `up` is in `RESERVED_SLUGS`.

### 10.2 Environment variables

| Var | Purpose |
|---|---|
| `DATABASE_URL` | Render-provided |
| `RAILS_MASTER_KEY` | secrets decryption |
| `SECRET_KEY_BASE` | Render-generated |
| `CLICK_IP_SALT` | per-env IP hash salt; never logged |
| `IPAPI_BASE_URL` | default `https://ipapi.co`; overridable in tests |
| `APP_HOST` | used by view helpers to construct short URLs |

### 10.3 Local dev

- `bin/setup` installs gems, prepares DB.
- `bin/dev` runs `Procfile.dev`: web + Tailwind watcher + jobs (all Ruby; no Node).

### 10.4 CI (GitHub Actions)

Single workflow on PR + push to main:
1. Checkout
2. Setup Ruby from `.ruby-version` with bundler cache
3. Start Postgres service container
4. `bin/rails db:prepare`
5. `bundle exec rspec`
6. `bundle exec rubocop`
7. `bundle exec brakeman --no-pager`

Status badge in README.

---

## 11. Documentation

| File | Purpose |
|---|---|
| `README.md` | One-line pitch, live demo URL, features, tech stack, local setup, env vars, testing, deploy, link to wiki. CI + Brakeman badges. |
| `docs/REQUIREMENTS.md` | The brief, verbatim. Source of truth, not modified. |
| `docs/SPECIFICATIONS.md` | This file. |
| `docs/PLAN.md` | Ordered implementation steps (written next via writing-plans skill). |
| `docs/WIKI.md` | The "brief Wiki" the brief asks for. See outline below. |
| `docs/BACKLOG.md` | Deferred polish, deliberately scoped out of MVP. |

### 11.1 `docs/WIKI.md` outline

1. **Short URL path: the chosen solution**
   - 7-char nanoid, 64-char URL-safe alphabet; capacity ≈ 4.4 × 10¹²
   - Why nanoid over Base62-of-ID: unguessability, no enumeration leak
   - Generation flow + collision-retry mechanism
2. **Limitations and workarounds**
   - Collision probability (birthday paradox math + growth path: extend slug length)
   - Reserved slugs (`up`, `stats`, `about`, `admin`, `rails`, `assets`, `short_links`)
   - Public stats pages — intentional for demo, requires auth in production
   - Geolocation accuracy — VPN/proxy/NAT inaccuracy, carrier IPs, rate limits; workaround: swap `GeolocationService` to MaxMind GeoLite2
   - Click loss vs duplicate clicks — rare duplicates accepted over blocking redirects; eventual loss after 3 retry attempts is logged and acceptable
3. **Scalability considerations**
   - Current envelope: bounded by Postgres write throughput on `clicks`
   - Workarounds: append-only click sink + rollup; materialized view for stats; Solid Cache for slug → URL lookups; separate `bin/jobs` worker; read replicas for stats
4. **Security considerations**
   - URL validation, SSRF protection, CSRF + headers, rate limiting, PII hashing
   - What's *not* protected and why (public stats by design)
5. **PII and retention**
   - What we store, what we don't, salted-hash design, production retention story (90-day purge job — not implemented for demo)

### 11.2 `docs/BACKLOG.md` (deferred MVP polish)

- Chart.js time-series on stats page (via chartkick)
- Unique-visitors counter on stats page
- Materialized-view rollup for stats
- Pagination on recent-visits table
- 90-day click purge scheduled job

---

## 12. Open questions

None at spec-approval time. Track new ones in `docs/PLAN.md` if they emerge during implementation.
