class Vendor < ApplicationRecord
  has_many :documents, dependent: :destroy
  has_many :tiers, -> { order(:position) }, dependent: :destroy
  has_many :clause_events, through: :documents

  validates :name, :slug, :ota_service, presence: true
  validates :slug, uniqueness: true

  scope :ordered, -> { order(:position, :name) }

  def to_param = slug

  # "ChatGPT (OpenAI)", or just the name when product and company coincide.
  def name_with_company = company.present? && company != name ? "#{name} (#{company})" : name

  def published_events = clause_events.published.order(occurred_on: :desc)
end
