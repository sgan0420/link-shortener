# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ShortLink routing", type: :routing do
  it "routes the form root to short_links#new" do
    expect(get: "/").to route_to(controller: "short_links", action: "new")
  end

  it "routes POST /short_links to short_links#create" do
    expect(post: "/short_links").to route_to(controller: "short_links", action: "create")
  end

  it "routes GET /:slug/stats to stats#show before /:slug catches it" do
    expect(get: "/abc1234/stats").to route_to(
      controller: "stats", action: "show", slug: "abc1234"
    )
  end

  it "routes GET /:slug to redirects#show" do
    expect(get: "/abc1234").to route_to(
      controller: "redirects", action: "show", slug: "abc1234"
    )
  end

  it "does not match /:slug with more than 15 chars" do
    expect(get: "/" + ("a" * 16)).not_to be_routable
  end

  it "still routes /up to the Rails health check (reserved slug)" do
    expect(get: "/up").to route_to(controller: "rails/health", action: "show")
  end
end
