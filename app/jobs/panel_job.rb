# Runs the panel over pending events and unconfirmed registry rows. Used by
# the nightly refresh, the admin's "run the panel" buttons and the rake task.
class PanelJob < ApplicationJob
  queue_as :default

  def perform(event_ids: nil, tier_ids: nil, force: false)
    panel = TrainedOn::Panel.new
    events = event_ids ? ClauseEvent.where(id: event_ids) : ClauseEvent.pending
    events = events.where(panel: nil) unless force || event_ids
    events.includes(:from_version, :to_version, document: :vendor).find_each { |event| panel.review_event(event) }

    tiers = tier_ids ? Tier.where(id: tier_ids) : Tier.unconfirmed
    tiers = tiers.where(panel: nil) unless force || tier_ids
    tiers.includes(:vendor, document: :clause_versions).find_each { |tier| panel.check_tier(tier) }

    TrainedOn::Decisions.export! if Rails.env.development?
  end
end
