# Behind Cloudflare, every request arrives from a Cloudflare address, and
# kamal-proxy on the box adds its own. Rails only looks past a proxy it trusts,
# so without this list `request.remote_ip` is Cloudflare's edge, the admin
# login's rate limit counts every visitor as one client, and a stranger can
# lock the reviewer out. Setting trusted_proxies replaces Rails' defaults, so
# the private ranges kamal-proxy uses are listed again here.
#
# Cloudflare's ranges, from https://www.cloudflare.com/ips/ on 2026-09-28.
# `bin/rails trained_on:cloudflare_ips` compares this list with the current one.
require "ipaddr"

CLOUDFLARE_IPS = %w[
  173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18
  108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 197.234.240.0/22 198.41.128.0/17
  162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22
  2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32
  2a06:98c0::/29 2c0f:f248::/32
].freeze

PRIVATE_PROXIES = %w[127.0.0.0/8 ::1/128 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fc00::/7].freeze

Rails.application.config.action_dispatch.trusted_proxies = (PRIVATE_PROXIES + CLOUDFLARE_IPS).map { |cidr| IPAddr.new(cidr) }
