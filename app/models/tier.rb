# One row of the registry: the current answer for one plan of one vendor.
class Tier < ApplicationRecord
  ANSWERS = {
    "trains_opt_out" => "Trains on your inputs by default. You can opt out.",
    "trains_no_opt_out" => "Trains on your inputs. No opt-out stated.",
    "trains_regional_opt_out" => "Trains on your inputs. Opt-out only in some regions.",
    "no_training_default" => "Does not train on your inputs by default.",
    "no_training" => "Does not train on your inputs.",
    "unclear" => "The terms do not say clearly."
  }.freeze
  STALE_AFTER = 30.days

  belongs_to :vendor
  belongs_to :document, optional: true

  validates :name, presence: true
  validates :answer, inclusion: { in: ANSWERS.keys }

  # Public rows: the quote is in the latest capture, and the answer label was
  # confirmed by the panel or by a person.
  scope :verified, -> { where.not(verified_on: nil).where.not(confirmed_by: nil) }
  scope :unconfirmed, -> { where(confirmed_by: nil) }

  # verified_on is mechanical: the date of the latest OTA capture whose located
  # clause contains the quote, or nil when the quote has dropped out (a person
  # must then update the row in db/seeds/tiers.yml).
  def self.refresh_verification!
    includes(document: :clause_versions).find_each do |tier|
      version = tier.document&.last_located_version
      current = version && tier.send(:contains_quote?, version.text)
      tier.update_columns(verified_on: current ? version.last_seen_at.to_date : nil)
    end
  end

  def confirmed? = confirmed_by.present?
  def panel_reason = panel&.dig("reason")
  def panel_decision = panel&.dig("decision")

  def answer_text = ANSWERS.fetch(answer)
  def stale? = verified_on.nil? || verified_on < STALE_AFTER.ago.to_date

  validate :quote_in_clause, if: -> { quote.present? && document }

  # The date OTA first recorded the quoted words, counting back through the
  # unbroken run of clause states that contain them. Edits elsewhere in the
  # clause do not reset it; a capture gap (anchor lost) does not break it.
  def effective_on
    return unless document && quote.present?
    since = nil
    document.clause_versions.reverse_each do |version|
      next if version.anchor_lost
      break unless contains_quote?(version.text)
      since = version.effective_at
    end
    since&.to_date
  end

  # When OTA went more than a week without capturing the document before the
  # quoted words first appeared, the real date lies somewhere in that gap.
  # Returns the last capture before the gap, or nil when captures were close.
  def previous_capture_on
    since = effective_on
    return unless since && !since_first_capture?
    before = document.clause_versions.select { |v| v.effective_at.to_date < since }.max_by(&:last_seen_at)
    last = before&.last_seen_at&.to_date
    last if last && (since - last).to_i > 7
  end

  # True when the quoted words are already in OTA's very first capture, so the
  # real start date is unknown: the page then says "at least since".
  def since_first_capture?
    first = document&.clause_versions&.first
    first.present? && effective_on == first.effective_at.to_date
  end

  def quote_in_clause? = contains_quote?(document&.last_located_version&.text)

  private

  def contains_quote?(text)
    text.present? && TrainedOn::Normaliser.fold(text).include?(TrainedOn::Normaliser.fold(TrainedOn::Normaliser.normalise(quote)))
  end

  # A registry quote must be verbatim from the clause we track, or nobody can
  # check it. Only enforced once the clause history has been backfilled.
  def quote_in_clause
    return if document.clause_versions.none?
    errors.add(:quote, "is not verbatim in the current #{document.name} clause") unless quote_in_clause?
  end
end
