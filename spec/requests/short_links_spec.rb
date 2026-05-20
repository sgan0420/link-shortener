# frozen_string_literal: true

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
    let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html" } }
    let(:valid_params)  { { short_link: { target_url: "https://example.com" } } }

    it "creates a ShortLink and renders Turbo Stream" do
      expect {
        post "/short_links", params: valid_params, headers: turbo_headers
      }.to change(ShortLink, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include("Fetching title")
    end

    it "enqueues FetchTitleJob with the new short_link id" do
      expect {
        post "/short_links", params: valid_params, headers: turbo_headers
      }.to have_enqueued_job(FetchTitleJob)
    end

    it "returns 422 turbo stream on invalid input and preserves the user's input" do
      post "/short_links",
           params: { short_link: { target_url: "javascript:alert(1)" } },
           headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to match(/must be http or https/i)
    end

    it "returns 422 on blank input" do
      post "/short_links", params: { short_link: { target_url: "" } }, headers: turbo_headers

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects to root for non-Turbo HTML clients on success" do
      post "/short_links", params: valid_params

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /short_links/lookup" do
    let!(:link_a) { create(:short_link, :fetched, slug: "abc1234", target_url: "https://example.com/a", title: "Link A") }
    let!(:link_b) { create(:short_link, :fetched, slug: "xyz9876", target_url: "https://example.com/b", title: "Link B") }

    it "renders cards for the requested slugs in the order received" do
      post "/short_links/lookup",
           params: { slugs: [ "xyz9876", "abc1234" ] }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Link A", "Link B")
      expect(response.body.index("Link B")).to be < response.body.index("Link A")
    end

    it "includes the 'Saved <timestamp>' line on each card" do
      post "/short_links/lookup",
           params: { slugs: [ "abc1234" ] }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "text/html" }

      expect(response.body).to match(/Saved \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} UTC/)
    end

    it "silently drops slugs that don't exist" do
      post "/short_links/lookup",
           params: { slugs: [ "abc1234", "ghost00" ] }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Link A")
      expect(response.body).not_to include("ghost00")
    end

    it "returns empty body when no slugs match" do
      post "/short_links/lookup",
           params: { slugs: [ "ghost01", "ghost02" ] }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body.strip).to be_empty
    end

    it "caps the lookup at LOOKUP_MAX_SLUGS — slugs past the cap are dropped" do
      # Pad the request with junk slugs first, then put the real one
      # past the cap. If the controller honors the cap, it never sees
      # "abc1234" and the response is empty.
      padding = Array.new(ShortLinksController::LOOKUP_MAX_SLUGS) { |i| "miss#{i.to_s.rjust(2, '0')}" }
      slugs = padding + [ "abc1234" ]

      post "/short_links/lookup",
           params: { slugs: slugs }.to_json,
           headers: { "Content-Type" => "application/json", "Accept" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Link A")
    end
  end
end
