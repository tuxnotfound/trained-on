class PagesController < ApplicationController
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

  def data; end
end
