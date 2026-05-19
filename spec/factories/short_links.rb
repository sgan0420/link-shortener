# frozen_string_literal: true

FactoryBot.define do
  factory :short_link do
    sequence(:slug) { |n| "slug#{n.to_s(36).rjust(3, '0')}" }
    target_url { "https://example.com/page-#{SecureRandom.hex(2)}" }
    title_status { :pending }

    trait :fetched do
      title_status { :fetched }
      title { "Example Page" }
    end

    trait :failed_title do
      title_status { :failed }
      title { nil }
    end
  end
end
