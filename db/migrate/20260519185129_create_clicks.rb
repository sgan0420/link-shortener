# frozen_string_literal: true

class CreateClicks < ActiveRecord::Migration[8.1]
  def change
    create_table :clicks do |t|
      t.references :short_link, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :country, limit: 2
      t.string :city, limit: 128
      t.string :ip_hash, null: false, limit: 64
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :clicks, [ :short_link_id, :occurred_at ], order: { occurred_at: :desc }
    add_index :clicks, [ :short_link_id, :country ]
    add_index :clicks, [ :short_link_id, :ip_hash ]
  end
end
