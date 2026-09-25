class CreateClauseEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :clause_events do |t|
      t.references :document, null: false, foreign_key: true
      t.references :from_version, null: true, foreign_key: { to_table: :clause_versions }
      t.references :to_version, null: false, foreign_key: { to_table: :clause_versions }
      t.date :occurred_on, null: false
      # pending -> published | rejected. Nothing reaches the public site without a human.
      t.string :state, null: false, default: "pending"
      # change: anchored clause text changed. anchor_lost: no anchor matched (never silence).
      # net_candidate: the fallback net saw a new unanchored training paragraph.
      t.string :kind, null: false, default: "change"
      # position | scope | disclosure | wording | churn | unrelated
      t.string :classification
      t.string :direction
      t.text :one_line
      t.json :llm_verdict
      t.boolean :suspected_extraction, null: false, default: false
      t.datetime :reviewed_at
      t.timestamps
    end
    add_index :clause_events, [ :document_id, :to_version_id, :kind ], unique: true
    add_index :clause_events, [ :state, :occurred_on ]
  end
end
