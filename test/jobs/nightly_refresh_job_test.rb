require "test_helper"

class NightlyRefreshJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  setup do
    @original_factory = NightlyRefreshJob.corpus_factory
    ENV["TRAINED_ON_REVIEWER"] = "reviewer@example.com"
  end

  teardown do
    NightlyRefreshJob.corpus_factory = @original_factory
    ENV.delete("TRAINED_ON_REVIEWER")
  end

  test "rebuilds history, never publishes, and emails the reviewer about new events" do
    document = build_document(anchors: [ "train our models on your content" ])
    corpus = FakeCorpus.new(document.ota_path => [
      [ "2025-01-01", "We will not train our models on your content." ],
      [ "2025-02-01", "We may train our models on your content unless you opt out." ]
    ])
    NightlyRefreshJob.corpus_factory = -> { corpus }

    assert_enqueued_emails 1 do
      NightlyRefreshJob.perform_now
    end
    assert_equal [ "pending" ], ClauseEvent.distinct.pluck(:state)

    # A second run finds nothing new and stays quiet.
    assert_no_enqueued_emails { NightlyRefreshJob.perform_now }
  end

  test "without a configured reviewer it logs instead of mailing" do
    ENV.delete("TRAINED_ON_REVIEWER")
    document = build_document(anchors: [ "train our models on your content" ])
    NightlyRefreshJob.corpus_factory = -> { FakeCorpus.new(document.ota_path => [ [ "2025-01-01", "We will not train our models on your content." ], [ "2025-02-01", "We may train our models on your content." ] ]) }
    assert_no_enqueued_emails { NightlyRefreshJob.perform_now }
    assert_equal 1, ClauseEvent.pending.count
  end

  test "the digest links each event to its review screen" do
    document = build_document(anchors: [ "train" ])
    version = document.clause_versions.create!(text: "We train.", sha256: "x", effective_at: Time.current, ota_commit_sha: "c" * 40)
    event = document.clause_events.create!(to_version: version, occurred_on: Date.current)
    mail = ReviewMailer.digest([ event.id ])
    assert_match "1 event to review", mail.subject
    assert_match "/admin/events/#{event.id}", mail.body.encoded
    assert_match "Nothing has been published", mail.body.encoded
  end
end
