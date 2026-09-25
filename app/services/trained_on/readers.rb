require "net/http"
require "json"

module TrainedOn
  # The panel's readers: one language model from each of three companies.
  # A reader answers one question with one JSON object. It knows nothing about
  # the other readers, and it never sees the suggested verdict.
  module Readers
    class Error < StandardError; end

    def self.all = [ AnthropicReader.new, OpenAIReader.new, GeminiReader.new ]
    def self.configured = all.select(&:configured?)

    class Base
      def provider = self.class::PROVIDER
      def key = ENV[self.class::KEY_ENV].presence
      def model = ENV[self.class::MODEL_ENV].presence || self.class::DEFAULT_MODEL
      def configured? = key.present?

      # Returns the parsed JSON object, or raises Readers::Error.
      def ask(system:, user:, schema:)
        raise Error, "#{provider}: no API key" unless configured?
        request(system, user, schema)
      end

      # The provider's own list of model ids, for trained_on:panel_check.
      def available_models = raise(NotImplementedError)
    end

    # Plain HTTPS JSON calls for the providers without an SDK in this app.
    module Http
      NETWORK_ERRORS = [ ::SocketError, ::Errno::ECONNREFUSED, ::Errno::ECONNRESET, ::Errno::EHOSTUNREACH, ::Net::OpenTimeout, ::Net::ReadTimeout, ::OpenSSL::SSL::SSLError, ::IOError ].freeze

      # Overloaded or rate-limited answers are retried a little; anything else is final.
      RETRY_CODES = %w[429 503 529].freeze
      RETRY_DELAYS = [ 20, 45 ].freeze

      module_function

      def json(method, url, headers: {}, body: nil, timeout: 180, delays: RETRY_DELAYS)
        uri = URI(url)
        attempt = 0
        loop do
          response = send_request(uri, method, headers, body, timeout)
          return JSON.parse(response.body) if response.is_a?(::Net::HTTPSuccess)
          if RETRY_CODES.include?(response.code) && attempt < delays.size
            sleep(delays[attempt])
            attempt += 1
            next
          end
          raise Error, "#{uri.host} answered #{response.code}: #{error_text(response.body)}"
        end
      rescue *NETWORK_ERRORS => e
        raise Error, "#{uri.host}: #{e.class}: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "#{uri.host}: unreadable response: #{e.message}"
      end

      def send_request(uri, method, headers, body, timeout)
        http = ::Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = timeout
        request = (method == :get ? ::Net::HTTP::Get : ::Net::HTTP::Post).new(uri, { "Content-Type" => "application/json" }.merge(headers))
        request.body = JSON.generate(body) if body
        http.request(request)
      end

      # The provider's own message, without its help links, so the reason
      # (a quota, a retired model) survives into the review queue and the digest.
      def error_text(body)
        message = JSON.parse(body.to_s).dig("error", "message")
        (message.presence || body.to_s).gsub(%r{https?://\S+}, "").gsub(/\s+/, " ").strip[0, 600]
      rescue JSON::ParserError
        body.to_s.gsub(/\s+/, " ")[0, 600]
      end
    end
  end
end
