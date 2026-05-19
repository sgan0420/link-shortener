# Link Shortener — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the URL shortener described in [`docs/SPECIFICATIONS.md`](./SPECIFICATIONS.md): public-facing form to shorten URLs, async title fetching, public per-link stats (clicks/country/recent visits), background click logging with geolocation, deployed to Render.

**Architecture:** Rails 8 monolith with Hotwire + Tailwind UI, Postgres, Solid Queue/Cache/Cable, layered with service objects, jobs, query objects, and presenters. See `docs/SPECIFICATIONS.md` §3 for the layer map.

**Tech Stack:** Ruby 3.x · Rails 8.x · PostgreSQL · Solid Queue/Cache/Cable · Turbo · Stimulus · Tailwind (`tailwindcss-rails`) · `importmap-rails` · RSpec · FactoryBot · Capybara · Cuprite · WebMock · VCR · Shoulda Matchers · SimpleCov · RuboCop · Brakeman · `nanoid` · `rack-attack`.

**Branching:** Each phase ships as a PR off `main` so reviewers see logical chunks. Commit per task; one PR per phase. CI must be green before merging each PR.

---

## Phase 0 — Bootstrap

### Task 1: Generate the Rails 8 app

**Files:**
- Create: app skeleton via generator (replaces empty workspace)

- [ ] **Step 1: Generate the app in a temp dir, then move into the existing repo**

The existing repo at the working directory has only `docs/` and `README.md`. We need a Rails app *in this directory* without clobbering the docs. Use a temp directory then copy.

```bash
cd /tmp
rails new link-shortener-tmp \
  --database=postgresql \
  --css=tailwind \
  --javascript=importmap \
  --skip-jbuilder \
  --skip-test \
  --skip-kamal \
  --skip-rubocop
rsync -av --exclude='.git' --exclude='README.md' /tmp/link-shortener-tmp/ /Users/shijie/Documents/Personal/link-shortener/
rm -rf /tmp/link-shortener-tmp
```

- [ ] **Step 2: Pin Ruby version**

```bash
cd /Users/shijie/Documents/Personal/link-shortener
echo "3.3.6" > .ruby-version   # or current Ruby 3.x stable at execution time
```

- [ ] **Step 3: Verify the app boots**

```bash
bin/setup --skip-server
bin/rails db:prepare
bin/rails runner "puts Rails.version"
```

Expected: prints `8.0.x`, no errors.

- [ ] **Step 4: Replace the placeholder README with a stub**

`README.md` currently just says `# link-shortener`. Replace with a minimal stub (full README written in Phase 10):

```markdown
# Link Shortener

Take-home: a URL shortener built for the CoinGecko engineering assessment. See [`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md), [`docs/SPECIFICATIONS.md`](docs/SPECIFICATIONS.md), and [`docs/PLAN.md`](docs/PLAN.md).
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: bootstrap Rails 8 app with postgres + tailwind + importmap"
```

---

### Task 2: Install test + tooling gems

**Files:**
- Modify: `Gemfile`
- Create: `.rspec`, `spec/rails_helper.rb`, `spec/spec_helper.rb`, `spec/support/*.rb`

- [ ] **Step 1: Add gems to `Gemfile`**

Append inside `group :development, :test`:

```ruby
gem "rspec-rails", "~> 7.0"
gem "factory_bot_rails"
gem "shoulda-matchers"
gem "faker"
```

Append inside `group :test`:

```ruby
gem "capybara"
gem "cuprite"
gem "webmock"
gem "vcr"
gem "simplecov", require: false
```

Append at top level:

```ruby
gem "nanoid", "~> 2.0"
gem "rack-attack"
gem "brakeman", group: :development, require: false
gem "rubocop-rails-omakase", group: :development, require: false
```

- [ ] **Step 2: Install**

```bash
bundle install
```

- [ ] **Step 3: Install RSpec**

```bash
bin/rails generate rspec:install
```

- [ ] **Step 4: Configure `.rspec`**

Overwrite `.rspec`:

```
--require spec_helper
--format documentation
--color
```

- [ ] **Step 5: Configure `spec/rails_helper.rb`**

After the auto-generated requires, add:

```ruby
require "capybara/rspec"
require "capybara/cuprite"
require "webmock/rspec"
require "vcr"

Capybara.javascript_driver = :cuprite
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(app, window_size: [1200, 800], timeout: 10)
end

WebMock.disable_net_connect!(allow_localhost: true)

VCR.configure do |c|
  c.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  c.hook_into :webmock
  c.configure_rspec_metadata!
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include ActiveJob::TestHelper, type: :job
  config.include ActionDispatch::TestProcess::FixtureFile
end
```

- [ ] **Step 6: Add SimpleCov to `spec/spec_helper.rb`**

At the very top, before everything else:

```ruby
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/config/"
  add_filter "/spec/"
end
```

- [ ] **Step 7: Run the empty spec suite**

```bash
bundle exec rspec
```

Expected: `0 examples, 0 failures` — confirms RSpec wiring works.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "chore: install rspec + factory_bot + capybara + cuprite + webmock + vcr"
```

---

### Task 3: Configure Solid Queue, Cache, Cable

**Files:**
- Modify: `config/database.yml`, `config/cable.yml`, `config/cache.yml`, `config/queue.yml`, `config/environments/production.rb`, `config/puma.rb`

Rails 8 generated all three Solid gems by default. We verify the production wiring and add the in-process worker.

- [ ] **Step 1: Confirm Solid gems are in `Gemfile.lock`**

```bash
grep -E "solid_queue|solid_cache|solid_cable" Gemfile.lock
```

Expected: three matches.

- [ ] **Step 2: Set DB pool sizing in `config/database.yml`**

Replace the `default: &default` block's `pool:` line with:

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS", 5).to_i + 5 %>
```

Spec §10.3 rationale: web + jobs share the AR pool when `SOLID_QUEUE_IN_PUMA=true`.

- [ ] **Step 3: Configure Solid Queue in-Puma in production**

In `config/environments/production.rb`, add (or confirm):

```ruby
config.solid_queue.connects_to = { database: { writing: :primary } }
```

In `config/puma.rb`, after the `workers` line, add:

```ruby
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"] == "true"
```

- [ ] **Step 4: Confirm Solid Cable adapter in `config/cable.yml`**

```yaml
production:
  adapter: solid_cable
  connects_to:
    database:
      writing: primary
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

(Rails 8 generates this; verify and leave alone.)

- [ ] **Step 5: Confirm Solid Cache adapter in `config/cache.yml`**

```yaml
production:
  database: primary
  store_options:
    max_age: <%= 7.days.to_i %>
    max_size: 256.megabytes
```

- [ ] **Step 6: Migrate Solid databases**

```bash
bin/rails db:prepare
bin/rails runner "puts SolidQueue::Job.table_exists?"
bin/rails runner "puts SolidCache::Entry.table_exists?"
bin/rails runner "puts SolidCable::Message.table_exists?"
```

Expected: three `true`s. If any returns `false`, run `bin/rails db:migrate` and re-check.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: configure Solid Queue (in-puma) + Cable + Cache + DB pool sizing"
```

---

### Task 4: GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: link_shortener_test
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost:5432/link_shortener_test
      RAILS_MAX_THREADS: 5

    steps:
      - uses: actions/checkout@v4

      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true

      - run: bin/rails db:prepare

      - run: bundle exec rspec

      - run: bundle exec rubocop --no-server

      - run: bundle exec brakeman --no-pager --no-progress -q
```

- [ ] **Step 2: Verify the workflow file is valid YAML**

```bash
ruby -ryaml -e "YAML.safe_load_file('.github/workflows/ci.yml', aliases: true)"
```

Expected: no output (no error).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow (rspec + rubocop + brakeman)"
```

---

### Task 5: Tailwind base + application layout shell

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/tailwind/application.css` (or whatever the generator named it)

- [ ] **Step 1: Confirm Tailwind is wired**

```bash
bin/rails tailwindcss:build
```

Expected: builds successfully, creates `app/assets/builds/tailwind.css`.

- [ ] **Step 2: Replace `application.html.erb` with a minimal branded shell**

```erb
<!DOCTYPE html>
<html lang="en" class="h-full bg-slate-50 text-slate-900">
  <head>
    <title><%= content_for(:title) || "Link Shortener" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= yield :head %>
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>
  <body class="h-full flex flex-col">
    <header class="border-b bg-white">
      <div class="mx-auto max-w-3xl px-6 py-4 flex items-center justify-between">
        <%= link_to "Link Shortener", root_path, class: "text-lg font-semibold tracking-tight" %>
        <span class="text-xs text-slate-500">CoinGecko take-home</span>
      </div>
    </header>
    <main class="flex-1">
      <div class="mx-auto max-w-3xl px-6 py-10">
        <%= yield %>
      </div>
    </main>
    <footer class="border-t bg-white">
      <div class="mx-auto max-w-3xl px-6 py-4 text-xs text-slate-500">
        <a class="hover:underline" href="/up">Health</a> · <a class="hover:underline" href="https://github.com/sgan0420/link-shortener">Source</a>
      </div>
    </footer>
  </body>
</html>
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "ui: minimal Tailwind layout shell"
```

**End of Phase 0** — open PR `phase-0-bootstrap`. Merge after CI passes.

---

## Phase 1 — Domain models

### Task 6: `ShortLink` model

**Files:**
- Create: `db/migrate/<timestamp>_create_short_links.rb`
- Create: `app/models/short_link.rb`
- Create: `spec/models/short_link_spec.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate model ShortLink slug:string:uniq target_url:string title:string title_status:integer
```

- [ ] **Step 2: Edit the migration**

Replace the generated migration with:

```ruby
class CreateShortLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :short_links do |t|
      t.string :slug,         null: false, limit: 15
      t.string :target_url,   null: false, limit: 2048
      t.string :title,        limit: 512
      t.integer :title_status, null: false, default: 0

      t.timestamps
    end

    add_index :short_links, :slug, unique: true
    add_index :short_links, :created_at, order: { created_at: :desc }
  end
end
```

- [ ] **Step 3: Write the failing model spec**

`spec/models/short_link_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ShortLink, type: :model do
  describe "validations" do
    subject { build(:short_link) }

    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug).case_insensitive }
    it { is_expected.to validate_length_of(:slug).is_at_most(15) }
    it { is_expected.to validate_presence_of(:target_url) }
    it { is_expected.to validate_length_of(:target_url).is_at_most(2048) }

    it "rejects target_urls that are not http/https" do
      link = build(:short_link, target_url: "javascript:alert(1)")
      expect(link).not_to be_valid
      expect(link.errors[:target_url]).to be_present
    end

    it "rejects slugs that appear in RESERVED_SLUGS" do
      link = build(:short_link, slug: "stats")
      expect(link).not_to be_valid
      expect(link.errors[:slug]).to include(/reserved/i)
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:title_status).with_values(pending: 0, fetched: 1, failed: 2) }
  end

  describe ".reserved_slug?" do
    it "is true for known reserved slugs" do
      %w[up stats about admin rails assets short_links].each do |slug|
        expect(ShortLink.reserved_slug?(slug)).to be(true)
      end
    end

    it "is case-insensitive" do
      expect(ShortLink.reserved_slug?("STATS")).to be(true)
    end
  end
end
```

- [ ] **Step 4: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/models/short_link_spec.rb
```

Expected: failures because model has no validations yet.

- [ ] **Step 5: Implement `ShortLink`**

`app/models/short_link.rb`:

```ruby
class ShortLink < ApplicationRecord
  RESERVED_SLUGS = %w[up stats about admin rails assets short_links].freeze
  TARGET_URL_SCHEME = /\Ahttps?:\z/.freeze

  enum :title_status, { pending: 0, fetched: 1, failed: 2 }

  has_many :clicks, dependent: :destroy

  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { maximum: 15 }
  validates :target_url,
            presence: true,
            length: { maximum: 2048 }
  validate  :target_url_must_be_http
  validate  :slug_must_not_be_reserved

  def self.reserved_slug?(slug)
    RESERVED_SLUGS.include?(slug.to_s.downcase)
  end

  private

  def target_url_must_be_http
    return if target_url.blank?

    uri = URI.parse(target_url)
    errors.add(:target_url, "must be http or https") unless uri.scheme&.match?(TARGET_URL_SCHEME)
  rescue URI::InvalidURIError
    errors.add(:target_url, "is not a valid URL")
  end

  def slug_must_not_be_reserved
    errors.add(:slug, "is reserved") if self.class.reserved_slug?(slug)
  end
end
```

- [ ] **Step 6: Run migration + spec**

```bash
bin/rails db:migrate
bundle exec rspec spec/models/short_link_spec.rb
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(model): ShortLink with validations + reserved slugs + title_status enum"
```

---

### Task 7: `Click` model

**Files:**
- Create: `db/migrate/<timestamp>_create_clicks.rb`
- Create: `app/models/click.rb`
- Create: `spec/models/click_spec.rb`

- [ ] **Step 1: Generate**

```bash
bin/rails generate model Click short_link:references country:string city:string ip_hash:string occurred_at:datetime
```

- [ ] **Step 2: Edit the migration**

```ruby
class CreateClicks < ActiveRecord::Migration[8.0]
  def change
    create_table :clicks do |t|
      t.references :short_link, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :country, limit: 2
      t.string :city, limit: 128
      t.string :ip_hash, null: false, limit: 64
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :clicks, [:short_link_id, :occurred_at], order: { occurred_at: :desc }
    add_index :clicks, [:short_link_id, :country]
    add_index :clicks, [:short_link_id, :ip_hash]
  end
end
```

- [ ] **Step 3: Write failing spec**

`spec/models/click_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe Click, type: :model do
  it { is_expected.to belong_to(:short_link) }
  it { is_expected.to validate_presence_of(:ip_hash) }
  it { is_expected.to validate_presence_of(:occurred_at) }
  it { is_expected.to validate_length_of(:country).is_at_most(2) }
  it { is_expected.to validate_length_of(:ip_hash).is_at_most(64) }
end
```

- [ ] **Step 4: Run, confirm fails, implement**

```bash
bundle exec rspec spec/models/click_spec.rb
```

`app/models/click.rb`:

```ruby
class Click < ApplicationRecord
  belongs_to :short_link

  validates :ip_hash, presence: true, length: { maximum: 64 }
  validates :occurred_at, presence: true
  validates :country, length: { maximum: 2 }, allow_nil: true
  validates :city, length: { maximum: 128 }, allow_nil: true
end
```

- [ ] **Step 5: Migrate and run**

```bash
bin/rails db:migrate
bundle exec rspec spec/models
```

Expected: green.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(model): Click with FK + indexes for stats queries"
```

---

### Task 8: Factories

**Files:**
- Create: `spec/factories/short_links.rb`, `spec/factories/clicks.rb`

- [ ] **Step 1: Write factories**

`spec/factories/short_links.rb`:

```ruby
FactoryBot.define do
  factory :short_link do
    sequence(:slug) { |n| "slug#{n.to_s(36).rjust(3, '0')}" }
    target_url { "https://example.com/page-#{SecureRandom.hex(2)}" }
    title_status { :pending }

    trait :fetched do
      title_status { :fetched }
      title { "Example Page" }
    end

    trait :failed_title do
      title_status { :failed }
      title { nil }
    end
  end
end
```

`spec/factories/clicks.rb`:

```ruby
FactoryBot.define do
  factory :click do
    short_link
    country     { "US" }
    city        { "San Francisco" }
    ip_hash     { SecureRandom.hex(32) }
    occurred_at { Time.current }

    trait :from_country do
      transient { country_code { "GB" } }
      country { country_code }
    end
  end
end
```

- [ ] **Step 2: Smoke test in a spec**

`spec/factories_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe "factories" do
  it "builds a valid short_link" do
    expect(build(:short_link)).to be_valid
  end

  it "builds a valid click" do
    expect(build(:click)).to be_valid
  end
end
```

- [ ] **Step 3: Run**

```bash
bundle exec rspec spec/factories_spec.rb
```

Expected: green.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: factories for ShortLink and Click"
```

**End of Phase 1** — open PR `phase-1-models`.

---

## Phase 2 — Service objects

### Task 9: `UrlShortener` service

**Files:**
- Create: `app/services/url_shortener.rb`
- Create: `spec/services/url_shortener_spec.rb`

- [ ] **Step 1: Write failing spec**

```ruby
require "rails_helper"

RSpec.describe UrlShortener do
  describe ".call" do
    it "returns a persisted ShortLink with a 7-char slug" do
      result = described_class.call(target_url: "https://example.com")
      expect(result).to be_a(ShortLink)
      expect(result).to be_persisted
      expect(result.slug.length).to eq(7)
      expect(result.target_url).to eq("https://example.com")
      expect(result).to be_pending  # title_status
    end

    it "raises ValidationError on invalid url" do
      expect {
        described_class.call(target_url: "javascript:alert(1)")
      }.to raise_error(UrlShortener::ValidationError)
    end

    it "raises ValidationError on blank url" do
      expect {
        described_class.call(target_url: "")
      }.to raise_error(UrlShortener::ValidationError)
    end

    it "retries on slug collision and eventually succeeds" do
      allow(Nanoid).to receive(:generate).and_return("dup0001", "dup0001", "fresh01")
      create(:short_link, slug: "dup0001")
      result = described_class.call(target_url: "https://example.com/another")
      expect(result.slug).to eq("fresh01")
    end

    it "raises CollisionExhaustedError after 3 collisions" do
      allow(Nanoid).to receive(:generate).and_return("collide", "collide", "collide")
      create(:short_link, slug: "collide")
      expect {
        described_class.call(target_url: "https://example.com/x")
      }.to raise_error(UrlShortener::CollisionExhaustedError)
    end
  end
end
```

- [ ] **Step 2: Run, confirm fails**

```bash
bundle exec rspec spec/services/url_shortener_spec.rb
```

- [ ] **Step 3: Implement**

```ruby
class UrlShortener
  SLUG_LENGTH = 7
  MAX_ATTEMPTS = 3

  class ValidationError < StandardError; end
  class CollisionExhaustedError < StandardError; end

  def self.call(target_url:)
    new(target_url: target_url).call
  end

  def initialize(target_url:)
    @target_url = target_url.to_s.strip
  end

  def call
    raise ValidationError, "target_url is required" if @target_url.empty?

    MAX_ATTEMPTS.times do
      link = ShortLink.new(slug: Nanoid.generate(size: SLUG_LENGTH), target_url: @target_url, title_status: :pending)
      if link.save
        return link
      else
        if link.errors.of_kind?(:slug, :taken)
          next
        elsif link.errors.any?
          raise ValidationError, link.errors.full_messages.join(", ")
        end
      end
    end

    raise CollisionExhaustedError, "could not generate unique slug after #{MAX_ATTEMPTS} attempts"
  end
end
```

- [ ] **Step 4: Run, confirm green**

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(service): UrlShortener with nanoid slug + collision retry + typed errors"
```

---

### Task 10: `TitleFetcher` service (with SSRF guard)

**Files:**
- Create: `app/services/title_fetcher.rb`
- Create: `spec/services/title_fetcher_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe TitleFetcher do
  describe ".call" do
    it "returns the parsed <title>" do
      stub_request(:get, "https://example.com/page")
        .to_return(status: 200, body: "<html><head><title>  Hello  World  </title></head></html>",
                   headers: { "Content-Type" => "text/html" })

      result = described_class.call(url: "https://example.com/page")
      expect(result.ok?).to be(true)
      expect(result.title).to eq("Hello World")
    end

    it "returns ok=false on missing <title>" do
      stub_request(:get, "https://example.com/notitle")
        .to_return(status: 200, body: "<html><head></head></html>")
      result = described_class.call(url: "https://example.com/notitle")
      expect(result.ok?).to be(false)
    end

    it "truncates very long titles to 512 chars" do
      long = "a" * 1000
      stub_request(:get, "https://example.com/long")
        .to_return(status: 200, body: "<html><head><title>#{long}</title></head></html>")
      result = described_class.call(url: "https://example.com/long")
      expect(result.title.length).to eq(512)
    end

    it "raises PrivateAddressError when hostname resolves to a private IP" do
      allow(Resolv).to receive(:getaddresses).with("internal.local").and_return(["10.0.0.1"])
      expect {
        described_class.call(url: "https://internal.local/x")
      }.to raise_error(TitleFetcher::PrivateAddressError)
    end

    it "raises PrivateAddressError for loopback" do
      allow(Resolv).to receive(:getaddresses).with("localhost").and_return(["127.0.0.1"])
      expect {
        described_class.call(url: "http://localhost/x")
      }.to raise_error(TitleFetcher::PrivateAddressError)
    end

    it "returns ok=false on HTTP timeout" do
      stub_request(:get, "https://example.com/slow").to_timeout
      result = described_class.call(url: "https://example.com/slow")
      expect(result.ok?).to be(false)
      expect(result.reason).to match(/timeout|timed out/i)
    end
  end
end
```

- [ ] **Step 2: Implement**

```ruby
require "nokogiri"
require "resolv"
require "ipaddr"
require "net/http"

class TitleFetcher
  class PrivateAddressError < StandardError; end

  Result = Struct.new(:ok, :title, :reason, keyword_init: true) do
    alias_method :ok?, :ok
  end

  MAX_TITLE_LENGTH    = 512
  HTTP_OPEN_TIMEOUT   = 5
  HTTP_READ_TIMEOUT   = 5
  MAX_BODY_BYTES      = 1.megabyte
  MAX_REDIRECTS       = 3

  PRIVATE_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 127.0.0.0/8 169.254.0.0/16
    172.16.0.0/12 192.168.0.0/16 224.0.0.0/4
    ::1/128 fc00::/7 fe80::/10
  ].map { |r| IPAddr.new(r) }

  def self.call(url:)
    new(url).call
  end

  def initialize(url)
    @url = url
  end

  def call
    uri = URI.parse(@url)
    guard_against_private_address!(uri.host)
    Result.new(ok: true, title: fetch_title(uri))
  rescue PrivateAddressError
    raise
  rescue StandardError => e
    Result.new(ok: false, reason: "#{e.class}: #{e.message}")
  end

  private

  def guard_against_private_address!(host)
    addresses = Resolv.getaddresses(host)
    raise PrivateAddressError, "no addresses for #{host}" if addresses.empty?

    addresses.each do |addr|
      ip = IPAddr.new(addr)
      if PRIVATE_RANGES.any? { |r| r.include?(ip) }
        raise PrivateAddressError, "private address: #{addr}"
      end
    end
  end

  def fetch_title(uri, redirects_left: MAX_REDIRECTS)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = HTTP_OPEN_TIMEOUT
    http.read_timeout = HTTP_READ_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "LinkShortener/1.0")
    response = http.request(request)

    case response
    when Net::HTTPRedirection
      raise "too many redirects" if redirects_left <= 0
      new_uri = URI.parse(response["location"])
      guard_against_private_address!(new_uri.host)
      fetch_title(new_uri, redirects_left: redirects_left - 1)
    when Net::HTTPSuccess
      body = response.body.to_s.byteslice(0, MAX_BODY_BYTES)
      doc  = Nokogiri::HTML(body)
      raw  = doc.at_css("title")&.text.to_s.squish
      raise "no title element" if raw.empty?
      raw.first(MAX_TITLE_LENGTH)
    else
      raise "http #{response.code}"
    end
  end
end
```

- [ ] **Step 3: Run, fix, green**

```bash
bundle exec rspec spec/services/title_fetcher_spec.rb
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(service): TitleFetcher with SSRF guard + timeouts + redirect cap"
```

---

### Task 11: `GeolocationService` (cache + fallback)

**Files:**
- Create: `app/services/geolocation_service.rb`
- Create: `spec/services/geolocation_service_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe GeolocationService do
  before { Rails.cache.clear }

  describe ".lookup" do
    it "returns Unknown for private/loopback IPs without HTTP" do
      result = described_class.lookup("127.0.0.1")
      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
      expect(result.city).to be_nil
      expect(WebMock).not_to have_requested(:any, /ipapi/)
    end

    it "calls ipapi for public IPs" do
      stub_request(:get, "https://ipapi.co/8.8.8.8/json/")
        .to_return(status: 200, body: { country_code: "US", city: "Mountain View" }.to_json)

      result = described_class.lookup("8.8.8.8")
      expect(result.country).to eq("US")
      expect(result.city).to eq("Mountain View")
    end

    it "caches results by IP" do
      stub_request(:get, "https://ipapi.co/8.8.8.8/json/")
        .to_return(status: 200, body: { country_code: "US", city: "MV" }.to_json)

      2.times { described_class.lookup("8.8.8.8") }
      expect(WebMock).to have_requested(:get, "https://ipapi.co/8.8.8.8/json/").once
    end

    it "returns Unknown on timeout" do
      stub_request(:get, %r{https://ipapi.co/.*}).to_timeout
      result = described_class.lookup("8.8.8.8")
      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
    end

    it "returns Unknown on 5xx" do
      stub_request(:get, %r{https://ipapi.co/.*}).to_return(status: 503)
      result = described_class.lookup("8.8.8.8")
      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
    end
  end
end
```

- [ ] **Step 2: Implement**

```ruby
require "net/http"
require "ipaddr"

class GeolocationService
  Result = Struct.new(:country, :city, keyword_init: true)

  UNKNOWN_COUNTRY = "ZZ"  # ISO 3166-1 user-assigned code for unknown
  TIMEOUT         = 2
  CACHE_TTL       = 24.hours

  PRIVATE_RANGES = TitleFetcher::PRIVATE_RANGES

  def self.lookup(ip)
    new(ip).lookup
  end

  def initialize(ip)
    @ip = ip.to_s
  end

  def lookup
    return unknown if private_or_invalid?

    Rails.cache.fetch("geo:#{@ip}", expires_in: CACHE_TTL) do
      fetch_remote || unknown
    end
  end

  private

  def private_or_invalid?
    return true if @ip.empty?
    addr = IPAddr.new(@ip)
    PRIVATE_RANGES.any? { |r| r.include?(addr) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def fetch_remote
    uri = URI.parse("#{base_url}/#{@ip}/json/")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    response = http.request(Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "LinkShortener/1.0"))
    return nil unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    Result.new(country: payload["country_code"].presence || UNKNOWN_COUNTRY, city: payload["city"].presence)
  rescue StandardError
    nil
  end

  def unknown
    Result.new(country: UNKNOWN_COUNTRY, city: nil)
  end

  def base_url
    ENV.fetch("IPAPI_BASE_URL", "https://ipapi.co")
  end
end
```

- [ ] **Step 3: Configure dev cache**

In `config/environments/development.rb`, ensure `config.cache_store = :memory_store` is set so `Rails.cache.fetch` works in dev tests. In test env (`config/environments/test.rb`) it defaults to `:null_store` — override to `:memory_store` so the cache-test passes:

```ruby
config.cache_store = :memory_store
```

- [ ] **Step 4: Green**

```bash
bundle exec rspec spec/services/geolocation_service_spec.rb
```

- [ ] **Step 5: VCR contract spec (one-time, for ipapi.co response shape)**

`spec/services/geolocation_service_contract_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe GeolocationService, :vcr do
  it "parses a real ipapi.co response", vcr: { cassette_name: "ipapi_8_8_8_8" } do
    WebMock.allow_net_connect!
    result = described_class.lookup("8.8.8.8")
    expect(result.country).to match(/\A[A-Z]{2}\z/)
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
```

Run once to record cassette, then commit the cassette.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(service): GeolocationService with cache, private-IP shortcut, graceful fallback"
```

**End of Phase 2** — open PR `phase-2-services`.

---

## Phase 3 — Background jobs

### Task 12: `FetchTitleJob`

**Files:**
- Create: `app/jobs/fetch_title_job.rb`
- Create: `spec/jobs/fetch_title_job_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe FetchTitleJob, type: :job do
  let(:short_link) { create(:short_link, target_url: "https://example.com") }

  it "updates short_link with the fetched title" do
    allow(TitleFetcher).to receive(:call).with(url: short_link.target_url)
      .and_return(TitleFetcher::Result.new(ok: true, title: "Example Page"))

    described_class.perform_now(short_link.id)

    short_link.reload
    expect(short_link.title).to eq("Example Page")
    expect(short_link).to be_fetched
  end

  it "marks failed when fetch returns ok=false" do
    allow(TitleFetcher).to receive(:call)
      .and_return(TitleFetcher::Result.new(ok: false, reason: "boom"))

    described_class.perform_now(short_link.id)

    expect(short_link.reload).to be_failed
  end

  it "discards on PrivateAddressError" do
    allow(TitleFetcher).to receive(:call).and_raise(TitleFetcher::PrivateAddressError)
    expect {
      described_class.perform_now(short_link.id)
    }.not_to raise_error
    expect(short_link.reload).to be_failed
  end

  it "broadcasts a Turbo Stream replace on success" do
    allow(TitleFetcher).to receive(:call)
      .and_return(TitleFetcher::Result.new(ok: true, title: "Example Page"))
    expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      .with(short_link, target: ActionView::RecordIdentifier.dom_id(short_link, :title),
            partial: "short_links/title", locals: hash_including(short_link: anything))

    described_class.perform_now(short_link.id)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class FetchTitleJob < ApplicationJob
  queue_as :default

  discard_on TitleFetcher::PrivateAddressError do |job, _error|
    ShortLink.find_by(id: job.arguments.first)&.update(title_status: :failed)
  end

  discard_on ActiveJob::DeserializationError

  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    ShortLink.find_by(id: job.arguments.first)&.update(title_status: :failed)
    broadcast(ShortLink.find_by(id: job.arguments.first))
  end

  def perform(short_link_id)
    short_link = ShortLink.find_by(id: short_link_id)
    return unless short_link

    result = TitleFetcher.call(url: short_link.target_url)

    if result.ok?
      short_link.update!(title: result.title, title_status: :fetched)
    else
      short_link.update!(title_status: :failed)
    end

    self.class.broadcast(short_link)
  end

  def self.broadcast(short_link)
    return unless short_link
    Turbo::StreamsChannel.broadcast_replace_to(
      short_link,
      target: ActionView::RecordIdentifier.dom_id(short_link, :title),
      partial: "short_links/title",
      locals: { short_link: short_link }
    )
  end
end
```

- [ ] **Step 3: Run, green**

```bash
bundle exec rspec spec/jobs/fetch_title_job_spec.rb
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(job): FetchTitleJob with retries, discard, Turbo Stream broadcast"
```

---

### Task 13: `RecordClickJob`

**Files:**
- Create: `app/jobs/record_click_job.rb`
- Create: `spec/jobs/record_click_job_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe RecordClickJob, type: :job do
  let(:short_link) { create(:short_link) }
  let(:occurred_at) { Time.current }

  before do
    ENV["CLICK_IP_SALT"] = "test-salt"
    allow(GeolocationService).to receive(:lookup).with("8.8.8.8")
      .and_return(GeolocationService::Result.new(country: "US", city: "Mountain View"))
  end

  it "creates a Click row with hashed IP" do
    expect {
      described_class.perform_now(short_link.id, "8.8.8.8", occurred_at.iso8601)
    }.to change(Click, :count).by(1)

    click = Click.last
    expect(click.short_link).to eq(short_link)
    expect(click.country).to eq("US")
    expect(click.city).to eq("Mountain View")
    expect(click.ip_hash).to eq(Digest::SHA256.hexdigest("8.8.8.8test-salt"))
    expect(click.occurred_at).to be_within(1.second).of(occurred_at)
  end

  it "uses Unknown when geolocation fails" do
    allow(GeolocationService).to receive(:lookup)
      .and_return(GeolocationService::Result.new(country: "ZZ", city: nil))

    described_class.perform_now(short_link.id, "8.8.8.8", occurred_at.iso8601)
    expect(Click.last.country).to eq("ZZ")
  end

  it "does nothing if the short_link no longer exists" do
    expect {
      described_class.perform_now(999_999, "8.8.8.8", occurred_at.iso8601)
    }.not_to change(Click, :count)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class RecordClickJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(short_link_id, ip, occurred_at_iso)
    return unless ShortLink.where(id: short_link_id).exists?

    geo = GeolocationService.lookup(ip)
    Click.create!(
      short_link_id: short_link_id,
      country: geo.country,
      city: geo.city,
      ip_hash: Digest::SHA256.hexdigest("#{ip}#{ENV.fetch('CLICK_IP_SALT', '')}"),
      occurred_at: Time.iso8601(occurred_at_iso)
    )
  end
end
```

- [ ] **Step 3: Run, green, commit**

```bash
bundle exec rspec spec/jobs/record_click_job_spec.rb
git add -A
git commit -m "feat(job): RecordClickJob with geo lookup + salted IP hash"
```

**End of Phase 3** — open PR `phase-3-jobs`.

---

## Phase 4 — Query objects

### Task 14: `ShortLinkStatsQuery`

**Files:**
- Create: `app/queries/short_link_stats_query.rb`
- Create: `spec/queries/short_link_stats_query_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe ShortLinkStatsQuery do
  let(:link) { create(:short_link) }

  it "returns zeroed stats for a link with no clicks" do
    result = described_class.new(link).call
    expect(result.total_clicks).to eq(0)
    expect(result.first_at).to be_nil
    expect(result.last_at).to be_nil
    expect(result.by_country).to eq([])
  end

  it "aggregates by country, ordered by count desc" do
    create_list(:click, 3, short_link: link, country: "US")
    create_list(:click, 1, short_link: link, country: "GB")
    create_list(:click, 2, short_link: link, country: "JP")

    result = described_class.new(link).call
    expect(result.total_clicks).to eq(6)
    expect(result.by_country.map(&:country)).to eq(%w[US JP GB])
    expect(result.by_country.map(&:count)).to eq([3, 2, 1])
  end

  it "reports first and last click timestamps" do
    create(:click, short_link: link, occurred_at: 2.days.ago)
    create(:click, short_link: link, occurred_at: 1.hour.ago)
    result = described_class.new(link).call
    expect(result.first_at).to be_within(1.minute).of(2.days.ago)
    expect(result.last_at).to be_within(1.minute).of(1.hour.ago)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class ShortLinkStatsQuery
  Result        = Struct.new(:total_clicks, :first_at, :last_at, :by_country, keyword_init: true)
  CountryBucket = Struct.new(:country, :count, keyword_init: true)

  def initialize(short_link)
    @short_link = short_link
  end

  def call
    clicks = @short_link.clicks
    Result.new(
      total_clicks: clicks.count,
      first_at:     clicks.minimum(:occurred_at),
      last_at:      clicks.maximum(:occurred_at),
      by_country:   country_buckets(clicks)
    )
  end

  private

  def country_buckets(clicks)
    clicks.group(:country).order(Arel.sql("count(*) DESC")).count.map do |country, count|
      CountryBucket.new(country: country || "ZZ", count: count)
    end
  end
end
```

- [ ] **Step 3: Run, green, commit**

```bash
bundle exec rspec spec/queries/short_link_stats_query_spec.rb
git add -A
git commit -m "feat(query): ShortLinkStatsQuery (totals + country breakdown + first/last)"
```

---

### Task 15: `RecentClicksQuery`

**Files:**
- Create: `app/queries/recent_clicks_query.rb`
- Create: `spec/queries/recent_clicks_query_spec.rb`

- [ ] **Step 1: Failing spec**

```ruby
require "rails_helper"

RSpec.describe RecentClicksQuery do
  let(:link) { create(:short_link) }

  it "returns clicks ordered by occurred_at desc" do
    older = create(:click, short_link: link, occurred_at: 2.days.ago)
    newer = create(:click, short_link: link, occurred_at: 1.hour.ago)

    result = described_class.new(link).call
    expect(result.to_a).to eq([newer, older])
  end

  it "caps to limit" do
    create_list(:click, 5, short_link: link)
    result = described_class.new(link).call(limit: 2)
    expect(result.count).to eq(2)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class RecentClicksQuery
  def initialize(short_link)
    @short_link = short_link
  end

  def call(limit: 50)
    @short_link.clicks.order(occurred_at: :desc).limit(limit)
  end
end
```

- [ ] **Step 3: Run, green, commit**

```bash
bundle exec rspec spec/queries/recent_clicks_query_spec.rb
git add -A
git commit -m "feat(query): RecentClicksQuery"
```

**End of Phase 4** — open PR `phase-4-queries`.

---

## Phase 5 — Presenters

### Task 16: `ShortLinkPresenter` and `ClickPresenter`

**Files:**
- Create: `app/presenters/short_link_presenter.rb`, `app/presenters/click_presenter.rb`
- Create: `spec/presenters/short_link_presenter_spec.rb`, `spec/presenters/click_presenter_spec.rb`

- [ ] **Step 1: Failing presenter specs**

`spec/presenters/short_link_presenter_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ShortLinkPresenter do
  let(:link) { build(:short_link, slug: "abc1234", target_url: "https://example.com/path") }
  subject(:presenter) { described_class.new(link, host: "example.test") }

  describe "#short_url" do
    it "returns the public-facing short URL" do
      expect(presenter.short_url).to eq("https://example.test/abc1234")
    end
  end

  describe "#display_target" do
    it "truncates very long target URLs" do
      link.target_url = "https://example.com/" + ("x" * 200)
      expect(presenter.display_target.length).to be <= 80
      expect(presenter.display_target).to end_with("…")
    end
  end

  describe "#title_label" do
    it "shows the title when fetched" do
      link.title = "Hello"
      link.title_status = :fetched
      expect(presenter.title_label).to eq("Hello")
    end

    it "shows fetching placeholder when pending" do
      link.title_status = :pending
      expect(presenter.title_label).to match(/Fetching/i)
    end

    it "shows unavailable when failed" do
      link.title_status = :failed
      expect(presenter.title_label).to match(/unavailable/i)
    end
  end
end
```

`spec/presenters/click_presenter_spec.rb`:

```ruby
require "rails_helper"

RSpec.describe ClickPresenter do
  let(:click) { build(:click, country: "US", city: "Mountain View",
                              ip_hash: "abcdef1234567890" * 4,
                              occurred_at: Time.utc(2026, 5, 17, 14, 30)) }
  subject(:presenter) { described_class.new(click) }

  it "formats location as 'City, CC'" do
    expect(presenter.location).to eq("Mountain View, US")
  end

  it "falls back to country only when city missing" do
    click.city = nil
    expect(presenter.location).to eq("US")
  end

  it "shows 'Unknown' when both missing" do
    click.country = nil
    click.city = nil
    expect(presenter.location).to eq("Unknown")
  end

  it "masks the ip hash to first 8 chars" do
    expect(presenter.ip_mask).to eq("abcdef12…")
  end

  it "formats occurred_at" do
    expect(presenter.occurred_at).to eq("2026-05-17 14:30 UTC")
  end
end
```

- [ ] **Step 2: Implement**

`app/presenters/short_link_presenter.rb`:

```ruby
class ShortLinkPresenter
  MAX_TARGET_DISPLAY = 80

  def initialize(short_link, host: ENV.fetch("APP_HOST", "localhost:3000"), scheme: ENV.fetch("APP_SCHEME", "https"))
    @link = short_link
    @host = host
    @scheme = scheme
  end

  def short_url
    "#{@scheme}://#{@host}/#{@link.slug}"
  end

  def display_target
    return @link.target_url if @link.target_url.length <= MAX_TARGET_DISPLAY
    @link.target_url.first(MAX_TARGET_DISPLAY - 1) + "…"
  end

  def title_label
    case @link.title_status.to_s
    when "fetched"
      @link.title
    when "failed"
      "Title unavailable"
    else
      "Fetching title…"
    end
  end
end
```

`app/presenters/click_presenter.rb`:

```ruby
class ClickPresenter
  def initialize(click)
    @click = click
  end

  def location
    if @click.city.present? && @click.country.present?
      "#{@click.city}, #{@click.country}"
    elsif @click.country.present?
      @click.country
    else
      "Unknown"
    end
  end

  def ip_mask
    "#{@click.ip_hash.to_s.first(8)}…"
  end

  def occurred_at
    @click.occurred_at.utc.strftime("%Y-%m-%d %H:%M UTC")
  end
end
```

- [ ] **Step 3: Configure Rails autoload for `app/services`, `app/queries`, `app/presenters`**

Rails 8 auto-loads any folder under `app/`, so this is automatic. Verify by:

```bash
bin/rails runner "puts UrlShortener, TitleFetcher, GeolocationService, ShortLinkStatsQuery, RecentClicksQuery, ShortLinkPresenter, ClickPresenter"
```

Expected: seven class names printed, no errors.

- [ ] **Step 4: Run, green, commit**

```bash
bundle exec rspec spec/presenters
git add -A
git commit -m "feat(presenters): ShortLinkPresenter + ClickPresenter for view formatting"
```

**End of Phase 5** — open PR `phase-5-presenters`.

---

## Phase 6 — Routes and controllers

### Task 17: Routes + routing spec

**Files:**
- Modify: `config/routes.rb`
- Create: `spec/routing/short_link_routing_spec.rb`

- [ ] **Step 1: Failing routing spec**

```ruby
require "rails_helper"

RSpec.describe "ShortLink routing" do
  it "routes the form root" do
    expect(get: "/").to route_to(controller: "short_links", action: "new")
  end

  it "routes POST /short_links to create" do
    expect(post: "/short_links").to route_to(controller: "short_links", action: "create")
  end

  it "routes GET /:slug/stats to stats#show before /:slug catches it" do
    expect(get: "/abc1234/stats").to route_to(controller: "stats", action: "show", slug: "abc1234")
  end

  it "routes GET /:slug to redirects#show" do
    expect(get: "/abc1234").to route_to(controller: "redirects", action: "show", slug: "abc1234")
  end

  it "does not match /:slug with > 15 chars" do
    expect(get: "/" + "a" * 16).not_to be_routable
  end
end
```

- [ ] **Step 2: Edit `config/routes.rb`**

```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "short_links#new"
  post "short_links" => "short_links#create"

  constraints slug: /[A-Za-z0-9_-]{1,15}/ do
    get ":slug/stats" => "stats#show",     as: :stats
    get ":slug"       => "redirects#show", as: :short_link
  end
end
```

- [ ] **Step 3: Run, green, commit**

```bash
bundle exec rspec spec/routing
git add -A
git commit -m "feat(routing): root + create + redirect + stats; constrained to 15-char slug"
```

---

### Task 18: `ShortLinksController` (new + create) + request spec

**Files:**
- Create: `app/controllers/short_links_controller.rb`
- Create: `spec/requests/short_links_spec.rb`

- [ ] **Step 1: Failing request spec**

```ruby
require "rails_helper"

RSpec.describe "ShortLinks", type: :request do
  describe "GET /" do
    it "renders the form" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Shorten")
    end
  end

  describe "POST /short_links" do
    it "creates a ShortLink and renders Turbo Stream" do
      expect {
        post "/short_links",
             params: { short_link: { target_url: "https://example.com" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change(ShortLink, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("Fetching title")
    end

    it "enqueues FetchTitleJob" do
      expect {
        post "/short_links",
             params: { short_link: { target_url: "https://example.com" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to have_enqueued_job(FetchTitleJob)
    end

    it "returns 422 turbo stream on invalid input" do
      post "/short_links",
           params: { short_link: { target_url: "javascript:alert(1)" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/must be http or https/i)
    end
  end
end
```

- [ ] **Step 2: Implement controller**

```ruby
class ShortLinksController < ApplicationController
  def new
    @short_link = ShortLink.new
  end

  def create
    @short_link = UrlShortener.call(target_url: params.dig(:short_link, :target_url))
    FetchTitleJob.perform_later(@short_link.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  rescue UrlShortener::ValidationError => e
    @short_link = ShortLink.new(target_url: params.dig(:short_link, :target_url))
    @short_link.errors.add(:target_url, e.message)
    respond_to do |format|
      format.turbo_stream { render :create_error, status: :unprocessable_entity }
      format.html { redirect_to root_path, alert: e.message }
    end
  rescue UrlShortener::CollisionExhaustedError
    respond_to do |format|
      format.turbo_stream { render :create_collision_exhausted, status: :service_unavailable }
      format.html { redirect_to root_path, alert: "Please try again." }
    end
  end
end
```

Views referenced (`new.html.erb`, `create.turbo_stream.erb`, `create_error.turbo_stream.erb`, `create_collision_exhausted.turbo_stream.erb`) are added in Phase 7. The request spec for now only asserts response semantics that hold once views exist — so Phase 6 commits will have failing system-level views; we land them in 7 before merging the umbrella PR.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(controller): ShortLinksController#new + #create with Turbo Stream + error branches"
```

---

### Task 19: `RedirectsController` + request spec

**Files:**
- Create: `app/controllers/redirects_controller.rb`
- Create: `spec/requests/redirects_spec.rb`

- [ ] **Step 1: Failing request spec**

```ruby
require "rails_helper"

RSpec.describe "Redirects", type: :request do
  let!(:link) { create(:short_link, :fetched, slug: "abc1234", target_url: "https://example.com/page") }

  it "redirects to the target url with 302" do
    get "/abc1234"
    expect(response).to have_http_status(:found)
    expect(response.location).to eq("https://example.com/page")
  end

  it "enqueues RecordClickJob" do
    expect {
      get "/abc1234", env: { "REMOTE_ADDR" => "8.8.8.8" }
    }.to have_enqueued_job(RecordClickJob).with(link.id, "8.8.8.8", a_kind_of(String))
  end

  it "renders branded 404 on unknown slug" do
    get "/nope999"
    expect(response).to have_http_status(:not_found)
    expect(response.body).to match(/not found/i)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class RedirectsController < ApplicationController
  def show
    link = ShortLink.find_by!(slug: params[:slug])
    occurred_at = Time.current
    RecordClickJob.perform_later(link.id, request.remote_ip, occurred_at.iso8601)
    redirect_to link.target_url, status: :found, allow_other_host: true
  end
end
```

- [ ] **Step 3: Add `ApplicationController` rescue for RecordNotFound (used by Redirects + Stats)**

`app/controllers/application_controller.rb`:

```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private

  def render_not_found
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found }
      format.any  { head :not_found }
    end
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat(controller): RedirectsController + 404 handler"
```

---

### Task 20: `StatsController` + request spec

**Files:**
- Create: `app/controllers/stats_controller.rb`
- Create: `spec/requests/stats_spec.rb`

- [ ] **Step 1: Failing request spec**

```ruby
require "rails_helper"

RSpec.describe "Stats", type: :request do
  let(:link) { create(:short_link, :fetched, slug: "abc1234") }

  it "renders the stats page" do
    create_list(:click, 3, short_link: link, country: "US")
    create(:click, short_link: link, country: "GB")

    get "/abc1234/stats"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("4")            # total clicks
    expect(response.body).to include("US")
    expect(response.body).to include("GB")
  end

  it "404s on missing slug" do
    get "/nope999/stats"
    expect(response).to have_http_status(:not_found)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class StatsController < ApplicationController
  def show
    @short_link = ShortLink.find_by!(slug: params[:slug])
    @stats      = ShortLinkStatsQuery.new(@short_link).call
    @recents    = RecentClicksQuery.new(@short_link).call(limit: 50)
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(controller): StatsController loading stats + recent clicks"
```

---

### Task 21: `ErrorsController` and 404 page

**Files:**
- Create: `app/controllers/errors_controller.rb`
- Create: `app/views/errors/not_found.html.erb`

- [ ] **Step 1: View**

```erb
<% content_for :title, "Not found · Link Shortener" %>
<div class="text-center py-20">
  <p class="text-sm uppercase tracking-wider text-slate-500">404</p>
  <h1 class="mt-2 text-3xl font-semibold">We couldn't find that link.</h1>
  <p class="mt-4 text-slate-600">It may have been mistyped, or never existed.</p>
  <p class="mt-8">
    <%= link_to "Shorten a new link", root_path,
        class: "inline-flex items-center rounded-md bg-slate-900 px-4 py-2 text-white text-sm font-medium hover:bg-slate-700" %>
  </p>
</div>
```

- [ ] **Step 2: Controller (currently no actions needed — view is rendered by ApplicationController rescue)**

```ruby
class ErrorsController < ApplicationController
  def not_found
    render :not_found, status: :not_found
  end
end
```

(Hooked into routes only if we want a static `/404` for crawlers; otherwise the rescue handles it.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "ui: branded 404 page"
```

**End of Phase 6** — note Phase 7 must follow before this PR is mergeable (views referenced by ShortLinksController don't exist yet). Either open a combined Phase 6+7 PR or hold Phase 6 PR until 7 lands.

---

## Phase 7 — Views, Turbo Streams, system spec

### Task 22: `ShortLinks#new` view (form)

**Files:**
- Create: `app/views/short_links/new.html.erb`
- Create: `app/views/short_links/_form.html.erb`

- [ ] **Step 1: Write `_form.html.erb`**

```erb
<%= form_with model: short_link, url: short_links_path, id: "shortener-form",
              class: "space-y-4", data: { turbo_frame: "_top" } do |f| %>
  <% if short_link.errors.any? %>
    <div role="alert" class="rounded-md border border-red-300 bg-red-50 px-4 py-3 text-sm text-red-800">
      <%= short_link.errors.full_messages.to_sentence %>
    </div>
  <% end %>

  <div>
    <%= f.label :target_url, "Long URL", class: "block text-sm font-medium text-slate-700" %>
    <%= f.url_field :target_url,
        placeholder: "https://example.com/very/long/path",
        required: true,
        class: "mt-1 block w-full rounded-md border border-slate-300 bg-white px-3 py-2 shadow-sm focus:border-slate-900 focus:ring-slate-900 sm:text-sm" %>
  </div>

  <%= f.submit "Shorten",
      class: "inline-flex items-center rounded-md bg-slate-900 px-4 py-2 text-white text-sm font-medium hover:bg-slate-700 disabled:opacity-50" %>
<% end %>
```

- [ ] **Step 2: Write `new.html.erb`**

```erb
<% content_for :title, "Shorten a link" %>
<section>
  <h1 class="text-2xl font-semibold tracking-tight">Shorten a link</h1>
  <p class="mt-1 text-sm text-slate-600">Paste a long URL and get a short one back.</p>
  <div class="mt-6 rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
    <%= render "form", short_link: @short_link %>
  </div>
  <div id="results" class="mt-8 space-y-4"></div>
</section>
```

- [ ] **Step 3: Manual smoke**

```bash
bin/dev
# visit http://localhost:3000, submit a URL, observe form behavior (no Turbo Stream wired yet — will refresh)
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "ui: shorten form and results container"
```

---

### Task 23: `ShortLinks#create` Turbo Stream + result card

**Files:**
- Create: `app/views/short_links/create.turbo_stream.erb`
- Create: `app/views/short_links/_result_card.html.erb`
- Create: `app/views/short_links/_title.html.erb`
- Create: `app/views/short_links/create_error.turbo_stream.erb`
- Create: `app/views/short_links/create_collision_exhausted.turbo_stream.erb`

- [ ] **Step 1: `_title.html.erb`**

```erb
<% presenter = ShortLinkPresenter.new(short_link, host: request.host_with_port, scheme: request.scheme) %>
<span id="<%= dom_id(short_link, :title) %>" class="text-sm text-slate-600">
  <%= presenter.title_label %>
</span>
```

- [ ] **Step 2: `_result_card.html.erb`**

```erb
<% presenter = ShortLinkPresenter.new(short_link, host: request.host_with_port, scheme: request.scheme) %>
<article id="<%= dom_id(short_link) %>"
         class="rounded-lg border border-slate-200 bg-white p-5 shadow-sm">
  <%= turbo_stream_from short_link %>

  <div class="flex items-baseline justify-between">
    <a href="<%= presenter.short_url %>" target="_blank" rel="noopener"
       class="text-lg font-mono text-slate-900 underline">
      <%= presenter.short_url %>
    </a>
    <%= link_to "View stats", stats_path(slug: short_link.slug),
        class: "text-sm text-slate-500 hover:text-slate-900" %>
  </div>
  <p class="mt-1 truncate text-sm text-slate-500"><%= presenter.display_target %></p>
  <p class="mt-3"><%= render "title", short_link: short_link %></p>
</article>
```

- [ ] **Step 3: `create.turbo_stream.erb`**

```erb
<%= turbo_stream.append "results" do %>
  <%= render "result_card", short_link: @short_link %>
<% end %>
<%= turbo_stream.replace "shortener-form" do %>
  <%= render "form", short_link: ShortLink.new %>
<% end %>
```

- [ ] **Step 4: `create_error.turbo_stream.erb`**

```erb
<%= turbo_stream.replace "shortener-form" do %>
  <%= render "form", short_link: @short_link %>
<% end %>
```

- [ ] **Step 5: `create_collision_exhausted.turbo_stream.erb`**

```erb
<%= turbo_stream.prepend "results" do %>
  <div role="alert" class="rounded-md border border-amber-300 bg-amber-50 px-4 py-3 text-sm text-amber-900">
    Couldn't generate a unique short URL right now. Please retry.
  </div>
<% end %>
```

- [ ] **Step 6: Verify request spec from Task 18 is now green**

```bash
bundle exec rspec spec/requests/short_links_spec.rb
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "ui: Turbo Stream result card + title slot + error variants"
```

---

### Task 24: Stats view

**Files:**
- Create: `app/views/stats/show.html.erb`

- [ ] **Step 1: View**

```erb
<% content_for :title, "Stats · #{@short_link.slug} · Link Shortener" %>
<% presenter = ShortLinkPresenter.new(@short_link, host: request.host_with_port, scheme: request.scheme) %>

<section class="space-y-8">
  <header class="flex items-baseline justify-between">
    <div>
      <h1 class="text-2xl font-semibold tracking-tight"><%= presenter.short_url %></h1>
      <p class="mt-1 truncate text-sm text-slate-500"><%= presenter.display_target %></p>
    </div>
    <%= link_to "← Shorten another", root_path, class: "text-sm text-slate-500 hover:text-slate-900" %>
  </header>

  <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
    <div class="rounded-lg border border-slate-200 bg-white p-5">
      <p class="text-xs uppercase tracking-wider text-slate-500">Total clicks</p>
      <p class="mt-2 text-3xl font-semibold tabular-nums"><%= @stats.total_clicks %></p>
    </div>
    <div class="rounded-lg border border-slate-200 bg-white p-5">
      <p class="text-xs uppercase tracking-wider text-slate-500">First click</p>
      <p class="mt-2 text-sm"><%= @stats.first_at ? l(@stats.first_at, format: :short) : "—" %></p>
    </div>
    <div class="rounded-lg border border-slate-200 bg-white p-5">
      <p class="text-xs uppercase tracking-wider text-slate-500">Last click</p>
      <p class="mt-2 text-sm"><%= @stats.last_at ? l(@stats.last_at, format: :short) : "—" %></p>
    </div>
  </div>

  <section>
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-500">By country</h2>
    <div class="mt-3 rounded-lg border border-slate-200 bg-white">
      <% if @stats.by_country.empty? %>
        <p class="p-5 text-sm text-slate-500">No clicks yet.</p>
      <% else %>
        <table class="min-w-full divide-y divide-slate-200">
          <thead class="bg-slate-50 text-xs uppercase tracking-wider text-slate-500">
            <tr><th class="px-5 py-3 text-left">Country</th><th class="px-5 py-3 text-right">Clicks</th></tr>
          </thead>
          <tbody class="divide-y divide-slate-200 text-sm">
            <% @stats.by_country.each do |bucket| %>
              <tr><td class="px-5 py-3 font-mono"><%= bucket.country %></td><td class="px-5 py-3 text-right tabular-nums"><%= bucket.count %></td></tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
  </section>

  <section>
    <h2 class="text-sm font-semibold uppercase tracking-wider text-slate-500">Recent visits</h2>
    <div class="mt-3 rounded-lg border border-slate-200 bg-white">
      <% if @recents.empty? %>
        <p class="p-5 text-sm text-slate-500">No visits yet.</p>
      <% else %>
        <table class="min-w-full divide-y divide-slate-200">
          <thead class="bg-slate-50 text-xs uppercase tracking-wider text-slate-500">
            <tr>
              <th class="px-5 py-3 text-left">When</th>
              <th class="px-5 py-3 text-left">Location</th>
              <th class="px-5 py-3 text-left">Visitor</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-200 text-sm">
            <% @recents.each do |click| %>
              <% cp = ClickPresenter.new(click) %>
              <tr>
                <td class="px-5 py-3 tabular-nums"><%= cp.occurred_at %></td>
                <td class="px-5 py-3"><%= cp.location %></td>
                <td class="px-5 py-3 font-mono text-slate-400"><%= cp.ip_mask %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      <% end %>
    </div>
  </section>
</section>
```

- [ ] **Step 2: Configure short time format**

In `config/initializers/time_formats.rb` (create):

```ruby
Time::DATE_FORMATS[:short] = "%Y-%m-%d %H:%M %Z"
```

- [ ] **Step 3: Run stats request spec, confirm green**

```bash
bundle exec rspec spec/requests/stats_spec.rb
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "ui: stats page (totals + country breakdown + recent visits)"
```

---

### Task 25: System spec — golden path

**Files:**
- Create: `spec/system/shortening_flow_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
require "rails_helper"

RSpec.describe "Shortening flow", type: :system do
  before do
    driven_by(:cuprite)
    stub_request(:get, "https://example.com/page")
      .to_return(status: 200, body: "<html><head><title>Example Page</title></head></html>",
                 headers: { "Content-Type" => "text/html" })
  end

  it "lets a user shorten a URL, see the title appear, follow the link, and view stats" do
    visit "/"
    fill_in "Long URL", with: "https://example.com/page"
    click_button "Shorten"

    expect(page).to have_content("Fetching title")
    perform_enqueued_jobs   # FetchTitleJob runs
    expect(page).to have_content("Example Page", wait: 5)

    short_url = page.find("article a[target='_blank']").text
    slug = URI.parse(short_url).path[1..]

    # Follow the redirect (use Capybara's underlying app rather than navigating
    # the headless browser off-app)
    visit "/#{slug}"
    expect(page.current_url).to eq("https://example.com/page")
    perform_enqueued_jobs   # RecordClickJob runs

    visit "/#{slug}/stats"
    expect(page).to have_content("Total clicks")
    expect(page).to have_content("1")
  end
end
```

Notes:
- ActionCable in test uses the `async` adapter; Turbo Stream broadcasts deliver inline.
- `perform_enqueued_jobs` requires `include ActiveJob::TestHelper` (already in `rails_helper`).
- The "follow the redirect" step uses `visit` to keep Capybara in-app. Real cross-origin redirects are tested at the request-spec layer in Task 19.

- [ ] **Step 2: Run**

```bash
bundle exec rspec spec/system/shortening_flow_spec.rb
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test(system): golden-path shortening flow with Turbo Stream broadcast"
```

**End of Phase 7** — open umbrella PR `phase-6-7-controllers-views`.

---

## Phase 8 — Security hardening

### Task 26: rack-attack throttles

**Files:**
- Create: `config/initializers/rack_attack.rb`
- Create: `spec/requests/rate_limiting_spec.rb`

- [ ] **Step 1: Failing rate-limit spec**

```ruby
require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rack::Attack.enabled = false }

  it "throttles POST /short_links beyond 20/min/IP" do
    21.times do
      post "/short_links",
           params: { short_link: { target_url: "https://example.com" } },
           env: { "REMOTE_ADDR" => "9.9.9.9" }
    end
    expect(response).to have_http_status(:too_many_requests)
  end

  it "does NOT throttle redirects at typical viral rates" do
    create(:short_link, slug: "viral1")
    100.times { get "/viral1", env: { "REMOTE_ADDR" => "9.9.9.10" } }
    expect(response).to have_http_status(:found)
  end
end
```

- [ ] **Step 2: Implement**

```ruby
class Rack::Attack
  Rack::Attack.cache.store = Rails.cache

  safelist("allow localhost") do |req|
    %w[127.0.0.1 ::1].include?(req.ip) && Rails.env.local?
  end

  throttle("POST /short_links by ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.post? && req.path == "/short_links"
  end

  throttle("GET /:slug by ip", limit: 1000, period: 1.minute) do |req|
    req.ip if req.get? && req.path =~ %r{\A/[A-Za-z0-9_-]{1,15}\z}
  end

  self.throttled_responder = lambda do |env|
    [429, { "Content-Type" => "text/plain", "Retry-After" => "60" }, ["Too many requests. Please slow down.\n"]]
  end
end
```

- [ ] **Step 3: Enable in `config/application.rb`**

```ruby
config.middleware.use Rack::Attack
```

- [ ] **Step 4: Run, commit**

```bash
bundle exec rspec spec/requests/rate_limiting_spec.rb
git add -A
git commit -m "security: rack-attack — tight form throttle, loose redirect throttle"
```

---

### Task 27: Secure headers + CSP

**Files:**
- Modify: `config/initializers/content_security_policy.rb`
- Modify: `config/application.rb`

- [ ] **Step 1: Edit `content_security_policy.rb`**

```ruby
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :https
    policy.style_src   :self, :https
    policy.connect_src :self, :https, :wss   # Action Cable
  end

  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
```

- [ ] **Step 2: Headers initializer**

`config/initializers/security_headers.rb`:

```ruby
Rails.application.config.action_dispatch.default_headers.merge!(
  "Referrer-Policy" => "no-referrer-when-downgrade",
  "X-Content-Type-Options" => "nosniff",
  "X-Frame-Options" => "DENY"
)
```

In `config/environments/production.rb`, ensure HSTS:

```ruby
config.force_ssl = true
config.ssl_options = { hsts: { expires: 1.year, subdomains: true, preload: false } }
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "security: CSP + Referrer-Policy + nosniff + HSTS in prod"
```

**End of Phase 8** — open PR `phase-8-security`.

---

## Phase 9 — Documentation

### Task 28: Wiki, backlog, README

**Files:**
- Create: `docs/WIKI.md`
- Create: `docs/BACKLOG.md`
- Modify: `README.md`

- [ ] **Step 1: `docs/WIKI.md`**

```markdown
# Wiki — Design Notes

## 1. Short URL path: the chosen solution

We use a 7-character slug generated by [nanoid](https://github.com/puyuan/py-nanoid) over the default URL-safe alphabet (`A–Z`, `a–z`, `0–9`, `_`, `-`). At length 7 the keyspace is 64⁷ ≈ **4.4 trillion**. Slugs are persisted with a unique index; collisions are resolved by application-level retry (3 attempts) before raising.

### Why nanoid over `Base62(id)`

- **Unguessability.** Sequential encodings leak total link count and let attackers enumerate links — a privacy and abuse risk. Nanoid slugs are random across the full keyspace.
- **No coupling to the primary key.** Allows future re-platforming (cross-shard IDs, snowflake IDs) without changing the public URL surface.

### Generation flow

`UrlShortener.call` validates the target URL, calls `Nanoid.generate(size: 7)`, attempts insert, and on a uniqueness collision (race against the `unique(slug)` index) retries up to twice more. After three failures, raises `CollisionExhaustedError`. The unique index is the source of truth; the app-level retry is best-effort for clean UX.

## 2. Limitations and workarounds

### 2.1 Collision probability (birthday paradox)

For a keyspace of size N = 64⁷, the probability of any collision among k slugs is roughly k² / (2N). The 50% collision threshold (√N) sits at ~1.9M slugs — so well before then, the 3-attempt retry stays statistically harmless. **Workaround at scale:** extend the slug length by one character (64⁸ ≈ 281T) — already a one-constant change.

### 2.2 Reserved slugs

`up`, `stats`, `about`, `admin`, `rails`, `assets`, `short_links` are blocked at creation time via `ShortLink::RESERVED_SLUGS`. Future top-level routes get added here; the unique index doesn't help with this — it's an application invariant.

### 2.3 Public stats pages

By design for this demo. Any visitor with a short URL can append `/stats` and see traffic. A production deployment would gate this behind ownership/auth.

### 2.4 Geolocation accuracy

ipapi.co is a free, signup-less service. Real-world inaccuracies:
- **VPN / proxy traffic** lands at the proxy's location, not the user's.
- **Mobile carrier NAT** sometimes returns the carrier hub city.
- **Free-tier rate limit** is 1k req/day — we mitigate via 24h `Rails.cache` keyed by IP.

**Workaround:** swap `GeolocationService` (interface is `lookup(ip) → Result(country:, city:)`) for a MaxMind GeoLite2 implementation. The DB is local (~70 MB), responses are in-process and microsecond-latency, and accuracy is operations-grade. One service replacement, no caller changes.

### 2.5 Click loss vs duplicate clicks

`RecordClickJob` retries transient errors up to 3 times. Retries reuse the original `occurred_at`, so a duplicated row would be a true duplicate (same link, same instant, same hashed IP) — visible as a count anomaly rather than silent corruption. We accept this over the alternative of blocking the redirect on a synchronous log write. After 3 retries the click is dropped and logged.

### 2.6 Rate-limit asymmetry

The form is throttled tight (20/min/IP) because the realistic abuse vector is mass-shortening for spam/phishing. The redirect path is throttled loose (1000/min/IP) because a viral link is a *good* problem — we don't want to cap legitimate traffic at the creator's source-IP rate. If the redirect throttle ever does become a problem, a per-slug throttle keyed on the link (not the visitor IP) is the next step.

### 2.7 In-process worker pool sharing

With `SOLID_QUEUE_IN_PUMA=true`, Puma threads and Solid Queue workers share the AR connection pool. We compensate via `pool: RAILS_MAX_THREADS + 5`. Once worker load competes with web latency, the right move is to extract a separate `bin/jobs` worker process.

## 3. Scalability considerations

At current scale, write throughput on `clicks` is the bottleneck; lookup latency on `short_links` is constant (PK + unique-index lookup). Documented growth path, in order:

1. Cache the slug → target_url lookup in Solid Cache (5-minute TTL). Most redirects skip the DB entirely.
2. Extract `bin/jobs` as its own Render process so job latency stops competing with web threads.
3. Move click writes to an append-only sink (e.g. dedicated table + hourly rollup, or a streaming target like Kinesis). Stats reads then hit a materialized view.
4. Add read replicas for stats pages once `clicks` exceeds tens of millions of rows.

## 4. Security considerations

| Threat | Mitigation |
|---|---|
| Malicious `javascript:` / `data:` URLs | Scheme allowlist (`http`/`https`), URI parse, length cap (2048) |
| SSRF via title fetcher | Pre-resolve hostname; reject any A/AAAA in private/loopback/link-local/multicast/reserved ranges |
| Form abuse / mass-shortening | rack-attack: 20 req/min/IP on `POST /short_links` |
| Redirect path abuse | rack-attack: 1000 req/min/IP on `GET /:slug` (loose by design — see §2.6) |
| CSRF on the form | Rails default CSRF token |
| XSS via stored target_urls | Rails ERB auto-escapes everything; we render `target_url` as text, never as raw HTML |
| Clickjacking | `X-Frame-Options: DENY` |
| MIME sniffing | `X-Content-Type-Options: nosniff` |
| Mixed-content / downgrade | `Strict-Transport-Security` in prod; `force_ssl` |
| Inline script injection | CSP with `script-src 'self' https:` and per-request nonce |

What we don't protect (intentionally): public visibility of stats pages.

## 5. PII and retention

Per visit, we store:
- Country (ISO 3166 alpha-2) and city — coarse-grained location, no street-level data
- `SHA256(ip + ENV['CLICK_IP_SALT'])` — a salted hash, not the raw IP
- Timestamp

The salt is per-environment (set via Render env var), so hashes from staging don't match hashes from production. A given visitor's hash is stable *within* a single deployment, which is what we need for unique-visitor counts, but not across deployments.

**Production retention story (not implemented for the demo):** a scheduled `PurgeOldClicksJob` would delete clicks older than 90 days. Listed in `BACKLOG.md`.
```

- [ ] **Step 2: `docs/BACKLOG.md`**

```markdown
# Backlog

Deliberately deferred to keep MVP tight. None of these block the assessment requirements; all are reasonable next-step polish.

- **Time-series chart on stats page.** Chart.js via `chartkick` would visualize daily clicks for the last 30 days.
- **Unique-visitors counter.** `COUNT(DISTINCT ip_hash)` already supported by the existing index; surface it in `ShortLinkStatsQuery` and the stats view.
- **Pagination on recent visits.** Currently capped at 50.
- **Materialized view rollup** for stats — once `clicks` exceeds millions of rows.
- **90-day click purge** scheduled job for retention compliance.
- **Owner-only stats** with magic-link sign-in — would let stats stay private while keeping the demo's no-account simplicity.
```

- [ ] **Step 3: README**

```markdown
# Link Shortener

> A small URL-shortener service built for the CoinGecko engineering assessment. Submit a long URL, get a short, unguessable one back — with public, per-link stats showing clicks, country breakdown, and recent visits.

🔗 **Live demo:** https://link-shortener.onrender.com
📖 **Design wiki:** [`docs/WIKI.md`](docs/WIKI.md)
🧪 **CI:** ![CI](https://github.com/sgan0420/link-shortener/actions/workflows/ci.yml/badge.svg)

## Features

- Short, unguessable 7-character URLs (nanoid)
- Asynchronous page-title fetching with live Turbo Stream UI update
- Public per-link stats: total clicks, country breakdown, recent visits
- Background click logging with IP-based geolocation; raw IPs are salted-hashed at rest
- SSRF-protected title fetching, rate-limited form, CSP + secure headers

## Tech stack

Rails 8 · Ruby 3.3 · PostgreSQL · Solid Queue / Cache / Cable · Turbo + Stimulus + Tailwind · RSpec · GitHub Actions CI · Render

## Local setup

Requires Ruby 3.3.x and PostgreSQL.

```bash
git clone https://github.com/sgan0420/link-shortener.git
cd link-shortener
bin/setup
bin/dev    # runs web + Tailwind watcher + Solid Queue
```

Visit http://localhost:3000.

## Environment variables

| Var | Required | Notes |
|---|---|---|
| `DATABASE_URL` | yes (prod) | provided by Render |
| `RAILS_MASTER_KEY` | yes (prod) | from `config/master.key` |
| `SECRET_KEY_BASE` | yes (prod) | |
| `CLICK_IP_SALT` | yes (prod) | per-env salt for hashing visitor IPs |
| `RAILS_MAX_THREADS` | no | default 5; drives Puma + DB pool sizing |
| `SOLID_QUEUE_IN_PUMA` | prod | `true` runs the job worker in the web process |
| `IPAPI_BASE_URL` | no | defaults to `https://ipapi.co` |
| `APP_HOST` | yes (prod) | used to build short URLs in views |

## Testing

```bash
bundle exec rspec       # full suite
bundle exec rubocop     # style
bundle exec brakeman    # static security scan
```

## Deployment

Render Blueprint via `render.yaml`. See [`docs/SPECIFICATIONS.md`](docs/SPECIFICATIONS.md) §10 for details.

## Architecture, limitations, scalability, security

See [`docs/WIKI.md`](docs/WIKI.md).

## License

MIT.
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: wiki + backlog + README"
```

**End of Phase 9** — open PR `phase-9-docs`.

---

## Phase 10 — Deployment

### Task 29: `render.yaml` Blueprint

**Files:**
- Create: `render.yaml`
- Create: `bin/render-build.sh`

- [ ] **Step 1: `render.yaml`**

```yaml
services:
  - type: web
    name: link-shortener
    env: ruby
    plan: free
    region: oregon
    buildCommand: ./bin/render-build.sh
    startCommand: bundle exec bin/rails server
    healthCheckPath: /up
    envVars:
      - key: RAILS_ENV
        value: production
      - key: RAILS_LOG_TO_STDOUT
        value: "true"
      - key: RAILS_SERVE_STATIC_FILES
        value: "true"
      - key: SOLID_QUEUE_IN_PUMA
        value: "true"
      - key: RAILS_MAX_THREADS
        value: "5"
      - key: RAILS_MASTER_KEY
        sync: false
      - key: SECRET_KEY_BASE
        generateValue: true
      - key: CLICK_IP_SALT
        generateValue: true
      - key: APP_HOST
        sync: false
      - key: DATABASE_URL
        fromDatabase:
          name: link-shortener-db
          property: connectionString

databases:
  - name: link-shortener-db
    plan: free
    databaseName: link_shortener_production
    user: link_shortener
```

- [ ] **Step 2: `bin/render-build.sh`**

```bash
#!/usr/bin/env bash
set -o errexit

bundle install
bundle exec rails assets:precompile
bundle exec rails db:migrate
```

```bash
chmod +x bin/render-build.sh
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "deploy: render.yaml Blueprint + build script"
```

---

### Task 30: Deploy and verify

- [ ] **Step 1: Push, open Render dashboard, create from Blueprint**

```bash
git push origin main
```

In Render dashboard:
1. New → Blueprint
2. Connect this repo
3. Set the secrets that have `sync: false` (`RAILS_MASTER_KEY`, `APP_HOST` once the URL is assigned)
4. Apply

- [ ] **Step 2: Wait for first deploy**

Watch the Render build logs. Expect ~5 minutes.

- [ ] **Step 3: Smoke test the live URL**

```
GET https://<assigned>.onrender.com/       → form renders
POST shorten a URL                          → short URL returned, title appears within ~5s
GET https://<assigned>.onrender.com/<slug>  → 302 to target
GET <slug>/stats                            → stats page with click count 1+
```

- [ ] **Step 4: Update the README live-demo URL**

Edit `README.md` to replace the placeholder URL with the assigned one.

```bash
git add README.md
git commit -m "docs: set live demo URL"
git push origin main
```

- [ ] **Step 5: Final spec-coverage sanity check**

Open `docs/SPECIFICATIONS.md` side-by-side with the deployed app and walk through:
- §3 architecture — every layer represented in `app/`
- §4 data model — `db/schema.rb` matches
- §6 request flows — all three exercised
- §7 jobs — `solid_queue:processes` table shows the in-puma worker
- §8 security — `curl -I https://<assigned>.onrender.com/` shows HSTS/CSP/nosniff
- §11 docs — README + WIKI committed

- [ ] **Step 6: Final commit**

If anything changed, commit. Otherwise tag the submission commit:

```bash
git tag -a submission-v1 -m "CoinGecko take-home submission"
git push --tags
```

**End of Phase 10 — submission ready.**

---

## Cross-cutting checklist

After all phases ship, verify:

- [ ] All specs green: `bundle exec rspec`
- [ ] RuboCop clean: `bundle exec rubocop`
- [ ] Brakeman clean: `bundle exec brakeman -q --no-pager`
- [ ] CI badge green on `main`
- [ ] Live URL works end-to-end
- [ ] README live URL is the real one
- [ ] `docs/WIKI.md` reads cleanly
- [ ] `docs/BACKLOG.md` accurately reflects what's deferred
- [ ] No raw IPs anywhere in DB or logs (grep `Click.pluck(:ip_hash)` to spot-check)
- [ ] Submission commit is tagged
