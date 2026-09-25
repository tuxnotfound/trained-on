class Document < ApplicationRecord
  belongs_to :vendor
  has_many :anchors, dependent: :destroy
  has_many :clause_versions, -> { order(:effective_at) }, dependent: :destroy
  has_many :clause_events, dependent: :destroy

  validates :name, :ota_path, presence: true

  def current_version = clause_versions.last

  # The latest version in which the anchors found the clause. When OTA's
  # capture breaks, the registry keeps quoting this one and says so.
  def last_located_version = clause_versions.reject(&:anchor_lost).last
  def capture_broken? = current_version&.anchor_lost?

  # Where OTA shows the tracked document's history, for citation next to every quote.
  def ota_history_url
    "https://github.com/OpenTermsArchive/genai-contrib-versions/commits/main/#{ERB::Util.url_encode(ota_path).gsub('%2F', '/')}"
  end
end
