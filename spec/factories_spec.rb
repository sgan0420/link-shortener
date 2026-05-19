# frozen_string_literal: true

require "rails_helper"

RSpec.describe "factories" do
  it "builds a valid short_link" do
    expect(build(:short_link)).to be_valid
  end

  it "builds a valid short_link with :fetched trait" do
    link = build(:short_link, :fetched)
    expect(link).to be_valid
    expect(link).to be_fetched
    expect(link.title).to be_present
  end

  it "builds a valid short_link with :failed_title trait" do
    link = build(:short_link, :failed_title)
    expect(link).to be_valid
    expect(link).to be_failed
    expect(link.title).to be_nil
  end

  it "builds a valid click" do
    expect(build(:click)).to be_valid
  end

  it "generates unique slugs across multiple builds" do
    slugs = Array.new(5) { build(:short_link).slug }
    expect(slugs.uniq.size).to eq(5)
  end
end
