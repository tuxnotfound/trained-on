class CreateVendors < ActiveRecord::Migration[8.1]
  def change
    create_table :vendors do |t|
      t.string :name
      t.string :slug
      t.string :ota_service
      t.text :summary
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :vendors, :slug, unique: true
  end
end
