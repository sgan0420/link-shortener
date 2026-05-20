# Link Shortener

A small URL-shortener service built for the CoinGecko engineering assessment. Submit a long URL, get a short, unguessable one back — with public, per-link stats showing clicks, country breakdown, and recent visits. Async page-title fetching via Turbo Streams so the result card updates live the moment the title is resolved.

> **🔗 Live demo:** [link-shortener-x7ry.onrender.com](https://link-shortener-x7ry.onrender.com/)
> **Design wiki:** [`docs/WIKI.md`](docs/WIKI.md)
> **Source-of-truth specs:** [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md) · [`docs/SPECIFICATIONS.md`](docs/SPECIFICATIONS.md) · [`docs/PLAN.md`](docs/PLAN.md) · [`docs/BACKLOG.md`](docs/BACKLOG.md)

> First request after idle may cold-start in ~30 s — Render's free web tier spins down after 15 min of inactivity.

## Features

- Short, unguessable 7-character URLs (nanoid)
- Async `<title>` fetching with live Turbo Stream UI update — the result card swaps from "Fetching title…" to the real title without a page reload
- Public per-link stats page (`/<slug>/stats`): total clicks, first/last seen, country breakdown, recent visits
- Per-browser "My links" page (`/my-links`): server-side hydration of slugs stored in `localStorage`. No accounts; localStorage is the ownership proxy — see [`docs/WIKI.md`](docs/WIKI.md) §2.3
- Background click logging with IP-based geolocation; raw IPs are salted-hashed at rest
- SSRF-protected title fetching, rate-limited form (`POST /short_links` 20 req/min/IP), loose redirect throttle, CSP + HSTS + nosniff + frame-ancestors + secure headers

## Tech stack

| Layer | Choice |
|---|---|
| Language / framework | Ruby 3.3.6 · Rails 8.1 |
| Database | PostgreSQL 16 |
| Background jobs | Solid Queue (in-Puma in prod via `SOLID_QUEUE_IN_PUMA=true`) |
| Cache | Solid Cache |
| Action Cable | Solid Cable |
| Frontend | ERB · Turbo · Stimulus · Tailwind (`tailwindcss-rails` standalone binary) |
| JS asset pipeline | `importmap-rails` (no Node, no bundler) |
| Slug generation | `nanoid` gem · 7 chars · default URL-safe alphabet |
| Geolocation | ipapi.co (HTTPS, no signup) — swappable via `GeolocationService` |
| Rate limiting | `rack-attack` |
| Test framework | RSpec · FactoryBot · Capybara · Cuprite · WebMock · VCR · Shoulda Matchers · SimpleCov |
| Lint / security | RuboCop (Rails Omakase) · Brakeman · bundler-audit · importmap audit |
| Deploy target | Render — `render.yaml` Blueprint |

## Local setup

Prerequisites: Ruby 3.3.6 (via mise / rbenv / asdf), PostgreSQL 16 running locally.

```bash
git clone https://github.com/sgan0420/link-shortener.git
cd link-shortener
bin/setup --skip-server     # bundle install + db:prepare
bin/dev                     # web + Tailwind watcher + Solid Queue (foreman)
```

Visit http://localhost:3000.

## Environment variables

Every variable that matters in production:

| Var                    | Required in | Notes                                                                                |
|------------------------|-------------|--------------------------------------------------------------------------------------|
| `DATABASE_URL`         | production  | Provided by Render's managed Postgres                                                 |
| `RAILS_MASTER_KEY`     | production  | From `config/master.key` — used to decrypt credentials                                |
| `SECRET_KEY_BASE`      | production  | Render-generated                                                                      |
| `CLICK_IP_SALT`        | production  | Per-env salt for hashing visitor IPs. Never logged.                                   |
| `RAILS_MAX_THREADS`    | all         | Default 5. Drives both Puma threads and the AR pool sizing (`pool = MAX_THREADS + 5`) |
| `SOLID_QUEUE_IN_PUMA`  | production  | `"true"` runs the Solid Queue worker in the web process                               |
| `IPAPI_BASE_URL`       | all         | Defaults to `https://ipapi.co`. Overridable for staging fixtures.                     |
| `APP_HOST`             | production  | Used by `ShortLinkPresenter` to build absolute short URLs                             |
| `APP_SCHEME`           | optional    | Defaults to `https`. Override only if deploying behind a plain HTTP proxy             |

## Testing

```bash
bundle exec rspec       # full suite
bundle exec rubocop     # style
bundle exec brakeman    # static security scan
bin/ci                  # everything above + bundler-audit + importmap audit
```

The same `bin/ci` runs in GitHub Actions on every PR and push to `main` — see [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Architecture, limitations, scalability, security

[`docs/WIKI.md`](docs/WIKI.md) covers the slug scheme + capacity math, every documented limitation with its workaround, the scalability growth path, the security model, and the PII/retention story.

[`docs/SPECIFICATIONS.md`](docs/SPECIFICATIONS.md) is the longer-form design document — layered architecture, request flows, async/error handling, testing strategy.

## Deployment

Render Blueprint via [`render.yaml`](render.yaml). One web service + one managed Postgres instance, deployed from a `git push` to `main`. See `docs/SPECIFICATIONS.md` §10 for the env var inventory and pool sizing rationale.

## License

MIT.
