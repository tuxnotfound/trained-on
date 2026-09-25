# The only recurring job. Pull the OTA corpus, rebuild every document's clause
# history, let the panel decide what it can, and email the reviewer what it
# could not. Nothing is published without three readers agreeing.
class NightlyRefreshJob < ApplicationJob
  queue_as :default

  # Swappable in tests; in production the corpus is cloned on first run.
  class_attribute :corpus_factory, default: -> { TrainedOn::Corpus.versions_repo.tap(&:ensure_clone!) }

  def perform
    corpus = corpus_factory.call
    corpus.pull!

    new_events = Document.includes(:vendor).flat_map do |document|
      TrainedOn::Backfill.new(document, corpus:).call.created_events
    end
    Tier.refresh_verification!

    # A changed clause puts its registry rows back in front of the panel.
    # A person's confirmation stands.
    changed = new_events.select { |e| e.kind == "change" }.map(&:document_id).uniq
    Tier.where(document_id: changed, confirmed_by: "panel").update_all(confirmed_by: nil, confirmed_at: nil, panel: nil)

    PanelJob.perform_now

    return if new_events.empty? && Tier.unconfirmed.none?
    if ReviewMailer.reviewer
      ReviewMailer.digest(new_events.map(&:id)).deliver_later
    else
      Rails.logger.warn("[nightly] #{new_events.size} new events; set TRAINED_ON_REVIEWER to be emailed")
    end
  end
end
