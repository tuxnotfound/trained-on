namespace :trained_on do
  desc "Rebuild clause history for every tracked document (or DOC=\"ChatGPT/Privacy Policy.md\")"
  task backfill: :environment do
    scope = ENV["DOC"] ? Document.where(ota_path: ENV["DOC"]) : Document.all
    scope.includes(:vendor).find_each do |document|
      run = TrainedOn::Backfill.new(document).call
      versions = document.clause_versions.count
      puts format("%-45s %3d states %3d events (%d new)", document.ota_path, versions, document.clause_events.count, run.created_events.size)
    end
  end
end

namespace :trained_on do
  desc "Apply suggested verdicts from db/seeds/reviews.yml to matching events. Never publishes."
  task apply_reviews: :environment do
    rows = YAML.load_file(Rails.root.join("db/seeds/reviews.yml"), permitted_classes: [ Date ])
    applied = rows.count do |row|
      document = Document.find_by!(ota_path: row.fetch("doc"))
      event = document.clause_events.find_by(occurred_on: row.fetch("date"), kind: row.fetch("kind", "change"))
      next warn("no event for #{row['doc']} #{row["date"]}") || false unless event
      next false if event.reviewed_at # a human decision always wins over a suggestion
      event.update!(row.slice("classification", "direction", "one_line", "note"))
    end
    unmatched = ClauseEvent.where(classification: nil).count
    puts "Applied #{applied} of #{rows.size} suggested verdicts. #{unmatched} events have no suggestion."
  end
end

namespace :trained_on do
  desc "Write a consistent copy of the primary SQLite database to storage/backups (upload it off-box from there)"
  task backup: :environment do
    source = ActiveRecord::Base.connection.raw_connection
    dir = Rails.root.join("storage/backups")
    FileUtils.mkdir_p(dir)
    path = dir.join("#{Rails.env}-#{Time.current.strftime('%Y%m%d-%H%M')}.sqlite3")
    destination = SQLite3::Database.new(path.to_s)
    backup = SQLite3::Backup.new(destination, "main", source, "main")
    backup.step(-1)
    backup.finish
    destination.close
    Dir.glob(dir.join("#{Rails.env}-*.sqlite3")).sort[0...-14].each { |old| File.delete(old) } # keep two weeks
    puts path
  end
end
