# IndexNow: one request tells Bing, Yandex, Seznam and Naver which pages
# changed. Google does not take part.
class IndexNowGateway < ApplicationGateway
  # Returns how many URLs were handed over.
  def self.submit(host:, urls:)
    post("/indexnow", body: { host:, key: Rails.configuration.x.indexnow_key, urlList: urls })
    urls.size
  end

  def self.base_url
    "https://api.indexnow.org"
  end
  private_class_method :base_url
end
