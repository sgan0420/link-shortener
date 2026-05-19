# frozen_string_literal: true

require "rails_helper"

RSpec.describe RecentClicksQuery do
  let(:link) { create(:short_link) }

  it "returns clicks ordered by occurred_at desc" do
    older = create(:click, short_link: link, occurred_at: 2.days.ago)
    newer = create(:click, short_link: link, occurred_at: 1.hour.ago)

    result = described_class.new(link).call

    expect(result.to_a).to eq([ newer, older ])
  end

  it "caps to the supplied limit" do
    create_list(:click, 5, short_link: link)

    result = described_class.new(link).call(limit: 2)

    expect(result.count).to eq(2)
  end

  it "defaults to a limit of 50" do
    create_list(:click, 60, short_link: link)

    result = described_class.new(link).call

    expect(result.count).to eq(50)
  end

  it "scopes to the supplied short_link" do
    other_link = create(:short_link)
    create_list(:click, 3, short_link: other_link)
    create_list(:click, 2, short_link: link)

    result = described_class.new(link).call

    expect(result.count).to eq(2)
    expect(result.pluck(:short_link_id).uniq).to eq([ link.id ])
  end
end
