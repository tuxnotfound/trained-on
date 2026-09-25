require "test_helper"

class TrainedOn::PanelTest < ActiveSupport::TestCase
  # A reader that answers from a script and records what it was asked.
  class FakeReader
    attr_reader :provider, :model, :asked

    def initialize(provider, answers)
      @provider = provider
      @model = "fake-1"
      @answers = answers.is_a?(Array) ? answers.dup : [ answers ]
      @asked = []
    end

    def configured? = true

    def ask(system:, user:, schema:)
      @asked << { system:, user:, schema: }
      answer = @answers.shift
      raise TrainedOn::Readers::Error, answer.message if answer.is_a?(StandardError)
      answer
    end
  end

  OLD = "We will not use your Inputs or Outputs to train our models unless you opt in."
  NEW = "We may use your Inputs and Outputs to train our models unless you opt out through your account settings."

  def verdict(classification, one_line: "Acme now trains on inputs and outputs unless you opt out.", confidence: "high", direction: "now_trains", concerns: "")
    { "classification" => classification, "direction" => direction, "one_line" => one_line, "material" => true, "confidence" => confidence, "concerns" => concerns }
  end

  def readers(*classes, **opts)
    %w[A B C].zip(classes).map { |name, cls| FakeReader.new("Reader #{name}", verdict(cls, **opts)) }
  end

  def skeptic(index, reason: "fine") = FakeReader.new("Skeptic", { "index" => index, "reason" => reason })

  setup do
    @document = build_document(anchors: [ "train our models" ])
    @old = @document.clause_versions.create!(text: OLD, sha256: "a", effective_at: Time.utc(2025, 1, 1), last_seen_at: Time.utc(2025, 1, 2), ota_commit_sha: "a" * 40)
    @new = @document.clause_versions.create!(text: NEW, sha256: "b", effective_at: Time.utc(2025, 2, 1), last_seen_at: Time.utc(2025, 2, 1), ota_commit_sha: "b" * 40)
    @event = @document.clause_events.create!(from_version: @old, to_version: @new, occurred_on: Date.new(2025, 2, 1),
                                             classification: "scope", one_line: "SUGGESTED SUMMARY, must stay hidden from readers")
  end

  test "three agreeing readers publish, with the summary the check chose" do
    rs = readers("position", "position", "position")
    rs[1] = FakeReader.new("Reader B", verdict("position", one_line: "Acme: training on inputs and outputs is now the default unless you opt out."))
    outcome = TrainedOn::Panel.new(readers: rs, skeptic: skeptic(1)).review_event(@event)

    assert_equal "published", outcome.decision
    @event.reload
    assert_equal "published", @event.state
    assert_equal "panel", @event.decided_by
    assert_equal "position", @event.classification
    assert_equal "Acme: training on inputs and outputs is now the default unless you opt out.", @event.one_line
    assert_equal 3, @event.panel["readers"].size
    assert_equal 1, @event.panel.dig("skeptic", "index")
    assert @event.reviewed_at
  end

  test "readers see the texts and nothing else" do
    rs = readers("position", "position", "position")
    TrainedOn::Panel.new(readers: rs, skeptic: skeptic(0)).review_event(@event)
    rs.each do |reader|
      prompt = reader.asked.first[:user]
      assert_includes prompt, OLD
      assert_includes prompt, NEW
      assert_not_includes prompt, "SUGGESTED SUMMARY"
      assert_not_includes prompt.downcase, "scope"
      assert_not_includes reader.asked.first[:system], "Acme"
    end
  end

  test "disagreement waits for a person, with every answer kept" do
    outcome = TrainedOn::Panel.new(readers: readers("position", "scope", "position"), skeptic: skeptic(0)).review_event(@event)
    assert_equal "human", outcome.decision
    assert_match "Reader B says scope", outcome.reason
    @event.reload
    assert_equal "pending", @event.state
    assert_equal "scope", @event.classification, "the suggestion is untouched"
    assert_equal %w[position scope position], @event.panel["readers"].map { |r| r.dig("answer", "classification") }
  end

  test "unanimous wording is rejected without a person" do
    outcome = TrainedOn::Panel.new(readers: readers("wording", "wording", "wording", direction: "wording_only"), skeptic: skeptic(0)).review_event(@event)
    assert_equal "rejected", outcome.decision
    assert_equal "rejected", @event.reload.state
    assert_equal "panel", @event.decided_by
  end

  test "a reader that fails, or is not confident, sends the event to a person" do
    failing = readers("position", "position", "position")
    failing[2] = FakeReader.new("Reader C", TrainedOn::Readers::Error.new("api.example answered 500"))
    outcome = TrainedOn::Panel.new(readers: failing, skeptic: skeptic(0)).review_event(@event)
    assert_equal "human", outcome.decision
    assert_match "no answer from Reader C", outcome.reason

    @event.update!(panel: nil)
    unsure = readers("position", "position", "position")
    unsure[0] = FakeReader.new("Reader A", verdict("position", confidence: "low", concerns: "opt-out scope unclear"))
    outcome = TrainedOn::Panel.new(readers: unsure, skeptic: skeptic(0)).review_event(@event)
    assert_equal "human", outcome.decision
    assert_match "opt-out scope unclear", outcome.reason
    assert_equal "pending", @event.reload.state
  end

  test "fewer than three readers never decide" do
    outcome = TrainedOn::Panel.new(readers: readers("position", "position").first(2), skeptic: skeptic(0)).review_event(@event)
    assert_equal "human", outcome.decision
    assert_match "only 2 of 3 readers", outcome.reason
    assert_equal "pending", @event.reload.state
    assert_equal 2, @event.panel["readers"].size, "their answers are still kept as advice"
  end

  test "no acceptable summary waits for a person" do
    outcome = TrainedOn::Panel.new(readers: readers("position", "position", "position"), skeptic: skeptic(-1, reason: "all three drop 'through your account settings'")).review_event(@event)
    assert_equal "human", outcome.decision
    assert_match "no summary was accepted", outcome.reason
    assert_equal "pending", @event.reload.state
  end

  test "extraction-flagged and already-decided events are not decided by the panel" do
    @event.update!(suspected_extraction: true)
    outcome = TrainedOn::Panel.new(readers: readers("position", "position", "position"), skeptic: skeptic(0)).review_event(@event)
    assert_equal "human", outcome.decision
    assert_equal "pending", @event.reload.state

    @event.update!(suspected_extraction: false, state: "published", classification: "position", one_line: "x", decided_by: "human", reviewed_at: Time.current)
    assert_equal "skipped", TrainedOn::Panel.new(readers: readers("wording", "wording", "wording"), skeptic: skeptic(0)).review_event(@event).decision
  end

  test "a malformed answer counts as a failure" do
    rs = readers("position", "position", "position")
    rs[0] = FakeReader.new("Reader A", { "classification" => "huge", "direction" => "now_trains", "one_line" => "x", "material" => true, "confidence" => "high", "concerns" => "" })
    outcome = TrainedOn::Panel.new(readers: rs, skeptic: skeptic(0)).review_event(@event)
    assert_equal "human", outcome.decision
    assert_match "classification is \"huge\"", outcome.reason
  end

  # --- registry rows --------------------------------------------------------

  def tier_readers(*answers)
    %w[A B C].zip(answers).map { |name, a| FakeReader.new("Reader #{name}", { "answer" => a, "reason" => "says so", "confidence" => "high" }) }
  end

  test "three readers agreeing with the row confirm it; disagreement withdraws a panel confirmation" do
    tier = @document.vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "unless you opt out")
    Tier.refresh_verification!
    outcome = TrainedOn::Panel.new(readers: tier_readers("trains_opt_out", "trains_opt_out", "trains_opt_out")).check_tier(tier)
    assert_equal "confirmed", outcome.decision
    assert_equal "panel", tier.reload.confirmed_by
    assert Tier.verified.exists?(tier.id)

    outcome = TrainedOn::Panel.new(readers: tier_readers("trains_opt_out", "no_training", "trains_opt_out")).check_tier(tier)
    assert_equal "flagged", outcome.decision
    assert_nil tier.reload.confirmed_by
    assert_not Tier.verified.exists?(tier.id)
  end

  test "a person's confirmation is not withdrawn by the panel" do
    tier = @document.vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "unless you opt out", confirmed_by: "human", confirmed_at: Time.current)
    Tier.refresh_verification!
    TrainedOn::Panel.new(readers: tier_readers("no_training", "no_training", "no_training")).check_tier(tier)
    assert_equal "human", tier.reload.confirmed_by
    assert_equal "flagged", tier.panel_decision
  end
end
