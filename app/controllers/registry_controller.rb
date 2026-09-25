class RegistryController < ApplicationController
  def index
    @vendors = visible_vendors
    @tiers = visible_tiers.includes(:vendor, document: :clause_versions).group_by(&:vendor_id)
    @recent = visible_events.includes(document: :vendor).order(occurred_on: :desc).limit(6)
    @last_capture = ClauseVersion.maximum(:last_seen_at)
  end
end
