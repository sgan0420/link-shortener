# frozen_string_literal: true

class StatsController < ApplicationController
  def show
    @short_link = ShortLink.find_by!(slug: params[:slug])
    @stats      = ShortLinkStatsQuery.new(@short_link).call
    @recents    = RecentClicksQuery.new(@short_link).call(limit: 50)
  end
end
