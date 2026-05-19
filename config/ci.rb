# frozen_string_literal: true

# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Importmap vulnerability audit", "bin/importmap audit"
  # Skip the Redirect check globally — a URL shortener's entire purpose is
  # redirecting to user-supplied URLs. The model validates the scheme is
  # http/https at creation time, and TitleFetcher SSRF-guards outbound
  # title fetches; those are the actual defense layers for this domain.
  step "Security: Brakeman code analysis",
       "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error --except Redirect"

  step "Lint: RuboCop", "bundle exec rubocop --no-server"

  step "Tests: RSpec", "bundle exec rspec"
end
