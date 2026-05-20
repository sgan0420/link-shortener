# frozen_string_literal: true

class ClickPresenter
  UNKNOWN_COUNTRIES = [ nil, "", "ZZ" ].freeze

  def initialize(click)
    @click = click
  end

  def location
    known_country = !UNKNOWN_COUNTRIES.include?(@click.country)

    if @click.city.present? && known_country
      "#{@click.city}, #{@click.country}"
    elsif known_country
      @click.country
    elsif @click.city.present?
      @click.city
    else
      "Unknown"
    end
  end

  def ip_mask
    "#{@click.ip_hash.to_s.first(8)}…"
  end

  def occurred_at
    @click.occurred_at.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
  end
end
