# frozen_string_literal: true

class ShortLinkPresenter
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
