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
end
