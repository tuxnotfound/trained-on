# IndexNow: one request tells Bing, Yandex, Seznam and Naver which pages
# changed. Google does not take part. It goes to Bing's own endpoint, which
# shares it with the others: a batch sent to api.indexnow.org on 2026-10-09
# never showed in Bing Webmaster Tools, and one sent to Bing did.
class IndexNowGateway < ApplicationGateway
  # Returns how many URLs were handed over.
  def self.submit(host:, urls:)
    post("/indexnow", body: { host:, key: Rails.configuration.x.indexnow_key, urlList: urls })
    urls.size
  end

  def self.base_url
    "https://www.bing.com"
  end
  private_class_method :base_url
end
