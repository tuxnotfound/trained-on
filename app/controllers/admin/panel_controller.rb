module Admin
  class PanelController < BaseController
    # Queues the panel over everything pending. Runs in the background: three
    # readers per event take a minute or two each.
    def run
      PanelJob.perform_later(force: params[:force].present?)
      redirect_to admin_root_path, notice: "Panel queued for #{ClauseEvent.pending.where(kind: 'change').count} pending events and #{Tier.unconfirmed.count} rows. Refresh in a few minutes."
    end
  end
end
