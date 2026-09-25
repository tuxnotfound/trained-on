# One distinct state of a document's training clause: a run of consecutive OTA
# versions whose anchored clause text hashes identically.
class ClauseVersion < ApplicationRecord
  belongs_to :document
  has_one :vendor, through: :document

  validates :sha256, presence: true

  def paragraphs = text.to_s.split("\n\n")
  def empty? = text.blank?
  def ota_commit_url = "https://github.com/OpenTermsArchive/genai-contrib-versions/commit/#{ota_commit_sha}"
end
