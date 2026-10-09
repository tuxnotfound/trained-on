# Tells search engines which public pages a newly published change touched:
# its own page, its vendor's page, and the pages that list changes. Without
# this a new change page waits for a crawler to find it through the sitemap.
class Changes::AnnounceService < ApplicationService
  include Rails.application.routes.url_helpers

  attr_accessor :since
  attr_reader :urls

  validates :since, presence: true

  private

  def execute
    events = ClauseEvent.published.where(reviewed_at: since..).includes(document: :vendor).order(:occurred_on).to_a
    @urls = page_urls(events)
    IndexNowGateway.submit(host: default_url_options.fetch(:host), urls:) if urls.any?
  end

  def page_urls(events)
    return [] if events.empty?

    vendors = events.map(&:vendor).uniq
    events.map { |event| change_url(event) } + vendors.map { |vendor| vendor_url(vendor) } + [ changes_url, root_url, press_url ]
  end

  # The key file lives on the public host, so the URLs must name it in every environment.
  def default_url_options
    Rails.application.config.action_controller.default_url_options.presence || { host: "trainedon.me", protocol: "https" }
  end
end
