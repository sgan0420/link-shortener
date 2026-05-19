# frozen_string_literal: true

class FetchTitleJob < ApplicationJob
  queue_as :default

  # ActiveJob rescues in reverse registration order — discard_on handlers
  # below take precedence over this retry_on. Register the broad fallback
  # first so PrivateAddressError + DeserializationError still discard.
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, _error|
    FetchTitleJob.mark_failed(job.arguments.first)
  end

  discard_on TitleFetcher::PrivateAddressError do |job, _error|
    FetchTitleJob.mark_failed(job.arguments.first)
  end

  discard_on ActiveJob::DeserializationError

  def perform(short_link_id)
    short_link = ShortLink.find_by(id: short_link_id)
    return unless short_link

    result = TitleFetcher.call(url: short_link.target_url)

    if result.ok?
      short_link.update!(title: result.title, title_status: :fetched)
    else
      short_link.update!(title_status: :failed)
    end

    self.class.broadcast(short_link)
  end

  def self.mark_failed(short_link_id)
    short_link = ShortLink.find_by(id: short_link_id)
    return unless short_link

    short_link.update(title_status: :failed)
    broadcast(short_link)
  end

  def self.broadcast(short_link)
    return unless short_link

    Turbo::StreamsChannel.broadcast_replace_to(
      short_link,
      target: ActionView::RecordIdentifier.dom_id(short_link, :title),
      partial: "short_links/title",
      locals: { short_link: short_link }
    )
  end
end
