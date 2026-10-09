require "net/http"

# Base class for every external API. All outbound HTTP in the app goes through a gateway,
# so a service never sees a URL, a header or a status code.
# Copied from control-tower/templates/rails. The rules are in control-tower/RAILS.md.
#
#   class GithubGateway < ApplicationGateway
#     def self.stars(repo)
#       get("/repos/#{repo}", headers: auth_headers)[:stargazers_count]
#     end
#
#     def self.base_url
#       "https://api.github.com"
#     end
#
#     def self.auth_headers
#       { "Authorization" => "Bearer #{Rails.application.credentials.github_token}" }
#     end
#     private_class_method :base_url, :auth_headers
#   end
#
# Callers rescue only the errors they can act on, and let the rest raise:
#
#   GithubGateway.stars(repo)
# rescue ApplicationGateway::NotFound
#   0
class ApplicationGateway
  class Error < StandardError
    attr_reader :status, :body

    def initialize(message = nil, status: nil, body: nil)
      @status = status
      @body = body
      super(message || "HTTP #{status}")
    end
  end

  class ConnectionFailed < Error; end    # DNS, refused, timeout, TLS
  class ClientError < Error; end         # any 4xx without a class of its own
  class Unauthorized < ClientError; end  # 401, 403
  class NotFound < ClientError; end      # 404
  class RateLimited < ClientError; end   # 429
  class ServerError < Error; end         # 5xx

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 15

  class << self
    private

    def get(path, query: {}, headers: {})
      request(Net::HTTP::Get, path, query:, headers:)
    end

    def post(path, body: nil, query: {}, headers: {})
      request(Net::HTTP::Post, path, query:, headers:, body:)
    end

    def put(path, body: nil, query: {}, headers: {})
      request(Net::HTTP::Put, path, query:, headers:, body:)
    end

    def patch(path, body: nil, query: {}, headers: {})
      request(Net::HTTP::Patch, path, query:, headers:, body:)
    end

    def delete(path, query: {}, headers: {})
      request(Net::HTTP::Delete, path, query:, headers:)
    end

    def base_url
      raise NotImplementedError, "#{name} must define self.base_url"
    end

    # TLS certificates are always verified. Never pass verify_mode here.
    def request(verb, path, query:, headers:, body: nil)
      uri = URI("#{base_url}#{path}")
      uri.query = URI.encode_www_form(query) if query.any?

      http_request = verb.new(uri, { "Accept" => "application/json" }.merge(headers))
      if body
        http_request["Content-Type"] = "application/json"
        http_request.body = body.to_json
      end

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
        open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) { |http| http.request(http_request) }
      parse(response)
    rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => error
      raise ConnectionFailed, "#{verb::METHOD} #{uri.host}: #{error.message}"
    end

    # A 2xx returns parsed JSON with symbol keys (or the raw body when it is not JSON).
    # Anything else raises the matching error class.
    def parse(response)
      status = response.code.to_i
      raise error_class_for(status).new(status:, body: response.body) unless status.between?(200, 299)
      return response.body unless response.content_type.to_s.include?("json")

      JSON.parse(response.body, symbolize_names: true) if response.body.present?
    end

    def error_class_for(status)
      case status
      when 401, 403 then Unauthorized
      when 404 then NotFound
      when 429 then RateLimited
      when 400..499 then ClientError
      when 500..599 then ServerError
      else Error
      end
    end
  end
end
