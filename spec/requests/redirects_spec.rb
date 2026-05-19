# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Redirects", type: :request do
  let!(:link) do
    create(:short_link, :fetched, slug: "abc1234", target_url: "https://example.com/page")
  end

  describe "GET /:slug" do
    it "redirects to the target url with 302 Found and allow_other_host" do
      get "/abc1234"

      expect(response).to have_http_status(:found)
      expect(response.location).to eq("https://example.com/page")
    end

    it "enqueues RecordClickJob with id + remote_ip + ISO8601 occurred_at" do
      expect {
        get "/abc1234", env: { "REMOTE_ADDR" => "8.8.8.8" }
      }.to have_enqueued_job(RecordClickJob).with(link.id, "8.8.8.8", a_kind_of(String))
    end

    it "captures occurred_at before enqueueing (so retries reuse the original time)" do
      freeze = Time.utc(2026, 5, 19, 20, 0, 0)
      travel_to freeze do
        get "/abc1234", env: { "REMOTE_ADDR" => "8.8.8.8" }
      end

      expect(RecordClickJob).to have_been_enqueued.with(link.id, "8.8.8.8", freeze.iso8601)
    end

    it "renders the branded 404 page on unknown slug" do
      get "/nope999"

      expect(response).to have_http_status(:not_found)
      expect(response.body).to match(/not found/i)
    end

    it "does not enqueue a click job on unknown slug" do
      expect {
        get "/nope999"
      }.not_to have_enqueued_job(RecordClickJob)
    end
  end
end
