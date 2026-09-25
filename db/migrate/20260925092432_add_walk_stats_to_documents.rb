class AddWalkStatsToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :versions_walked, :integer
    add_column :documents, :phantom_versions, :integer
    add_column :documents, :walked_at, :datetime
  end
end
