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
    @positions = visible_events.where(classification: "position").includes(document: :vendor).order(occurred_on: :desc)
  end
end
