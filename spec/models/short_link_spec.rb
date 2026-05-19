# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShortLink, type: :model do
  describe "validations" do
    subject { build(:short_link) }

    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug).case_insensitive }
    it { is_expected.to validate_length_of(:slug).is_at_most(15) }
    it { is_expected.to validate_presence_of(:target_url) }
    it { is_expected.to validate_length_of(:target_url).is_at_most(2048) }

    it "rejects target_urls that are not http/https" do
      link = build(:short_link, target_url: "javascript:alert(1)")
      expect(link).not_to be_valid
      expect(link.errors[:target_url]).to be_present
    end

    it "rejects slugs that appear in RESERVED_SLUGS" do
      link = build(:short_link, slug: "stats")
      expect(link).not_to be_valid
      expect(link.errors[:slug]).to include(/reserved/i)
    end
  end

  describe "enums" do
    it { is_expected.to define_enum_for(:title_status).with_values(pending: 0, fetched: 1, failed: 2) }
  end

  describe ".reserved_slug?" do
    it "is true for known reserved slugs" do
      %w[up stats about admin rails assets short_links].each do |slug|
        expect(ShortLink.reserved_slug?(slug)).to be(true)
      end
    end

    it "is case-insensitive" do
      expect(ShortLink.reserved_slug?("STATS")).to be(true)
    end
  end
end
