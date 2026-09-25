module TrainedOn
  module Readers
    # Google's Gemini API with a JSON response schema.
    class GeminiReader < Base
      PROVIDER = "Gemini (Google)".freeze
      KEY_ENV = "GEMINI_API_KEY".freeze
      MODEL_ENV = "TRAINED_ON_GEMINI_MODEL".freeze
      DEFAULT_MODEL = "gemini-3.1-pro-preview".freeze
      BASE = "https://generativelanguage.googleapis.com/v1beta".freeze

      def initialize(transport: Http.method(:json))
        @transport = transport
      end

      def available_models
        @transport.call(:get, "#{BASE}/models?pageSize=200", headers: auth).fetch("models").map { |m| m["name"].delete_prefix("models/") }
      end

      # Gemini takes a subset of JSON Schema: upper-case types, no additionalProperties.
      def self.schema_for(schema)
        case schema
        when Hash
          schema.except("additionalProperties").to_h do |k, v|
            [ k, k == "type" && v.is_a?(String) ? v.upcase : schema_for(v) ]
          end
        when Array then schema.map { |v| schema_for(v) }
        else schema
        end
      end

      private

      def auth = { "x-goog-api-key" => key }

      def request(system, user, schema)
        body = {
          systemInstruction: { parts: [ { text: system } ] },
          contents: [ { role: "user", parts: [ { text: user } ] } ],
          generationConfig: { responseMimeType: "application/json", responseSchema: self.class.schema_for(schema) }
        }
        response = @transport.call(:post, "#{BASE}/models/#{model}:generateContent", headers: auth, body:)
        raise Error, "#{PROVIDER} blocked the prompt: #{response.dig('promptFeedback', 'blockReason')}" if response.dig("promptFeedback", "blockReason")
        candidate = response.fetch("candidates", []).first or raise Error, "#{PROVIDER} returned no candidates"
        text = candidate.dig("content", "parts", 0, "text")
        raise Error, "#{PROVIDER} stopped: #{candidate['finishReason']}" if text.blank?
        JSON.parse(text)
      rescue JSON::ParserError => e
        raise Error, "#{PROVIDER}: unreadable answer: #{e.message}"
      end
    end
  end
end
