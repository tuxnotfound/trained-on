class SitemapsController < ApplicationController
  include PublicCache

  # Like the feeds, only reviewed material, whoever asks: the vendor pages that
  # would render and every published change page.
  def show
    @events = ClauseEvent.published.includes(document: :vendor).order(occurred_on: :desc)
    vendor_ids = Tier.verified.pluck(:vendor_id) | @events.map { |event| event.document.vendor_id }
    @vendors = Vendor.where(id: vendor_ids).ordered
  end
end
