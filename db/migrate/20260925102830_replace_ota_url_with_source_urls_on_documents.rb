class ReplaceOtaUrlWithSourceUrlsOnDocuments < ActiveRecord::Migration[8.1]
  # The live vendor page(s) OTA fetches a document from. Some OTA documents
  # combine several pages, so this is a list.
  def change
    remove_column :documents, :ota_url, :string
    add_column :documents, :source_urls, :json
  end
end
