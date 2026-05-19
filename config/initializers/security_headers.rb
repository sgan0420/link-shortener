# frozen_string_literal: true

# Belt-and-suspenders security headers applied to every response. The CSP
# header is set by the separate content_security_policy initializer.
Rails.application.config.action_dispatch.default_headers.merge!(
  "Referrer-Policy"        => "no-referrer-when-downgrade",
  "X-Content-Type-Options" => "nosniff",
  "X-Frame-Options"        => "DENY"
)
