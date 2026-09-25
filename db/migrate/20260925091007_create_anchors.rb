class CreateAnchors < ActiveRecord::Migration[8.1]
  def change
    create_table :anchors do |t|
      t.references :document, null: false, foreign_key: true
      t.string :phrase
      t.string :note

      t.timestamps
    end
  end
end
