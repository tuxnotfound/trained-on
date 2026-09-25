module Admin
  class TiersController < BaseController
    # Marks a registry row as checked against the live vendor page today.
    def update
      tier = Tier.find(params[:id])
      tier.update!(verified_on: params[:unverify] ? nil : Date.current)
      redirect_to admin_root_path(anchor: "registry"), notice: "#{tier.vendor.name} / #{tier.name}: #{tier.verified_on ? "verified #{tier.verified_on}" : 'back to draft'}"
    end
  end
end
