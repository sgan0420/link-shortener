# frozen_string_literal: true

FactoryBot.define do
  factory :click do
    short_link
    country     { "US" }
    city        { "San Francisco" }
    ip_hash     { SecureRandom.hex(32) }
    occurred_at { Time.current }
  end
end
