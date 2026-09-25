class ClauseEvent < ApplicationRecord
  STATES = %w[pending published rejected].freeze
  KINDS = %w[change anchor_lost net_candidate].freeze
  CLASSIFICATIONS = %w[position scope disclosure wording churn unrelated].freeze
  # A published event must say what changed. Only these are public:
  PUBLIC_CLASSIFICATIONS = %w[position scope disclosure].freeze
  DIRECTIONS = %w[now_trains no_longer_trains scope_widened scope_narrowed disclosure wording_only].freeze

  belongs_to :document
  belongs_to :from_version, class_name: "ClauseVersion", optional: true
  belongs_to :to_version, class_name: "ClauseVersion"
  has_one :vendor, through: :document

  validates :state, inclusion: { in: STATES }
  validates :kind, inclusion: { in: KINDS }
  validates :classification, inclusion: { in: CLASSIFICATIONS }, allow_nil: true
  validates :direction, inclusion: { in: DIRECTIONS }, allow_nil: true
  validates :occurred_on, presence: true
  validate :publishable, if: -> { state == "published" }

  scope :pending, -> { where(state: "pending") }
  scope :published, -> { where(state: "published") }
  # What preview mode shows: pending events that would be publishable as they stand.
  scope :publishable_draft, -> { pending.where(kind: "change", classification: PUBLIC_CLASSIFICATIONS).where.not(one_line: [ nil, "" ]) }
  scope :chronological, -> { order(:occurred_on, :id) }

  def slug = "#{occurred_on.iso8601}-#{vendor.slug}-#{document.name.parameterize}"
  def to_param = slug

  def self.find_by_slug!(slug)
    date = Date.iso8601(slug[0, 10])
    where(occurred_on: date).includes(document: :vendor).find { |e| e.slug == slug } ||
      raise(ActiveRecord::RecordNotFound)
  rescue Date::Error
    raise ActiveRecord::RecordNotFound
  end

  def publish!
    update!(state: "published", reviewed_at: Time.current)
  end

  def reject!(classification: self.classification)
    update!(state: "rejected", classification:, reviewed_at: Time.current)
  end

  def headline
    one_line.presence || "#{vendor.name} #{document.name} changed"
  end

  def draft? = state != "published"

  # OTA can go weeks without a capture. The honest date of a change is the
  # window between the last capture of the old text and the first of the new.
  def window_start = from_version&.last_seen_at&.to_date
  def window_days = window_start ? (occurred_on - window_start).to_i : nil
  def gap? = window_days.to_i > 7

  private

  def publishable
    errors.add(:classification, "must be one of #{PUBLIC_CLASSIFICATIONS.join(', ')} to publish") unless classification.in?(PUBLIC_CLASSIFICATIONS)
    errors.add(:one_line, "is required to publish") if one_line.blank?
    errors.add(:kind, "must be a change to publish") unless kind == "change"
  end
end
