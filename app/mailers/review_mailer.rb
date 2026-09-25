class ReviewMailer < ApplicationMailer
  def self.reviewer = ENV["TRAINED_ON_REVIEWER"].presence

  def digest(event_ids)
    events = ClauseEvent.where(id: event_ids).includes(document: :vendor).chronological
    @published = events.select { |e| e.state == "published" }
    @rejected = events.select { |e| e.state == "rejected" }
    @pending = ClauseEvent.pending.includes(document: :vendor).chronological
    @rows = Tier.unconfirmed.or(Tier.where(verified_on: nil)).includes(:vendor, :document)
    @unanchored = Document.includes(:clause_versions).select { |d| d.current_version&.unanchored_hits.present? }
    mail to: self.class.reviewer,
         subject: "Trained On: #{@published.size} published, #{@pending.size} waiting for you"
  end
end
