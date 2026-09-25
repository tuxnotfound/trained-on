class ApplicationController < ActionController::Base
  allow_browser versions: :modern

  helper_method :preview?, :visible_event?

  private

  # Set from /admin. Shows pending events and unverified rows on the public
  # pages, marked as drafts, so the reviewer sees exactly what would publish.
  # In development, ?preview=1 also works, for screenshots and quick looks.
  def preview? = cookies.signed[:preview] == "1" || (Rails.env.development? && params[:preview] == "1")

  def visible_events = preview? ? ClauseEvent.publishable_draft.or(ClauseEvent.published) : ClauseEvent.published
  def visible_event?(event) = visible_events.exists?(event.id)
  def visible_tiers = preview? ? Tier.all : Tier.verified

  def visible_vendors
    Vendor.ordered.includes(:tiers).select do |vendor|
      vendor.tiers.any? { |t| preview? || t.verified_on } || visible_events.joins(:document).where(documents: { vendor_id: vendor.id }).exists?
    end
  end
end
