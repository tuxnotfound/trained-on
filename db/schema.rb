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

ActiveRecord::Schema[8.1].define(version: 2026_09_25_092432) do
  create_table "anchors", force: :cascade do |t|
    t.integer "document_id", null: false
    t.string "phrase"
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_anchors_on_document_id"
  end

  create_table "clause_events", force: :cascade do |t|
    t.integer "document_id", null: false
    t.integer "from_version_id"
    t.integer "to_version_id", null: false
    t.date "occurred_on", null: false
    t.string "state", default: "pending", null: false
    t.string "kind", default: "change", null: false
    t.string "classification"
    t.string "direction"
    t.text "one_line"
    t.json "llm_verdict"
    t.boolean "suspected_extraction", default: false, null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "note"
    t.index ["document_id", "to_version_id", "kind"], name: "index_clause_events_on_document_id_and_to_version_id_and_kind", unique: true
    t.index ["document_id"], name: "index_clause_events_on_document_id"
    t.index ["from_version_id"], name: "index_clause_events_on_from_version_id"
    t.index ["state", "occurred_on"], name: "index_clause_events_on_state_and_occurred_on"
    t.index ["to_version_id"], name: "index_clause_events_on_to_version_id"
  end

  create_table "clause_versions", force: :cascade do |t|
    t.integer "document_id", null: false
    t.text "text"
    t.string "sha256", null: false
    t.datetime "effective_at"
    t.datetime "last_seen_at"
    t.string "ota_commit_sha"
    t.integer "versions_count", default: 1, null: false
    t.boolean "anchor_lost", default: false, null: false
    t.json "unanchored_hits"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "ota_commit_sha"], name: "index_clause_versions_on_document_id_and_ota_commit_sha", unique: true
    t.index ["document_id"], name: "index_clause_versions_on_document_id"
  end

  create_table "documents", force: :cascade do |t|
    t.integer "vendor_id", null: false
    t.string "name"
    t.string "ota_path"
    t.string "ota_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "versions_walked"
    t.integer "phantom_versions"
    t.datetime "walked_at"
    t.index ["ota_path"], name: "index_documents_on_ota_path", unique: true
    t.index ["vendor_id"], name: "index_documents_on_vendor_id"
  end

  create_table "tiers", force: :cascade do |t|
    t.integer "vendor_id", null: false
    t.integer "document_id"
    t.string "name"
    t.string "answer"
    t.text "opt_out"
    t.text "quote"
    t.date "verified_on"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id"], name: "index_tiers_on_document_id"
    t.index ["vendor_id"], name: "index_tiers_on_vendor_id"
  end

  create_table "vendors", force: :cascade do |t|
    t.string "name"
    t.string "slug"
    t.string "ota_service"
    t.text "summary"
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_vendors_on_slug", unique: true
  end

  add_foreign_key "anchors", "documents"
  add_foreign_key "clause_events", "clause_versions", column: "from_version_id"
  add_foreign_key "clause_events", "clause_versions", column: "to_version_id"
  add_foreign_key "clause_events", "documents"
  add_foreign_key "clause_versions", "documents"
  add_foreign_key "documents", "vendors"
  add_foreign_key "tiers", "documents"
  add_foreign_key "tiers", "vendors"
end
