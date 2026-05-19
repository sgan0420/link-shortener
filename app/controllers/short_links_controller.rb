# frozen_string_literal: true

class ShortLinksController < ApplicationController
  def new
    @short_link = ShortLink.new
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
