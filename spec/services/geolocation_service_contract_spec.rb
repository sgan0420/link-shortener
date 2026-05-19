# frozen_string_literal: true

require "rails_helper"

# Contract spec — proves a *real* ipapi.co response parses correctly.
# Recorded once via VCR; subsequent runs replay the cassette offline,
# so CI never depends on the external service.
RSpec.describe GeolocationService, :contract do
  it "parses a real ipapi.co response shape", vcr: { cassette_name: "ipapi_8_8_8_8" } do
    Rails.cache.clear
    WebMock.allow_net_connect!

    result = described_class.lookup("8.8.8.8")

    expect(result.country).to match(/\A[A-Z]{2}\z/)
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end
end
