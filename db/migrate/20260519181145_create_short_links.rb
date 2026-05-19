# frozen_string_literal: true

class CreateShortLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :short_links do |t|
      t.string :slug, null: false, limit: 15
      t.string :target_url, null: false, limit: 2048
      t.string :title, limit: 512
      t.integer :title_status, null: false, default: 0

      t.timestamps
    end

    add_index :short_links, :slug, unique: true
    add_index :short_links, :created_at, order: { created_at: :desc }
  end
end
