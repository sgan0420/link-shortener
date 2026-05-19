# frozen_string_literal: true

require "nokogiri"
require "resolv"
require "ipaddr"
require "net/http"

class TitleFetcher
  class PrivateAddressError < StandardError; end

  Result = Struct.new(:ok, :title, :reason, keyword_init: true) do
    alias_method :ok?, :ok
  end

  MAX_TITLE_LENGTH  = 512
  HTTP_OPEN_TIMEOUT = 5
  HTTP_READ_TIMEOUT = 5
  MAX_BODY_BYTES    = 1.megabyte
  MAX_REDIRECTS     = 3

  PRIVATE_RANGES = %w[
    0.0.0.0/8
    10.0.0.0/8
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.168.0.0/16
    224.0.0.0/4
    ::1/128
    fc00::/7
    fe80::/10
  ].map { |r| IPAddr.new(r) }

  def self.call(url:)
    new(url).call
  end

  def initialize(url)
    @url = url
  end

  def call
    uri = URI.parse(@url)
    guard_against_private_address!(uri.host)
    Result.new(ok: true, title: fetch_title(uri))
  rescue PrivateAddressError
    raise
  rescue StandardError => e
    Result.new(ok: false, reason: "#{e.class}: #{e.message}")
  end

  private

  def guard_against_private_address!(host)
    addresses = Resolv.getaddresses(host)
    raise PrivateAddressError, "no addresses for #{host}" if addresses.empty?

    addresses.each do |addr|
      ip = IPAddr.new(addr)
      raise PrivateAddressError, "private address: #{addr}" if PRIVATE_RANGES.any? { |r| r.include?(ip) }
    end
  end

  def fetch_title(uri, redirects_left: MAX_REDIRECTS)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = HTTP_OPEN_TIMEOUT
    http.read_timeout = HTTP_READ_TIMEOUT

    request = Net::HTTP::Get.new(uri.request_uri, "User-Agent" => "LinkShortener/1.0")

    http.request(request) do |response|
      case response
      when Net::HTTPRedirection
        raise "too many redirects" if redirects_left <= 0

        new_uri = URI.parse(response["location"])
        guard_against_private_address!(new_uri.host)
        return fetch_title(new_uri, redirects_left: redirects_left - 1)
      when Net::HTTPSuccess
        return extract_title(read_capped_body(response))
      else
        raise "http #{response.code}"
      end
    end
  end

  def read_capped_body(response)
    body = +""
    response.read_body do |chunk|
      space = MAX_BODY_BYTES - body.bytesize
      if chunk.bytesize >= space
        body << chunk.byteslice(0, space)
        break
      end
      body << chunk
    end
    body
  end

  def extract_title(body)
    doc = Nokogiri::HTML(body)
    raw = doc.at_css("title")&.text.to_s.squish
    raise "no title element" if raw.empty?

    raw.first(MAX_TITLE_LENGTH)
  end
end
