# frozen_string_literal: true

require "rails_helper"

RSpec.describe UrlShortener do
  describe ".call" do
    it "returns a persisted ShortLink with a 7-char slug" do
      result = described_class.call(target_url: "https://example.com")

      expect(result).to be_a(ShortLink)
      expect(result).to be_persisted
      expect(result.slug.length).to eq(7)
      expect(result.target_url).to eq("https://example.com")
      expect(result).to be_pending
    end

    it "raises ValidationError on invalid url" do
      expect {
        described_class.call(target_url: "javascript:alert(1)")
      }.to raise_error(UrlShortener::ValidationError)
    end

    it "raises ValidationError on blank url" do
      expect {
        described_class.call(target_url: "")
      }.to raise_error(UrlShortener::ValidationError)
    end

    it "retries on slug collision and eventually succeeds" do
      allow(Nanoid).to receive(:generate).and_return("dup0001", "dup0001", "fresh01")
      create(:short_link, slug: "dup0001")

      result = described_class.call(target_url: "https://example.com/another")

      expect(result.slug).to eq("fresh01")
    end

    it "raises CollisionExhaustedError after 3 collisions" do
      allow(Nanoid).to receive(:generate).and_return("collide", "collide", "collide")
      create(:short_link, slug: "collide")

      expect {
        described_class.call(target_url: "https://example.com/x")
      }.to raise_error(UrlShortener::CollisionExhaustedError)
    end
  end
end
