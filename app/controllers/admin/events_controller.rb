module Admin
  class EventsController < BaseController
    after_action :export_decisions, only: :update

    def index
      @state = params[:state].presence_in(ClauseEvent::STATES) || "pending"
      @filter = params[:classification].presence_in(ClauseEvent::CLASSIFICATIONS)
      @events = ClauseEvent.where(state: @state).includes(document: :vendor).order(:occurred_on)
      @events = @events.where(classification: @filter) if @filter
      @by_class = ClauseEvent.where(state: @state).group(:classification).count
      @counts = ClauseEvent.group(:state).count
      @tiers = Tier.includes(:vendor, document: :clause_versions).order("vendors.position", :position).references(:vendor)
      @panel = TrainedOn::Panel.new
      @unanchored = Document.includes(:vendor, :clause_versions).select { |d| d.current_version&.unanchored_hits.present? }
    end

    def show
      @event = ClauseEvent.includes(:from_version, :to_version, document: %i[vendor anchors]).find(params[:id])
      @diff = TrainedOn::WordDiff.new(@event.from_version&.text, @event.to_version.text)
    end

    def panel
      event = ClauseEvent.find(params[:id])
      PanelJob.perform_later(event_ids: [ event.id ])
      redirect_to admin_event_path(event.id), notice: "Panel queued for this event. Refresh in a minute or two."
    end

    def update
      @event = ClauseEvent.find(params[:id])
      @event.assign_attributes(event_params)
      @event.decided_by = "human" if params[:decision].in?(%w[publish reject])
      case params[:decision]
      when "publish" then @event.state = "published"
      when "reject" then @event.state = "rejected"
      when "reopen" then @event.state = "pending"
      end
      @event.reviewed_at = Time.current unless @event.state == "pending"

      if @event.save
        respond_to do |format|
          format.turbo_stream { render turbo_stream: turbo_stream.replace(@event, partial: "admin/events/row", locals: { event: @event }) }
          format.html { redirect_to next_pending_path, notice: "#{@event.state.capitalize}: #{@event.headline}" }
        end
      else
        @diff = TrainedOn::WordDiff.new(@event.from_version&.text, @event.to_version.text)
        render :show, status: :unprocessable_content
      end
    end

    private

    def event_params = params.fetch(:clause_event, {}).permit(:classification, :direction, :one_line, :note)

    # Walks the queue in date order, staying within the classification the
    # reviewer filtered on, if any.
    def next_pending_path
      filter = params[:filter].presence_in(ClauseEvent::CLASSIFICATIONS)
      scope = ClauseEvent.pending
      scope = scope.where(classification: filter) if filter
      following = scope.where("occurred_on > ? OR (occurred_on = ? AND id > ?)", @event.occurred_on, @event.occurred_on, @event.id).order(:occurred_on, :id).first
      following ||= scope.order(:occurred_on, :id).first
      following ? admin_event_path(following.id, filter:) : admin_root_path(classification: filter)
    end
  end
end
