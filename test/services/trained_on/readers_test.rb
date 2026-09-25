require "test_helper"

class TrainedOn::ReadersTest < ActiveSupport::TestCase
  SCHEMA = { "type" => "object", "properties" => { "answer" => { "type" => "string", "enum" => %w[yes no] } }, "required" => %w[answer], "additionalProperties" => false }.freeze

  class FakeTransport
    attr_reader :calls
    def initialize(response) = (@response, @calls = response, [])
    def call(method, url, headers: {}, body: nil)
      @calls << { method:, url:, headers:, body: }
      @response.is_a?(StandardError) ? raise(@response) : @response
    end
  end

  setup do
    ENV["OPENAI_API_KEY"] = "sk-test"
    ENV["GEMINI_API_KEY"] = "g-test"
  end

  teardown do
    ENV.delete("OPENAI_API_KEY")
    ENV.delete("GEMINI_API_KEY")
    ENV.delete("TRAINED_ON_OPENAI_MODEL")
  end

  test "an unconfigured reader refuses to ask" do
    ENV.delete("OPENAI_API_KEY")
    assert_raises(TrainedOn::Readers::Error) { TrainedOn::Readers::OpenAIReader.new(transport: FakeTransport.new({})).ask(system: "s", user: "u", schema: SCHEMA) }
  end

  test "OpenAI: strict JSON schema request, parsed answer, model from the environment" do
    ENV["TRAINED_ON_OPENAI_MODEL"] = "gpt-test"
    transport = FakeTransport.new({ "choices" => [ { "finish_reason" => "stop", "message" => { "content" => '{"answer":"yes"}' } } ] })
    reader = TrainedOn::Readers::OpenAIReader.new(transport:)
    assert_equal({ "answer" => "yes" }, reader.ask(system: "SYS", user: "USER", schema: SCHEMA))

    call = transport.calls.first
    assert_equal "https://api.openai.com/v1/chat/completions", call[:url]
    assert_equal "Bearer sk-test", call[:headers]["Authorization"]
    assert_equal "gpt-test", call[:body][:model]
    assert_equal [ %w[system SYS], %w[user USER] ], call[:body][:messages].map { |m| [ m[:role], m[:content] ] }
    assert_equal true, call[:body].dig(:response_format, :json_schema, :strict)
    assert_equal SCHEMA, call[:body].dig(:response_format, :json_schema, :schema)
  end

  test "OpenAI: a refusal or a cut-off answer is an error" do
    refusal = FakeTransport.new({ "choices" => [ { "message" => { "refusal" => "no" } } ] })
    assert_raises(TrainedOn::Readers::Error) { TrainedOn::Readers::OpenAIReader.new(transport: refusal).ask(system: "s", user: "u", schema: SCHEMA) }
    cut = FakeTransport.new({ "choices" => [ { "finish_reason" => "length", "message" => { "content" => '{"ans' } } ] })
    assert_raises(TrainedOn::Readers::Error) { TrainedOn::Readers::OpenAIReader.new(transport: cut).ask(system: "s", user: "u", schema: SCHEMA) }
  end

  test "Gemini: schema converted to its dialect, system instruction set, answer parsed" do
    transport = FakeTransport.new({ "candidates" => [ { "finishReason" => "STOP", "content" => { "parts" => [ { "text" => '{"answer":"no"}' } ] } } ] })
    reader = TrainedOn::Readers::GeminiReader.new(transport:)
    assert_equal({ "answer" => "no" }, reader.ask(system: "SYS", user: "USER", schema: SCHEMA))

    call = transport.calls.first
    assert_equal "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent", call[:url]
    assert_equal "g-test", call[:headers]["x-goog-api-key"]
    assert_equal "SYS", call[:body].dig(:systemInstruction, :parts, 0, :text)
    assert_equal "USER", call[:body].dig(:contents, 0, :parts, 0, :text)
    schema = call[:body].dig(:generationConfig, :responseSchema)
    assert_equal "OBJECT", schema["type"]
    assert_equal "STRING", schema.dig("properties", "answer", "type")
    assert_nil schema["additionalProperties"]
    assert_equal "application/json", call[:body].dig(:generationConfig, :responseMimeType)
  end

  test "Gemini: a blocked prompt is an error" do
    blocked = FakeTransport.new({ "promptFeedback" => { "blockReason" => "SAFETY" }, "candidates" => [] })
    assert_raises(TrainedOn::Readers::Error) { TrainedOn::Readers::GeminiReader.new(transport: blocked).ask(system: "s", user: "u", schema: SCHEMA) }
  end

  test "a transport failure surfaces as a reader error" do
    failing = FakeTransport.new(TrainedOn::Readers::Error.new("api.openai.com answered 503"))
    error = assert_raises(TrainedOn::Readers::Error) { TrainedOn::Readers::OpenAIReader.new(transport: failing).ask(system: "s", user: "u", schema: SCHEMA) }
    assert_match "503", error.message
  end

  test "Anthropic: structured output request, refusal handled" do
    block = Struct.new(:type, :text)
    message = Struct.new(:content, :stop_reason, :stop_details)
    messages = Class.new do
      attr_reader :params
      def initialize(reply) = @reply = reply
      def create(**params) = (@params = params; @reply)
    end
    client = Struct.new(:messages)

    ENV["ANTHROPIC_API_KEY"] = "a-test"
    good = messages.new(message.new([ block.new(:text, '{"answer":"yes"}') ], :end_turn, nil))
    reader = TrainedOn::Readers::AnthropicReader.new(client: client.new(good))
    assert_equal({ "answer" => "yes" }, reader.ask(system: "SYS", user: "USER", schema: SCHEMA))
    assert_equal "claude-opus-5", good.params[:model]
    assert_equal :json_schema, good.params.dig(:output_config, :format_, :type)
    assert_equal "SYS", good.params[:system_]

    refused = messages.new(message.new([], :refusal, nil))
    assert_raises(TrainedOn::Readers::Error) { TrainedOn::Readers::AnthropicReader.new(client: client.new(refused)).ask(system: "s", user: "u", schema: SCHEMA) }
  ensure
    ENV.delete("ANTHROPIC_API_KEY")
  end
end
