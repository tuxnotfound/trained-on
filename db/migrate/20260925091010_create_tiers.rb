class CreateTiers < ActiveRecord::Migration[8.1]
  def change
    create_table :tiers do |t|
      t.references :vendor, null: false, foreign_key: true
      t.references :document, null: true, foreign_key: true
      t.string :name
      t.string :answer
      t.text :opt_out
      t.text :quote
      t.date :verified_on
      t.integer :position, null: false, default: 0

      t.timestamps
    end
  end
end
