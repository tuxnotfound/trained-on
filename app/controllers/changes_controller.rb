class ChangesController < ApplicationController
  def index
    @events = visible_events.includes(document: :vendor).order(occurred_on: :desc)
    @events = @events.where(classification: params[:type]) if params[:type].in?(ClauseEvent::PUBLIC_CLASSIFICATIONS)
  end

  def show
    @event = ClauseEvent.find_by_slug!(params[:slug])
    raise ActiveRecord::RecordNotFound unless visible_events.exists?(@event.id)
    @diff = TrainedOn::WordDiff.new(@event.from_version&.text, @event.to_version.text)
    @vendor = @event.vendor
    @related = visible_events.joins(:document).where(documents: { vendor_id: @vendor.id }).where.not(id: @event.id).order(occurred_on: :desc).limit(5)
  end
end
