require "test_helper"

class TrustedProxiesTest < ActionDispatch::IntegrationTest
  test "a visitor's own address survives Cloudflare and kamal-proxy" do
    # client -> Cloudflare edge (104.16.1.1) -> kamal-proxy (172.18.0.2) -> Rails
    get root_path, headers: { "REMOTE_ADDR" => "172.18.0.2", "X-Forwarded-For" => "203.0.113.9, 104.16.1.1" }
    assert_equal "203.0.113.9", request.remote_ip
  end

  test "a forged header cannot hide behind an untrusted address" do
    get root_path, headers: { "REMOTE_ADDR" => "198.51.100.7", "X-Forwarded-For" => "203.0.113.9" }
    assert_equal "198.51.100.7", request.remote_ip
  end

  test "every listed range parses" do
    assert CLOUDFLARE_IPS.all? { |c| IPAddr.new(c) }
    assert_equal 22, CLOUDFLARE_IPS.size
  end
end
