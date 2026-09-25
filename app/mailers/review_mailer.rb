class ReviewMailer < ApplicationMailer
  def self.reviewer = ENV["TRAINED_ON_REVIEWER"].presence

  def digest(event_ids)
    @events = ClauseEvent.where(id: event_ids).includes(document: :vendor).chronological
    @unanchored = Document.includes(:clause_versions).select { |d| d.current_version&.unanchored_hits.present? }
    mail to: self.class.reviewer,
         subject: "Trained On: #{@events.size} event#{'s' unless @events.one?} to review"
  end
end
