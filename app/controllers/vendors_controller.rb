class VendorsController < ApplicationController
  def show
    @vendor = Vendor.find_by!(slug: params[:slug])
    @tiers = visible_tiers.where(vendor: @vendor).includes(document: :clause_versions).order(:position)
    @events = visible_events.joins(:document).where(documents: { vendor_id: @vendor.id })
                            .includes(:from_version, :to_version, :document).order(occurred_on: :desc)
    @documents = @vendor.documents.includes(:clause_versions).order(:name)
    raise ActiveRecord::RecordNotFound if @tiers.empty? && @events.empty?
  end
end
