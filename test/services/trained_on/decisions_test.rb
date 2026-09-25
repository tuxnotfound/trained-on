require "test_helper"

class TrainedOn::DecisionsTest < ActiveSupport::TestCase
  setup do
    @path = Rails.root.join("tmp/decisions-test-#{SecureRandom.hex(4)}.yml")
    @document = build_document
    @version = @document.clause_versions.create!(text: "We may train on your data.", sha256: Digest::SHA256.hexdigest("v2"), effective_at: Time.utc(2025, 2, 1), ota_commit_sha: "b" * 40)
    @event = @document.clause_events.create!(to_version: @version, occurred_on: Date.new(2025, 2, 1), classification: "position", one_line: "Acme now trains.")
    @tier = @document.vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "We may train on your data.")
  end

  teardown { FileUtils.rm_f(@path) }

  def reset_review_state
    @event.update_columns(state: "pending", reviewed_at: nil, one_line: "Suggested.")
    @tier.update_columns(verified_on: nil)
  end

  test "a published event and a verified row survive a fresh database via the file" do
    @event.update!(one_line: "Acme started training on your data by default.", state: "published", reviewed_at: Time.utc(2026, 9, 25, 10))
    @tier.update!(verified_on: Date.new(2026, 9, 25))
    TrainedOn::Decisions.export!(@path)

    reset_review_state
    result = TrainedOn::Decisions.apply!(@path)

    assert_equal 2, result.applied
    @event.reload
    assert_equal "published", @event.state
    assert_equal "Acme started training on your data by default.", @event.one_line
    assert_equal Date.new(2026, 9, 25), @tier.reload.verified_on
  end

  test "pending events are not exported" do
    data = TrainedOn::Decisions.export!(@path)
    assert_empty data["events"]
  end

  test "a decision about a clause that has since changed is not applied" do
    @event.update!(state: "published", reviewed_at: Time.current)
    TrainedOn::Decisions.export!(@path)
    reset_review_state
    @version.update_columns(sha256: Digest::SHA256.hexdigest("different clause"))

    result = TrainedOn::Decisions.apply!(@path)
    assert_equal 0, result.applied
    assert_equal [ "Acme/Privacy Policy.md 2025-02-01" ], result.stale
    assert_equal "pending", @event.reload.state
  end

  test "a missing file applies nothing" do
    assert_equal 0, TrainedOn::Decisions.apply!(Rails.root.join("tmp/does-not-exist.yml")).applied
  end
end
