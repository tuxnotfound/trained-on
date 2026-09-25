require "csv"

module Api
  module V1
    class ChangesController < ApplicationController
      COLUMNS = %w[date vendor document classification direction summary decided_by previous_capture url ota_commit].freeze

      def index
        events = ClauseEvent.published.includes(:from_version, :to_version, document: :vendor).order(occurred_on: :desc)
        respond_to do |format|
          format.json { render json: { license: VendorsController::LICENSE, attribution: VendorsController::ATTRIBUTION, rows: events.map { |e| row(e) } } }
          format.csv { send_data CSV.generate { |out| out << COLUMNS; events.each { |e| out << row(e).values_at(*COLUMNS) } }, type: "text/csv", filename: "trained-on-changes.csv" }
        end
      end

      private

      def row(event)
        {
          "date" => event.occurred_on.iso8601, "vendor" => event.vendor.name, "document" => event.document.name,
          "classification" => event.classification, "direction" => event.direction, "summary" => event.one_line,
          "decided_by" => event.decided_by,
          "previous_capture" => event.from_version&.last_seen_at&.to_date&.iso8601,
          "url" => change_url(event), "ota_commit" => event.to_version.ota_commit_url
        }
      end
    end
  end
end
