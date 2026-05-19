# frozen_string_literal: true

class RecentClicksQuery
  DEFAULT_LIMIT = 50

  def initialize(short_link)
    @short_link = short_link
  end

  def call(limit: DEFAULT_LIMIT)
    @short_link.clicks.order(occurred_at: :desc).limit(limit)
  end
end
