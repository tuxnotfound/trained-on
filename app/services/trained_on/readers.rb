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

      module_function

      def json(method, url, headers: {}, body: nil, timeout: 180)
        uri = URI(url)
        http = ::Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 15
        http.read_timeout = timeout
        request = (method == :get ? ::Net::HTTP::Get : ::Net::HTTP::Post).new(uri, { "Content-Type" => "application/json" }.merge(headers))
        request.body = JSON.generate(body) if body
        response = http.request(request)
        raise Error, "#{uri.host} answered #{response.code}: #{response.body.to_s[0, 300]}" unless response.is_a?(::Net::HTTPSuccess)
        JSON.parse(response.body)
      rescue *NETWORK_ERRORS => e
        raise Error, "#{uri.host}: #{e.class}: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "#{uri.host}: unreadable response: #{e.message}"
      end
    end
  end
end
