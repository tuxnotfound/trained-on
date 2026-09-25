class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.references :vendor, null: false, foreign_key: true
      t.string :name
      t.string :ota_path
      t.string :ota_url

      t.timestamps
    end
    add_index :documents, :ota_path, unique: true
  end
end
