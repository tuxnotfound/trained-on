require "yaml"

module TrainedOn
  # Review decisions as a committed file, db/seeds/decisions.yml.
  #
  # Reviewing happens wherever the admin runs; the database is not the record.
  # Every publish, reject and verification is exported here (automatically in
  # development), committed, and replayed on deploy. Git becomes the audit
  # trail of what was published and when, and a fresh production database
  # ends up with exactly the reviewed state.
  #
  # Each event carries the hash prefix of the clause it was reviewed against.
  # If a rebuild ever produces a different clause for that date, the decision
  # is not applied and the event stays pending for a new review.
  module Decisions
    PATH = Rails.root.join("db/seeds/decisions.yml")
    HASH_PREFIX = 12
    HEADER = <<~TEXT
      # Review decisions (by the panel or a person), written by the review admin (development) or by
      # `bin/rails trained_on:export_decisions`. Replayed with
      # `bin/rails trained_on:apply_decisions`. Do not edit by hand: review in /admin.
    TEXT

    module_function

    def export!(path = PATH)
      events = ClauseEvent.where.not(reviewed_at: nil).includes(:to_version, :document).sort_by { |e| [ e.document.ota_path, e.occurred_on, e.kind ] }
      tiers = Tier.where.not(confirmed_by: nil).includes(:vendor).sort_by { |t| [ t.vendor.slug, t.position ] }
      data = {
        "events" => events.map do |e|
          {
            "doc" => e.document.ota_path, "date" => e.occurred_on.iso8601, "kind" => e.kind,
            "clause" => e.to_version.sha256[0, HASH_PREFIX], "state" => e.state,
            "classification" => e.classification, "direction" => e.direction,
            "one_line" => e.one_line, "note" => e.note, "decided_by" => e.decided_by, "reviewed_at" => e.reviewed_at.utc.iso8601
          }.compact
        end,
        "tiers" => tiers.map { |t| { "vendor" => t.vendor.slug, "name" => t.name, "confirmed_by" => t.confirmed_by, "confirmed_at" => t.confirmed_at&.utc&.iso8601 }.compact }
      }
      File.write(path, HEADER + data.to_yaml.delete_prefix("---\n"))
      data
    end

    Result = Data.define(:applied, :stale, :missing)

    def apply!(path = PATH)
      return Result.new(applied: 0, stale: [], missing: []) unless File.exist?(path)
      data = YAML.safe_load_file(path) || {}
      applied, stale, missing = 0, [], []

      Array(data["events"]).each do |row|
        document = Document.find_by(ota_path: row.fetch("doc"))
        event = document&.clause_events&.includes(:to_version)&.find_by(occurred_on: row.fetch("date"), kind: row.fetch("kind"))
        next missing << "#{row['doc']} #{row['date']}" unless event
        next stale << "#{row['doc']} #{row['date']}" unless event.to_version.sha256.start_with?(row.fetch("clause"))
        event.update!(row.slice("state", "classification", "direction", "one_line", "note", "decided_by").merge("reviewed_at" => Time.iso8601(row.fetch("reviewed_at"))))
        applied += 1
      end

      Array(data["tiers"]).each do |row|
        tier = Vendor.find_by(slug: row.fetch("vendor"))&.tiers&.find_by(name: row.fetch("name"))
        next missing << "tier #{row['vendor']} / #{row['name']}" unless tier
        tier.update_columns(confirmed_by: row.fetch("confirmed_by"), confirmed_at: row["confirmed_at"] && Time.iso8601(row["confirmed_at"]))
        applied += 1
      end

      Result.new(applied:, stale:, missing:)
    end
  end
end
