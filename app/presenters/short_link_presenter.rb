# frozen_string_literal: true

class ShortLinkPresenter
  MAX_TARGET_DISPLAY = 80

  def initialize(short_link,
                 host: ENV.fetch("APP_HOST", "localhost:3000"),
                 scheme: ENV.fetch("APP_SCHEME", "https"))
    @link   = short_link
    @host   = host
    @scheme = scheme
  end

  def short_url
    "#{@scheme}://#{@host}/#{@link.slug}"
  end

  def display_target
    return @link.target_url if @link.target_url.length <= MAX_TARGET_DISPLAY

    @link.target_url.first(MAX_TARGET_DISPLAY - 1) + "…"
  end

  def title_label
    case @link.title_status.to_s
    when "fetched"
      @link.title
    when "failed"
      "Title unavailable"
    else
      "Fetching title…"
    end
  end
end
