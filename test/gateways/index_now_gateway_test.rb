require "test_helper"

class IndexNowGatewayTest < ActiveSupport::TestCase
  test "posts the host, the key and the URLs" do
    request = stub_request(:post, "https://api.indexnow.org/indexnow")
      .with(body: { host: "trainedon.me", key: Rails.configuration.x.indexnow_key, urlList: [ "https://trainedon.me/" ] })
      .to_return(status: 202)
    assert_equal 1, IndexNowGateway.submit(host: "trainedon.me", urls: [ "https://trainedon.me/" ])
    assert_requested request
  end

  test "a refused key raises" do
    stub_request(:post, "https://api.indexnow.org/indexnow").to_return(status: 403)
    assert_raises(ApplicationGateway::Unauthorized) { IndexNowGateway.submit(host: "trainedon.me", urls: [ "https://trainedon.me/" ]) }
  end

  test "the key file at the site root holds the key" do
    key = Rails.configuration.x.indexnow_key
    assert_equal key, Rails.root.join("public/#{key}.txt").read
  end
end
