# frozen_string_literal: true

require "rails_helper"

RSpec.describe GeolocationService do
  before { Rails.cache.clear }

  describe ".lookup" do
    it "returns Unknown for private/loopback IPs without making any HTTP call" do
      result = described_class.lookup("127.0.0.1")

      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
      expect(result.city).to be_nil
      expect(WebMock).not_to have_requested(:any, /ipapi/)
    end

    it "returns Unknown for RFC1918 private IPs without making any HTTP call" do
      result = described_class.lookup("10.0.0.1")

      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
      expect(WebMock).not_to have_requested(:any, /ipapi/)
    end

    it "returns Unknown for garbage input" do
      result = described_class.lookup("not-an-ip")

      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
      expect(WebMock).not_to have_requested(:any, /ipapi/)
    end

    it "calls ipapi.co for public IPs and returns country + city" do
      stub_request(:get, "https://ipapi.co/8.8.8.8/json/")
        .to_return(status: 200,
                   body: { country_code: "US", city: "Mountain View" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = described_class.lookup("8.8.8.8")

      expect(result.country).to eq("US")
      expect(result.city).to eq("Mountain View")
    end

    it "caches results by IP across calls" do
      stub_request(:get, "https://ipapi.co/8.8.8.8/json/")
        .to_return(status: 200, body: { country_code: "US", city: "MV" }.to_json)

      2.times { described_class.lookup("8.8.8.8") }

      expect(WebMock).to have_requested(:get, "https://ipapi.co/8.8.8.8/json/").once
    end

    it "returns Unknown on timeout" do
      stub_request(:get, %r{https://ipapi.co/.*}).to_timeout

      result = described_class.lookup("8.8.8.8")

      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
    end

    it "returns Unknown on 5xx response" do
      stub_request(:get, %r{https://ipapi.co/.*}).to_return(status: 503)

      result = described_class.lookup("8.8.8.8")

      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
    end

    it "returns Unknown when country_code is missing from response" do
      stub_request(:get, "https://ipapi.co/8.8.8.8/json/")
        .to_return(status: 200, body: { city: "Nowhere" }.to_json)

      result = described_class.lookup("8.8.8.8")

      expect(result.country).to eq(GeolocationService::UNKNOWN_COUNTRY)
    end
  end
end
