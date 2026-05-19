# frozen_string_literal: true

class ShortLinkStatsQuery
  Result        = Struct.new(:total_clicks, :first_at, :last_at, :by_country, keyword_init: true)
  CountryBucket = Struct.new(:country, :count, keyword_init: true)

  def initialize(short_link)
    @short_link = short_link
  end

  def call
    clicks = @short_link.clicks
    Result.new(
      total_clicks: clicks.count,
      first_at:     clicks.minimum(:occurred_at),
      last_at:      clicks.maximum(:occurred_at),
      by_country:   country_buckets(clicks)
    )
  end

  private

  def country_buckets(clicks)
    clicks.group(:country).order(Arel.sql("count(*) DESC")).count.map do |country, count|
      CountryBucket.new(country: country || "ZZ", count: count)
    end
  end
end
