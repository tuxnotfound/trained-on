class FeedsController < ApplicationController
  def changes
    @events = ClauseEvent.published.includes(document: :vendor).order(occurred_on: :desc).limit(50)
    @title = "Trained On: changes to AI vendors' training clauses"
    render :index
  end

  def vendor
    @vendor = Vendor.find_by!(slug: params[:slug])
    @events = ClauseEvent.published.joins(:document).where(documents: { vendor_id: @vendor.id }).includes(document: :vendor).order(occurred_on: :desc)
    @title = "Trained On: #{@vendor.name}"
    render :index
  end
end
