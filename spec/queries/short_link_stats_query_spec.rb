# frozen_string_literal: true

require "rails_helper"

RSpec.describe ShortLinkStatsQuery do
  let(:link) { create(:short_link) }

  it "returns zeroed stats for a link with no clicks" do
    result = described_class.new(link).call

    expect(result.total_clicks).to eq(0)
    expect(result.first_at).to be_nil
    expect(result.last_at).to be_nil
    expect(result.by_country).to eq([])
  end

  it "aggregates by country, ordered by count desc" do
    create_list(:click, 3, short_link: link, country: "US")
    create_list(:click, 1, short_link: link, country: "GB")
    create_list(:click, 2, short_link: link, country: "JP")

    result = described_class.new(link).call

    expect(result.total_clicks).to eq(6)
    expect(result.by_country.map(&:country)).to eq(%w[US JP GB])
    expect(result.by_country.map(&:count)).to eq([ 3, 2, 1 ])
  end

  it "reports first and last click timestamps" do
    create(:click, short_link: link, occurred_at: 2.days.ago)
    create(:click, short_link: link, occurred_at: 1.hour.ago)

    result = described_class.new(link).call

    expect(result.first_at).to be_within(1.minute).of(2.days.ago)
    expect(result.last_at).to be_within(1.minute).of(1.hour.ago)
  end

  it "buckets nil-country clicks as 'ZZ' (matches the GeolocationService fallback)" do
    create(:click, short_link: link, country: nil)
    create(:click, short_link: link, country: "US")

    result = described_class.new(link).call
    bucket_countries = result.by_country.map(&:country)

    expect(bucket_countries).to include("ZZ", "US")
  end

  it "folds nil-country and explicit 'ZZ' rows into a single 'ZZ' bucket" do
    create_list(:click, 2, short_link: link, country: nil)
    create_list(:click, 3, short_link: link, country: "ZZ")

    result = described_class.new(link).call
    zz_buckets = result.by_country.select { |b| b.country == "ZZ" }

    expect(zz_buckets.size).to eq(1)
    expect(zz_buckets.first.count).to eq(5)
  end

  it "ignores clicks belonging to other short_links" do
    other_link = create(:short_link)
    create_list(:click, 5, short_link: other_link, country: "US")
    create_list(:click, 2, short_link: link,       country: "US")

    result = described_class.new(link).call

    expect(result.total_clicks).to eq(2)
  end
end
