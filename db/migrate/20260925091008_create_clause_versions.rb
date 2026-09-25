class CreateClauseVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :clause_versions do |t|
      t.references :document, null: false, foreign_key: true
      t.text :text
      t.string :sha256, null: false
      t.datetime :effective_at
      t.datetime :last_seen_at
      t.string :ota_commit_sha
      t.integer :versions_count, null: false, default: 1
      t.boolean :anchor_lost, null: false, default: false
      t.json :unanchored_hits

      t.timestamps
    end
    add_index :clause_versions, [ :document_id, :ota_commit_sha ], unique: true
  end
end
