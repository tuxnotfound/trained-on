module Admin
  class DocumentsController < BaseController
    def show
      @document = Document.includes(:anchors, :clause_versions, :vendor).find(params[:id])
    end

    # Re-derives history after an anchor change. Reviews carry over.
    def rebuild
      document = Document.find(params[:id])
      run = TrainedOn::Backfill.new(document).call
      redirect_to admin_document_path(document), notice: "Rebuilt: #{document.clause_versions.count} states, #{run.created_events.size} new events."
    end
  end
end
