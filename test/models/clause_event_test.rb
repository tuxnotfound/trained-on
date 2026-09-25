require "test_helper"

class ClauseEventTest < ActiveSupport::TestCase
  setup do
    @document = build_document
    @old = @document.clause_versions.create!(text: "Old.", sha256: "a", effective_at: Time.utc(2025, 1, 1), last_seen_at: Time.utc(2025, 1, 10), ota_commit_sha: "a1")
    @new = @document.clause_versions.create!(text: "New.", sha256: "b", effective_at: Time.utc(2025, 3, 1), ota_commit_sha: "b1")
    @event = @document.clause_events.create!(from_version: @old, to_version: @new, occurred_on: Date.new(2025, 3, 1))
  end

  test "cannot publish without a public classification and a summary" do
    assert_not @event.update(state: "published")
    assert_includes @event.errors[:classification].join, "must be one of"
    assert_includes @event.errors[:one_line].join, "required"
  end

  test "cannot publish wording-only or churn events" do
    assert_not @event.update(state: "published", classification: "wording", one_line: "Renamed.")
  end

  test "publishes a classified event" do
    @event.update!(classification: "position", one_line: "Acme now trains.")
    @event.publish!
    assert_equal "published", @event.reload.state
    assert @event.reviewed_at
  end

  test "the change window starts at the last capture of the old text" do
    assert_equal Date.new(2025, 1, 10), @event.window_start
    assert @event.gap?
  end

  test "slug round-trips" do
    assert_equal "2025-03-01-acme-privacy-policy", @event.slug
    assert_equal @event, ClauseEvent.find_by_slug!(@event.slug)
    assert_raises(ActiveRecord::RecordNotFound) { ClauseEvent.find_by_slug!("nonsense") }
  end
end
