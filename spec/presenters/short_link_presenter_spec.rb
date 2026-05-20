# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShortLinkPresenter do
  let(:link) { build(:short_link, slug: "abc1234", target_url: "https://example.com/path") }
  subject(:presenter) { described_class.new(link, host: "example.test", scheme: "https") }

  describe "#short_url" do
    it "returns the public-facing short URL" do
      expect(presenter.short_url).to eq("https://example.test/abc1234")
    end

    it "honors a non-https scheme override" do
      presenter = described_class.new(link, host: "localhost:3000", scheme: "http")
      expect(presenter.short_url).to eq("http://localhost:3000/abc1234")
    end
  end

  describe "#title_label" do
    it "shows the title when fetched" do
      link.title = "Hello"
      link.title_status = :fetched
      expect(presenter.title_label).to eq("Hello")
    end

    it "shows fetching placeholder when pending" do
      link.title_status = :pending
      expect(presenter.title_label).to match(/Fetching/i)
    end

    it "shows unavailable when failed" do
      link.title_status = :failed
      expect(presenter.title_label).to match(/unavailable/i)
    end
  end
end
