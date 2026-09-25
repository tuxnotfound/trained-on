module Admin
  class TiersController < BaseController
    after_action :export_decisions, only: :update

    # A person confirms (or withdraws) the answer label of a registry row. The
    # quote itself is checked mechanically against the latest capture.
    def update
      tier = Tier.find(params[:id])
      if params[:withdraw]
        tier.update_columns(confirmed_by: nil, confirmed_at: nil)
      elsif params[:panel]
        PanelJob.perform_later(tier_ids: [ tier.id ])
        return redirect_to(admin_root_path(anchor: "registry"), notice: "Panel queued for #{tier.vendor.name} / #{tier.name}.")
      else
        tier.update_columns(confirmed_by: "human", confirmed_at: Time.current)
      end
      redirect_to admin_root_path(anchor: "registry"), notice: "#{tier.vendor.name} / #{tier.name}: #{tier.confirmed? ? 'confirmed by you' : 'confirmation withdrawn'}"
    end
  end
end
