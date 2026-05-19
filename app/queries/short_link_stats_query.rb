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
    # COALESCE in the GROUP BY so nil-country and explicit "ZZ" rows fold
    # into a single bucket rather than producing two buckets both labeled
    # "ZZ" after a Ruby-side rename.
    clicks
      .group(Arel.sql("COALESCE(country, 'ZZ')"))
      .order(Arel.sql("count(*) DESC"))
      .count
      .map { |country, count| CountryBucket.new(country: country, count: count) }
  end
end
