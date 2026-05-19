# frozen_string_literal: true

# Be sure to restart your server when you modify this file.
# See https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self, :https
    policy.font_src    :self, :https, :data
    policy.img_src     :self, :https, :data
    policy.object_src  :none
    policy.script_src  :self, :https
    policy.style_src   :self, :https
    policy.connect_src :self, :https, :wss # Action Cable / Turbo Streams
    policy.base_uri    :self
    policy.frame_ancestors :none # belt-and-suspenders with X-Frame-Options
  end

  # Per-request random nonces for permitted inline scripts (importmap) and
  # inline styles. Not session-scoped — session.id is lazy in Rails 8 and
  # nil for anonymous GETs, which would render the nonce empty and let
  # all inline scripts through (effectively no protection).
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]

  # Auto-attach the nonce to javascript_tag, javascript_include_tag,
  # stylesheet_link_tag, and javascript_importmap_tags — otherwise the
  # importmap's inline <script type="importmap"> is CSP-blocked and Turbo
  # never loads.
  config.content_security_policy_nonce_auto = true
end
