# frozen_string_literal: true

class ShortLinksController < ApplicationController
  LOOKUP_MAX_SLUGS = 50

  def new
    @short_link = ShortLink.new
  end

  # Server-side hydration for /my-links — Stimulus POSTs the slug list
  # from localStorage, controller returns rendered cards. Order of the
  # response mirrors the order of the request, so the client's "newest
  # first" ordering is preserved.
  def lookup
    slugs = Array(params[:slugs]).map(&:to_s).first(LOOKUP_MAX_SLUGS)
    by_slug = ShortLink.where(slug: slugs).index_by(&:slug)
    ordered = slugs.filter_map { |s| by_slug[s] }

    render partial: "result_card",
           collection: ordered,
           as: :short_link,
           locals: { show_saved_at: true },
           formats: [ :html ]
  end

  def create
    @short_link = UrlShortener.call(target_url: params.dig(:short_link, :target_url))
    FetchTitleJob.perform_later(@short_link.id)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to root_path }
    end
  rescue UrlShortener::ValidationError => e
    @short_link = ShortLink.new(target_url: params.dig(:short_link, :target_url))
    @short_link.errors.add(:target_url, e.message)
    respond_to do |format|
      format.turbo_stream { render :create_error, status: :unprocessable_content }
      format.html { redirect_to root_path, alert: e.message }
    end
  rescue UrlShortener::CollisionExhaustedError
    respond_to do |format|
      format.turbo_stream { render :create_collision_exhausted, status: :service_unavailable }
      format.html { redirect_to root_path, alert: "Please try again." }
    end
  end
end
