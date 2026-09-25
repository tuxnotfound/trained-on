module TrainedOn
  module Readers
    # OpenAI's Chat Completions API with a strict JSON schema response.
    class OpenAIReader < Base
      PROVIDER = "GPT (OpenAI)".freeze
      KEY_ENV = "OPENAI_API_KEY".freeze
      MODEL_ENV = "TRAINED_ON_OPENAI_MODEL".freeze
      DEFAULT_MODEL = "gpt-5".freeze
      BASE = "https://api.openai.com/v1".freeze

      def initialize(transport: Http.method(:json))
        @transport = transport
      end

      def available_models
        @transport.call(:get, "#{BASE}/models", headers: auth).fetch("data").map { |m| m["id"] }
      end

      private

      def auth = { "Authorization" => "Bearer #{key}" }

      def request(system, user, schema)
        body = {
          model:,
          messages: [ { role: "system", content: system }, { role: "user", content: user } ],
          response_format: { type: "json_schema", json_schema: { name: "answer", strict: true, schema: } }
        }
        response = @transport.call(:post, "#{BASE}/chat/completions", headers: auth, body:)
        choice = response.fetch("choices").first or raise Error, "#{PROVIDER} returned no choices"
        message = choice.fetch("message")
        raise Error, "#{PROVIDER} declined: #{message['refusal']}" if message["refusal"].present?
        raise Error, "#{PROVIDER} ran out of tokens" if choice["finish_reason"] == "length"
        JSON.parse(message.fetch("content").to_s)
      rescue JSON::ParserError, KeyError => e
        raise Error, "#{PROVIDER}: unreadable answer: #{e.message}"
      end
    end
  end
end
