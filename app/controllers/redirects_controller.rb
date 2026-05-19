# frozen_string_literal: true

class RedirectsController < ApplicationController
  def show
    link = ShortLink.find_by!(slug: params[:slug])

    occurred_at = Time.current
    RecordClickJob.perform_later(link.id, request.remote_ip, occurred_at.iso8601)

    redirect_to link.target_url, status: :found, allow_other_host: true
  end
end
