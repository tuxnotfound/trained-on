require "csv"

module Api
  module V1
    # The registry as data, ODC-By like the corpus it derives from.
    class VendorsController < ApplicationController
      def index
        tiers = Tier.verified.includes(:vendor, document: :clause_versions).order("vendors.position", :position).references(:vendor)
        respond_to do |format|
          format.json { render json: { license: LICENSE, attribution: ATTRIBUTION, generated_at: Time.current.iso8601, rows: tiers.map { |t| row(t) } } }
          format.csv { send_data csv(tiers), type: "text/csv", filename: "trained-on-registry.csv" }
        end
      end

      LICENSE = "ODC-By-1.0"
      ATTRIBUTION = "Trained On (trained-on), derived from Open Terms Archive contributors' genai-contrib collection, ODC-By 1.0"
      COLUMNS = %w[vendor plan answer answer_text quote document effective_on verified_on source_url].freeze

      private

      def row(tier)
        {
          "vendor" => tier.vendor.name, "plan" => tier.name, "answer" => tier.answer, "answer_text" => tier.answer_text,
          "quote" => tier.quote, "document" => tier.document&.name, "effective_on" => tier.effective_on&.iso8601,
          "verified_on" => tier.verified_on&.iso8601, "confirmed_by" => tier.confirmed_by, "source_url" => tier.document&.ota_history_url,
          "opt_out" => tier.opt_out, "vendor_url" => vendor_url(tier.vendor)
        }
      end

      def csv(tiers)
        CSV.generate do |out|
          out << COLUMNS + %w[opt_out]
          tiers.each { |t| out << row(t).values_at(*COLUMNS, "opt_out") }
        end
      end
    end
  end
end
