# frozen_string_literal: true

class Click < ApplicationRecord
  belongs_to :short_link

  validates :ip_hash, presence: true, length: { maximum: 64 }
  validates :occurred_at, presence: true
  validates :country, length: { maximum: 2 }, allow_nil: true
  validates :city, length: { maximum: 128 }, allow_nil: true
end
