# frozen_string_literal: true

Rails.application.routes.draw do
  # Health check for load balancers / uptime monitors. Declared first so
  # it's matched before the catch-all slug route below; "up" is also in
  # ShortLink::RESERVED_SLUGS to prevent collision at creation time.
  get "up" => "rails/health#show", as: :rails_health_check

  root "short_links#new"
  post "short_links" => "short_links#create"

  # Slug constraint: 1-15 chars from nanoid's URL-safe alphabet.
  # /:slug/stats is declared BEFORE /:slug so Rails matches it first —
  # router resolves top-to-bottom.
  constraints slug: /[A-Za-z0-9_-]{1,15}/ do
    get ":slug/stats" => "stats#show",     as: :stats
    get ":slug"       => "redirects#show", as: :short_link
  end
end
