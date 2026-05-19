# frozen_string_literal: true

class UrlShortener
  SLUG_LENGTH = 7
  MAX_ATTEMPTS = 3

  class ValidationError < StandardError; end
  class CollisionExhaustedError < StandardError; end

  def self.call(target_url:)
    new(target_url: target_url).call
  end

  def initialize(target_url:)
    @target_url = target_url.to_s.strip
  end

  def call
    raise ValidationError, "target_url is required" if @target_url.empty?

    MAX_ATTEMPTS.times do
      link = ShortLink.new(
        slug: Nanoid.generate(size: SLUG_LENGTH),
        target_url: @target_url,
        title_status: :pending
      )

      return link if link.save

      if link.errors.of_kind?(:slug, :taken)
        next
      elsif link.errors.any?
        raise ValidationError, link.errors.full_messages.join(", ")
      end
    end

    raise CollisionExhaustedError, "could not generate unique slug after #{MAX_ATTEMPTS} attempts"
  end
end
