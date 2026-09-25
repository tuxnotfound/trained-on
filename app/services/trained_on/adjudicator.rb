require "anthropic"

module TrainedOn
  # Asks Claude Haiku for a first opinion on one candidate event: given only
  # the old and new clause text, is this a change of position, a scope change,
  # a disclosure, or wording? The model never searches for the clause (the
  # anchors do that) and its answer is only ever a suggestion shown to the
  # human reviewer. Skips silently when no API key is configured.
  class Adjudicator
    MODEL = "claude-haiku-4-5"

    SCHEMA = {
      type: "object",
      properties: {
        classification: { type: "string", enum: ClauseEvent::CLASSIFICATIONS },
        direction: { type: "string", enum: ClauseEvent::DIRECTIONS },
        material: { type: "boolean" },
        one_line: { type: "string" }
      },
      required: %w[classification direction material one_line],
      additionalProperties: false
    }.freeze

    SYSTEM = <<~PROMPT.freeze
      You compare two versions of the clause in an AI vendor's terms that says whether the vendor trains AI models on its users' data.
      Classify the change between OLD and NEW:
      - position: what is trained on, the default (opt-in or opt-out), who is covered, or whether an opt-out exists changed.
      - scope: a plan, product, data source or purpose was added to or removed from an existing rule.
      - disclosure: new description of existing practice; the position did not change.
      - wording: renames, links, punctuation, restatement with the same meaning.
      - churn: the texts differ only because different paragraphs were captured, not because the vendor changed anything.
      - unrelated: the change is not about training.
      direction is one of now_trains, no_longer_trains, scope_widened, scope_narrowed, disclosure, wording_only.
      material is true only for position and scope.
      one_line is one plain sentence a procurement reader understands, naming the vendor and quoting the decisive words. Do not speculate beyond the text.
    PROMPT

    def self.available? = ENV["ANTHROPIC_API_KEY"].present?

    def initialize(client: nil)
      @client = client
    end

    # Returns the parsed verdict hash, or nil when unavailable or declined.
    def call(event)
      return nil unless @client || self.class.available?

      message = client.messages.create(
        model: MODEL,
        max_tokens: 1024,
        system_: SYSTEM,
        messages: [ { role: "user", content: prompt(event) } ],
        output_config: { format_: { type: :json_schema, schema: SCHEMA } }
      )
      return nil if message.stop_reason == :refusal

      text = message.content.find { |block| block.type == :text }&.text
      text && JSON.parse(text).merge("model" => MODEL, "at" => Time.current.iso8601)
    rescue Anthropic::Errors::APIError, JSON::ParserError => e
      Rails.logger.warn("[adjudicator] event #{event.id}: #{e.class}: #{e.message}")
      nil
    end

    private

    def client = @client ||= Anthropic::Client.new

    def prompt(event)
      <<~TEXT
        Vendor: #{event.vendor.name}
        Document: #{event.document.name}
        Recorded: #{event.occurred_on.iso8601}

        OLD:
        #{event.from_version&.text.presence || "(no clause found)"}

        NEW:
        #{event.to_version.text.presence || "(no clause found)"}
      TEXT
    end
  end
end
