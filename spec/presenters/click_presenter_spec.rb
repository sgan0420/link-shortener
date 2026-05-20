# frozen_string_literal: true

require "rails_helper"

RSpec.describe ClickPresenter do
  let(:click) do
    build(:click,
          country: "US",
          city: "Mountain View",
          ip_hash: "abcdef1234567890" * 4,
          occurred_at: Time.utc(2026, 5, 17, 14, 30))
  end
  subject(:presenter) { described_class.new(click) }

  describe "#location" do
    it "formats location as 'City, CC' when both present" do
      expect(presenter.location).to eq("Mountain View, US")
    end

    it "falls back to country only when city is missing" do
      click.city = nil
      expect(presenter.location).to eq("US")
    end

    it "shows 'Unknown' when both country and city are missing" do
      click.country = nil
      click.city = nil
      expect(presenter.location).to eq("Unknown")
    end

    it "shows 'Unknown' when country is the ZZ fallback and city is missing" do
      click.country = "ZZ"
      click.city = nil
      expect(presenter.location).to eq("Unknown")
    end
  end

  describe "#ip_mask" do
    it "shows only the first 8 chars of the hash followed by an ellipsis" do
      expect(presenter.ip_mask).to eq("abcdef12…")
    end
  end

  describe "#occurred_at" do
    it "formats as 'YYYY-MM-DD HH:MM:SS UTC'" do
      expect(presenter.occurred_at).to eq("2026-05-17 14:30:00 UTC")
    end
  end
end
