# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  # Test env disables Rack::Attack globally (see config/initializers/
  # rack_attack.rb). Opt in here and reset the throttle cache so
  # counters from other specs don't bleed in.
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  after { Rack::Attack.enabled = false }

  describe "POST /short_links" do
    let(:valid_params) { { short_link: { target_url: "https://example.com" } } }

    it "throttles at > 20 requests/minute/IP" do
      20.times do
        post "/short_links", params: valid_params, env: { "REMOTE_ADDR" => "9.9.9.9" }
      end
      # 21st request from the same IP is over the limit.
      post "/short_links", params: valid_params, env: { "REMOTE_ADDR" => "9.9.9.9" }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq("60")
    end

    it "does not throttle a different IP under the limit" do
      20.times do
        post "/short_links", params: valid_params, env: { "REMOTE_ADDR" => "9.9.9.9" }
      end
      post "/short_links", params: valid_params, env: { "REMOTE_ADDR" => "9.9.9.99" }

      # The other IP gets its own bucket.
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end

  describe "GET /:slug" do
    before { create(:short_link, slug: "viral1") }

    it "does not throttle redirects at typical viral rates" do
      100.times { get "/viral1", env: { "REMOTE_ADDR" => "9.9.9.10" } }

      expect(response).to have_http_status(:found)
    end
  end
end
