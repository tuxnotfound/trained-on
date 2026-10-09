class PagesController < ApplicationController
  include PublicCache

  def methodology
    @documents = Document.includes(:vendor, :anchors, :clause_versions).order(:ota_path)
    @walked = @documents.sum { |d| d.versions_walked.to_i }
    @phantoms = @documents.sum { |d| d.phantom_versions.to_i }
    @states = @documents.sum { |d| d.clause_versions.size }
    @candidates = ClauseEvent.count
    @published = ClauseEvent.published.count
    @by_panel = ClauseEvent.published.where(decided_by: "panel").count
    @rejected = ClauseEvent.where(state: "rejected").count
  end

  def data
    @last_capture = ClauseVersion.maximum(:last_seen_at)
  end

  def press
    @walked = Document.sum(:versions_walked)
    @published = ClauseEvent.published.count
    @rows = Tier.verified.count
    @positions = position_events
  end

  # A plain-text map of the site for language models (llmstxt.org), carrying
  # the registry itself, so an answer engine can quote it with dates.
  def llms
    @tiers = visible_tiers.joins(:vendor).merge(Vendor.ordered).order(:id).includes(:vendor, document: :clause_versions)
    @positions = position_events
    @last_capture = ClauseVersion.maximum(:last_seen_at)
  end

  private

  def position_events = visible_events.where(classification: "position").includes(document: :vendor).order(occurred_on: :desc)
end
