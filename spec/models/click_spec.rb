# frozen_string_literal: true

require "rails_helper"

RSpec.describe Click, type: :model do
  it { is_expected.to belong_to(:short_link) }
  it { is_expected.to validate_presence_of(:ip_hash) }
  it { is_expected.to validate_presence_of(:occurred_at) }
  it { is_expected.to validate_length_of(:country).is_at_most(2) }
  it { is_expected.to validate_length_of(:ip_hash).is_at_most(64) }
end
