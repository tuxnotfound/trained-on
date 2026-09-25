module Admin
  class EventsController < BaseController
    def index
      @state = params[:state].presence_in(ClauseEvent::STATES) || "pending"
      @events = ClauseEvent.where(state: @state).includes(document: :vendor).order(:occurred_on)
      @counts = ClauseEvent.group(:state).count
      @tiers = Tier.includes(:vendor, document: :clause_versions).order("vendors.position", :position).references(:vendor)
      @unanchored = Document.includes(:vendor, :clause_versions).select { |d| d.current_version&.unanchored_hits.present? }
    end

    def show
      @event = ClauseEvent.includes(:from_version, :to_version, document: %i[vendor anchors]).find(params[:id])
      @diff = TrainedOn::WordDiff.new(@event.from_version&.text, @event.to_version.text)
    end

    def update
      @event = ClauseEvent.find(params[:id])
      @event.assign_attributes(event_params)
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

    def next_pending_path
      following = ClauseEvent.pending.where("occurred_on > ? OR (occurred_on = ? AND id > ?)", @event.occurred_on, @event.occurred_on, @event.id).order(:occurred_on, :id).first
      following ? admin_event_path(following.id) : admin_root_path
    end
  end
end
