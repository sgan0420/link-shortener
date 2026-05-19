# frozen_string_literal: true

class ShortLink < ApplicationRecord
  RESERVED_SLUGS = %w[up stats about admin rails assets short_links].freeze
  TARGET_URL_SCHEME = /\Ahttps?\z/

  enum :title_status, { pending: 0, fetched: 1, failed: 2 }

  has_many :clicks, dependent: :destroy

  validates :slug,
            presence: true,
            uniqueness: { case_sensitive: false },
            length: { maximum: 15 }
  validates :target_url,
            presence: true,
            length: { maximum: 2048 }
  validate  :target_url_must_be_http
  validate  :slug_must_not_be_reserved

  def self.reserved_slug?(slug)
    RESERVED_SLUGS.include?(slug.to_s.downcase)
  end

  private

  def target_url_must_be_http
    return if target_url.blank?

    uri = URI.parse(target_url)
    errors.add(:target_url, "must be http or https") unless uri.scheme&.match?(TARGET_URL_SCHEME)
  rescue URI::InvalidURIError
    errors.add(:target_url, "is not a valid URL")
  end

  def slug_must_not_be_reserved
    errors.add(:slug, "is reserved") if self.class.reserved_slug?(slug)
  end
end
