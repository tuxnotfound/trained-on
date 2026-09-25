# The only recurring job. Pull the OTA corpus, rebuild every document's clause
# history, ask Haiku for a first opinion on anything new, and email the
# reviewer. Nothing is ever published here: new events arrive pending.
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

    adjudicator = TrainedOn::Adjudicator.new
    new_events.each do |event|
      next if event.kind != "change"
      verdict = adjudicator.call(event)
      event.update!(llm_verdict: verdict) if verdict
    end

    return if new_events.empty?
    if ReviewMailer.reviewer
      ReviewMailer.digest(new_events.map(&:id)).deliver_later
    else
      Rails.logger.warn("[nightly] #{new_events.size} new events pending review; set TRAINED_ON_REVIEWER to be emailed")
    end
  end
end
