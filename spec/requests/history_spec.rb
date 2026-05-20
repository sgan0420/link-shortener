# frozen_string_literal: true

require "rails_helper"

RSpec.describe "History", type: :request do
  describe "GET /history" do
    it "renders the page with the stimulus controller anchor" do
      get "/history"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("My links")
      # The list is hydrated client-side; the server-rendered shell just
      # needs the controller anchor for Stimulus to attach.
      expect(response.body).to include("history-list")
    end
  end
end
