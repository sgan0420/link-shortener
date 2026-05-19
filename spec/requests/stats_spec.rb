# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Stats", type: :request do
  let!(:link) { create(:short_link, :fetched, slug: "abc1234") }

  describe "GET /:slug/stats" do
    it "renders totals + country breakdown + recent visits" do
      create_list(:click, 3, short_link: link, country: "US")
      create(:click, short_link: link, country: "GB")

      get "/abc1234/stats"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("4") # total clicks
      expect(response.body).to include("US")
      expect(response.body).to include("GB")
    end

    it "renders 0 with no clicks (zero state)" do
      get "/abc1234/stats"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("0")
    end

    it "404s on unknown slug" do
      get "/nope999/stats"

      expect(response).to have_http_status(:not_found)
    end
  end
end
