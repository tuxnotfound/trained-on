module Admin
  class AnchorsController < BaseController
    def create
      document = Document.find(params[:document_id])
      anchor = document.anchors.create(phrase: params.require(:anchor)[:phrase].to_s.strip, note: params[:anchor][:note])
      redirect_to admin_document_path(document), (anchor.persisted? ? { notice: "Anchor added. Rebuild to apply it, and copy it into db/seeds/anchors.yml." } : { alert: anchor.errors.full_messages.to_sentence })
    end

    def destroy
      document = Document.find(params[:document_id])
      document.anchors.find(params[:id]).destroy!
      redirect_to admin_document_path(document), notice: "Anchor removed. Rebuild to apply it, and remove it from db/seeds/anchors.yml."
    end
  end
end
