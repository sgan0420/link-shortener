# frozen_string_literal: true

Rails.application.routes.draw do
  # Health check for load balancers / uptime monitors. Declared first so
  # it's matched before the catch-all slug route below; "up" is also in
  # ShortLink::RESERVED_SLUGS to prevent collision at creation time.
  get "up" => "rails/health#show", as: :rails_health_check

  root "short_links#new"
  post "short_links" => "short_links#create", as: :short_links

  # Client-local "My links" page (reads localStorage via a Stimulus
  # controller). No server-side index — there's no auth, so a global
  # recent-links list would leak across users. The path is reserved at
  # creation time so a user can't shadow the route.
  get "my-links" => "my_links#show", as: :my_links

  # Slug constraint: 1-15 chars from nanoid's URL-safe alphabet.
  # /:slug/stats is declared BEFORE /:slug so Rails matches it first —
  # router resolves top-to-bottom.
  constraints slug: /[A-Za-z0-9_-]{1,15}/ do
    get ":slug/stats" => "stats#show",     as: :stats
    get ":slug"       => "redirects#show", as: :short_link
  end
end
