require "anthropic"

module TrainedOn
  module Readers
    class AnthropicReader < Base
      PROVIDER = "Claude (Anthropic)".freeze
      KEY_ENV = "ANTHROPIC_API_KEY".freeze
      MODEL_ENV = "TRAINED_ON_ANTHROPIC_MODEL".freeze
      DEFAULT_MODEL = "claude-opus-5".freeze

      def initialize(client: nil)
        @client = client
      end

      def available_models
        client.models.list.to_enum.map(&:id)
      rescue Anthropic::Errors::APIError => e
        raise Error, "#{PROVIDER}: #{e.message}"
      end

      private

      def client = @client ||= Anthropic::Client.new

      def request(system, user, schema)
        message = client.messages.create(
          model:, max_tokens: 8000, system_: system,
          messages: [ { role: "user", content: user } ],
          output_config: { format_: { type: :json_schema, schema: } }
        )
        raise Error, "#{PROVIDER} declined (#{message.stop_details&.category || 'refusal'})" if message.stop_reason == :refusal
        raise Error, "#{PROVIDER} ran out of tokens" if message.stop_reason == :max_tokens
        text = message.content.find { |block| block.type == :text }&.text
        raise Error, "#{PROVIDER} returned no text" if text.blank?
        JSON.parse(text)
      rescue Anthropic::Errors::APIError => e
        raise Error, "#{PROVIDER}: #{e.class.name.demodulize}: #{e.message.to_s[0, 300]}"
      rescue JSON::ParserError => e
        raise Error, "#{PROVIDER}: unreadable answer: #{e.message}"
      end
    end
  end
end
