# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Shortening flow", type: :system do
  before do
    driven_by(:cuprite)
    stub_request(:get, "https://example.com/page")
      .to_return(status: 200,
                 body: "<html><head><title>Example Page</title></head></html>",
                 headers: { "Content-Type" => "text/html" })
  end

  it "lets a user shorten a URL, sees the title appear, and views populated stats" do
    visit "/"
    fill_in "Long URL", with: "https://example.com/page"
    click_button "Shorten"

    # Result card appears with the title placeholder.
    expect(page).to have_selector("article", wait: 5)
    expect(page).to have_content("Fetching title")

    # FetchTitleJob runs → DB updates → Turbo Stream broadcast updates the
    # title slot live (no page reload).
    perform_enqueued_jobs
    expect(page).to have_content("Example Page", wait: 5)

    # Extract the slug from the rendered short URL and record a synthetic
    # click directly via the job — driving the cross-host redirect through
    # Cuprite would have the browser fetch real example.com.
    short_url = page.find("article a[target='_blank']").text
    slug      = URI.parse(short_url).path.delete_prefix("/")
    short_link = ShortLink.find_by!(slug: slug)
    RecordClickJob.perform_now(short_link.id, "8.8.8.8", Time.current.iso8601)

    visit "/#{slug}/stats"
    # CSS `uppercase` transforms the visible text, so the assertion is on
    # the uppercase form (or a case-insensitive regex).
    expect(page).to have_text(/total clicks/i)
    expect(page).to have_content("1") # the click we just recorded
  end
end
