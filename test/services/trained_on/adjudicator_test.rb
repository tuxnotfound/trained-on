require "test_helper"

class TrainedOn::AdjudicatorTest < ActiveSupport::TestCase
  FakeBlock = Struct.new(:type, :text)
  FakeMessage = Struct.new(:content, :stop_reason)

  class FakeMessages
    attr_reader :params
    def initialize(reply) = @reply = reply
    def create(**params)
      @params = params
      @reply
    end
  end

  class FakeClient
    attr_reader :messages
    def initialize(reply) = @messages = FakeMessages.new(reply)
  end

  setup do
    @document = build_document(anchors: [ "train" ])
    old = @document.clause_versions.create!(text: "We will not train on your data.", sha256: "a", effective_at: 2.days.ago, ota_commit_sha: "a1")
    new = @document.clause_versions.create!(text: "We may train on your data unless you opt out.", sha256: "b", effective_at: 1.day.ago, ota_commit_sha: "b1")
    @event = @document.clause_events.create!(from_version: old, to_version: new, occurred_on: Date.current)
  end

  test "sends only the two clause texts to Haiku with a JSON schema and parses the verdict" do
    verdict = { classification: "position", direction: "now_trains", material: true, one_line: "Acme now trains by default." }
    client = FakeClient.new(FakeMessage.new([ FakeBlock.new(:text, verdict.to_json) ], :end_turn))
    result = TrainedOn::Adjudicator.new(client:).call(@event)

    assert_equal "position", result["classification"]
    assert_equal "claude-haiku-4-5", result["model"]
    params = client.messages.params
    assert_equal "claude-haiku-4-5", params[:model]
    assert_equal :json_schema, params.dig(:output_config, :format_, :type)
    assert_match "We will not train on your data.", params[:messages].first[:content]
    assert_match "We may train on your data unless you opt out.", params[:messages].first[:content]
  end

  test "a refusal yields no verdict" do
    client = FakeClient.new(FakeMessage.new([], :refusal))
    assert_nil TrainedOn::Adjudicator.new(client:).call(@event)
  end

  test "without an API key it does nothing" do
    ENV.delete("ANTHROPIC_API_KEY")
    assert_nil TrainedOn::Adjudicator.new.call(@event)
  end
end
