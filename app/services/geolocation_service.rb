# frozen_string_literal: true

require "net/http"
require "ipaddr"
require "json"

class GeolocationService
  Result = Struct.new(:country, :city, keyword_init: true)

  UNKNOWN_COUNTRY = "ZZ" # ISO 3166-1 user-assigned code for "unknown".
  TIMEOUT         = 2
  CACHE_TTL       = 24.hours

  # Reuse the address space classifier from TitleFetcher so the SSRF guard
  # and the geo-skip list stay in sync.
  PRIVATE_RANGES = TitleFetcher::PRIVATE_RANGES

  def self.lookup(ip)
    new(ip).lookup
  end

  def initialize(ip)
    @ip = ip.to_s
  end

  def lookup
    return unknown if private_or_invalid?

    Rails.cache.fetch("geo:#{@ip}", expires_in: CACHE_TTL) do
      fetch_remote || unknown
    end
  end

  private

  def private_or_invalid?
    return true if @ip.empty?

    addr = IPAddr.new(@ip)
    PRIVATE_RANGES.any? { |r| r.include?(addr) }
  rescue IPAddr::InvalidAddressError
    true
  end

  def fetch_remote
    uri = URI.parse("#{base_url}/#{@ip}/json/")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    response = http.request(Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "LinkShortener/1.0"))
    return nil unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    Result.new(
      country: payload["country_code"].presence || UNKNOWN_COUNTRY,
      city: payload["city"].presence
    )
  rescue StandardError
    nil
  end

  def unknown
    Result.new(country: UNKNOWN_COUNTRY, city: nil)
  end

  def base_url
    ENV.fetch("IPAPI_BASE_URL", "https://ipapi.co")
  end
end
