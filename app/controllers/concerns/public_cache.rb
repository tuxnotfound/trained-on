# Public pages are cacheable at Cloudflare's edge for a few minutes, so a launch
# spike is served by the edge and not by the box. Only a plain 200 GET outside
# preview qualifies: preview renders drafts, a flash is personal, and an error is
# not worth keeping. Everything else keeps Rails' private default. The edge only
# stores a response that carries no Set-Cookie, so public pages must not touch the
# session either; the layout skips the CSRF token outside preview for that reason.
module PublicCache
  extend ActiveSupport::Concern

  EDGE_TTL = 10.minutes
  BROWSER_TTL = 1.minute

  included do
    after_action :set_public_cache_control
  end

  private

  def set_public_cache_control
    return unless request.get? && response.ok? && !preview? && flash.empty?

    # If the box errors or is down, the edge keeps serving the last good copy for a day.
    expires_in BROWSER_TTL, public: true, "s-maxage": EDGE_TTL.to_i, stale_while_revalidate: 1.hour.to_i, stale_if_error: 1.day.to_i
  end
end
