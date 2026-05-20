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
  #
  # Why the client passes the slug list instead of the server scoping
  # to a user: there's no auth in scope. localStorage stands in for
  # per-user ownership — each browser tracks its own slugs and asks
  # the server to hydrate them. Post-auth this becomes
  # `current_user.short_links.order(created_at: :desc)` and the
  # endpoint signature disappears entirely. See docs/WIKI.md §2.3.
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
