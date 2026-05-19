# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_19_185129) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "clicks", force: :cascade do |t|
    t.string "city", limit: 128
    t.string "country", limit: 2
    t.datetime "created_at", null: false
    t.string "ip_hash", limit: 64, null: false
    t.datetime "occurred_at", null: false
    t.bigint "short_link_id", null: false
    t.datetime "updated_at", null: false
    t.index ["short_link_id", "country"], name: "index_clicks_on_short_link_id_and_country"
    t.index ["short_link_id", "ip_hash"], name: "index_clicks_on_short_link_id_and_ip_hash"
    t.index ["short_link_id", "occurred_at"], name: "index_clicks_on_short_link_id_and_occurred_at", order: { occurred_at: :desc }
  end

  create_table "short_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "slug", limit: 15, null: false
    t.string "target_url", limit: 2048, null: false
    t.string "title", limit: 512
    t.integer "title_status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_short_links_on_created_at", order: :desc
    t.index ["slug"], name: "index_short_links_on_slug", unique: true
  end

  add_foreign_key "clicks", "short_links", on_delete: :cascade
end
