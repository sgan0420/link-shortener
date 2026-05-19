# frozen_string_literal: true

# Disabled by default in test so RSpec doesn't accidentally throttle a
# loop of requests in unrelated specs. Specs that exercise the throttle
# explicitly opt in via `Rack::Attack.enabled = true` in a before block.
Rack::Attack.enabled = !Rails.env.test?

Rack::Attack.cache.store = Rails.cache

# Skip throttling for localhost in dev/test, so a developer hammering
# the form during a manual smoke session isn't locked out.
Rack::Attack.safelist("allow localhost") do |req|
  %w[127.0.0.1 ::1].include?(req.ip) && Rails.env.local?
end

# Form abuse is the realistic threat — tight throttle on the create path.
Rack::Attack.throttle("POST /short_links by ip", limit: 20, period: 1.minute) do |req|
  req.ip if req.post? && req.path == "/short_links"
end

# Redirects are public + indexable by design. A viral link is a *good*
# problem; the per-IP limit is loose enough to never bite legitimate
# traffic. The wiki documents the per-slug throttle as the next step if
# this ever does matter.
Rack::Attack.throttle("GET /:slug by ip", limit: 1000, period: 1.minute) do |req|
  req.ip if req.get? && req.path =~ %r{\A/[A-Za-z0-9_-]{1,15}\z}
end

Rack::Attack.throttled_responder = lambda do |_env|
  [
    429,
    { "Content-Type" => "text/plain", "Retry-After" => "60" },
    [ "Too many requests. Please slow down.\n" ]
  ]
end
