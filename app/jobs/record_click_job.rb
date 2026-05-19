# frozen_string_literal: true

class RecordClickJob < ApplicationJob
  queue_as :default

  # Retries reuse the original occurred_at, so a duplicated row is a true
  # duplicate visible as a count anomaly rather than silent corruption.
  # After max attempts the click is dropped + logged — documented trade-off
  # in docs/WIKI.md (rare loss preferred over blocking the redirect path).
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    Rails.logger.warn(
      "[RecordClickJob] dropping click for short_link_id=#{job.arguments.first} " \
      "after #{job.executions} attempts: #{error.class}: #{error.message}"
    )
  end

  def perform(short_link_id, ip, occurred_at_iso)
    return unless ShortLink.where(id: short_link_id).exists?

    geo = GeolocationService.lookup(ip)
    Click.create!(
      short_link_id: short_link_id,
      country: geo.country,
      city: geo.city,
      ip_hash: Digest::SHA256.hexdigest("#{ip}#{ENV.fetch('CLICK_IP_SALT', '')}"),
      occurred_at: Time.iso8601(occurred_at_iso)
    )
  end
end
