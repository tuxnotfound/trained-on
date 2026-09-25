namespace :trained_on do
  desc "Rebuild clause history for every tracked document (or DOC=\"ChatGPT/Privacy Policy.md\")"
  task backfill: :environment do
    TrainedOn::Corpus.versions_repo.ensure_clone!
    scope = ENV["DOC"] ? Document.where(ota_path: ENV["DOC"]) : Document.all
    scope.includes(:vendor).find_each do |document|
      run = TrainedOn::Backfill.new(document).call
      versions = document.clause_versions.count
      puts format("%-45s %3d states %3d events (%d new)", document.ota_path, versions, document.clause_events.count, run.created_events.size)
    end
    Tier.refresh_verification!
  end

  desc "Run the panel over pending change events and unconfirmed registry rows (FORCE=1 to redo)"
  task panel: :environment do
    panel = TrainedOn::Panel.new
    puts "Readers: #{panel.readers.map { |r| "#{r.provider} #{r.model}" }.join(', ').presence || 'none configured'}"
    puts "Fewer than #{TrainedOn::Panel::MIN_READERS} readers: the panel advises but decides nothing." unless panel.enough_readers?
    PanelJob.perform_now(force: ENV["FORCE"].present?)
    puts ClauseEvent.group(:state, :decided_by).count.map { |(state, by), n| "#{n} #{state}#{by ? " by #{by}" : ''}" }.sort.join("\n")
    puts "Rows: #{Tier.verified.count} public, #{Tier.unconfirmed.count} unconfirmed, #{Tier.where(verified_on: nil).count} with the quote gone."
    puts "Waiting for a person:"
    ClauseEvent.pending.includes(document: :vendor).chronological.each { |e| puts "  #{e.occurred_on} #{e.document.ota_path}: #{e.panel_reason || 'panel has not run'}" }
  end

  desc "Check each configured reader's key and model id against the provider"
  task panel_check: :environment do
    TrainedOn::Readers.all.each do |reader|
      unless reader.configured?
        puts "#{reader.provider}: no key (#{reader.class::KEY_ENV})"
        next
      end
      begin
        models = reader.available_models
        found = models.include?(reader.model)
        puts "#{reader.provider}: key ok; model #{reader.model} #{found ? 'found' : 'NOT FOUND'} (set #{reader.class::MODEL_ENV}). Newest listed: #{models.sort.last(6).join(', ')}"
      rescue TrainedOn::Readers::Error => e
        puts "#{reader.provider}: #{e.message}"
      end
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

namespace :trained_on do
  desc "Write human review decisions to db/seeds/decisions.yml"
  task export_decisions: :environment do
    data = TrainedOn::Decisions.export!
    puts "Exported #{data['events'].size} event decisions and #{data['tiers'].size} verified rows."
  end

  desc "Replay db/seeds/decisions.yml onto the database (publishes what a human published)"
  task apply_decisions: :environment do
    result = TrainedOn::Decisions.apply!
    puts "Applied #{result.applied} decisions."
    result.stale.each { |s| warn "Clause changed since review, left pending: #{s}" }
    result.missing.each { |s| warn "No match for: #{s}" }
  end

  desc "Fresh database to reviewed state: seed, rebuild history, load suggestions, replay decisions"
  task bootstrap: :environment do
    %w[db:seed trained_on:backfill trained_on:apply_reviews trained_on:apply_decisions].each { |t| Rake::Task[t].invoke }
    Tier.refresh_verification!
  end
end
