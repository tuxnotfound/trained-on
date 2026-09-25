require "test_helper"

class TrainedOn::BackfillTest < ActiveSupport::TestCase
  PATH = "Acme/Privacy Policy.md"
  OLD = "We will not train our models on your content.\n\nWe sell nothing."
  NEW = "We may train our models on your content unless you opt out.\n\nWe sell nothing."

  def backfill(document, versions)
    TrainedOn::Backfill.new(document, corpus: FakeCorpus.new(PATH => versions)).call
  end

  test "collapses identical clause states and emits one event per real change" do
    document = build_document(anchors: [ "train our models on your content" ])
    run = backfill(document, [
      [ "2025-01-01", OLD ],
      [ "2025-01-02", OLD + "\n\nWe changed the cookie banner." ], # rest of document changed
      [ "2025-01-03", OLD.sub("nothing", "little") ],             # still not the clause
      [ "2025-02-01", NEW ]
    ])
    assert_equal 2, document.clause_versions.count
    assert_equal 1, document.clause_events.count
    event = document.clause_events.first
    assert_equal Date.new(2025, 2, 1), event.occurred_on
    assert_equal "pending", event.state
    assert_equal Date.new(2025, 1, 3), event.window_start
    assert_equal [ event ], run.created_events
  end

  test "counts phantom versions that are identical once normalised" do
    document = build_document(anchors: [ "train our models" ])
    backfill(document, [
      [ "2025-01-01", "[Free](https://x.com/?did=1) We may train our models on it." ],
      [ "2025-01-02", "[Free](https://x.com/?did=2) We may train our models on it." ],
      [ "2025-01-03", "[Free⁠](https://x.com/?did=3) We may train our models on it." ]
    ])
    assert_equal 3, document.reload.versions_walked
    assert_equal 2, document.phantom_versions
    assert_equal 0, document.clause_events.count
  end

  test "a lost anchor is an event, and a capture gap between identical clauses is not a change" do
    document = build_document(anchors: [ "train our models on your content" ])
    backfill(document, [
      [ "2025-01-01", OLD ],
      [ "2025-03-01", "Page failed to load." ],
      [ "2025-03-02", OLD ]
    ])
    kinds = document.clause_events.order(:occurred_on).pluck(:kind)
    assert_equal [ "anchor_lost" ], kinds
  end

  test "a change after a lost anchor is diffed against the last located clause" do
    document = build_document(anchors: [ "train our models on your content" ])
    backfill(document, [
      [ "2025-01-01", OLD ],
      [ "2025-03-01", "Page failed to load." ],
      [ "2025-03-02", NEW ]
    ])
    change = document.clause_events.find_by!(kind: "change")
    assert_equal OLD.split("\n\n").first, change.from_version.text
  end

  test "flags events that coincide with an OTA extraction upgrade" do
    document = build_document(anchors: [ "train our models on your content" ])
    backfill(document, [
      [ "2025-01-01", OLD ],
      [ "2025-02-01", NEW, "Apply technical or declaration upgrade on Acme Privacy Policy" ]
    ])
    assert document.clause_events.first.suspected_extraction
  end

  test "a rebuild keeps human review decisions" do
    document = build_document(anchors: [ "train our models on your content" ])
    versions = [ [ "2025-01-01", OLD ], [ "2025-02-01", NEW ] ]
    backfill(document, versions)
    document.clause_events.first.update!(classification: "position", direction: "now_trains", one_line: "Acme now trains.", state: "published", reviewed_at: Time.current)

    run = backfill(document, versions)
    event = document.clause_events.first
    assert_equal "published", event.state
    assert_equal "Acme now trains.", event.one_line
    assert_empty run.created_events, "a carried-over event is not new"
  end

  test "documents without anchors are skipped" do
    document = build_document(anchors: [])
    backfill(document, [ [ "2025-01-01", OLD ] ])
    assert_equal 0, document.clause_versions.count
  end
end
