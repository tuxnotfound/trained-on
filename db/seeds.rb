# Loads the registry's hand-maintained data. Safe to re-run.
#   db/seeds/anchors.yml  vendors, tracked documents, clause anchors
#   db/seeds/tiers.yml    the registry rows (one per vendor plan)
# Anchors in the file replace the anchors in the database for that document.
require "yaml"

YAML.load_file(Rails.root.join("db/seeds/anchors.yml")).each_with_index do |row, i|
  vendor = Vendor.find_or_initialize_by(slug: row.fetch("slug"))
  vendor.update!(name: row.fetch("vendor"), ota_service: row.fetch("ota_service"), summary: row["summary"], position: i)
  row.fetch("documents").each do |doc|
    document = vendor.documents.find_or_initialize_by(ota_path: doc.fetch("ota_path"))
    document.update!(name: doc.fetch("name"), source_urls: doc.fetch("urls", []))
    wanted = doc.fetch("anchors")
    document.anchors.where.not(phrase: wanted).delete_all
    (wanted - document.anchors.pluck(:phrase)).each { |phrase| document.anchors.create!(phrase:) }
  end
end

tiers_file = Rails.root.join("db/seeds/tiers.yml")
if tiers_file.exist?
  YAML.load_file(tiers_file).each do |row|
    vendor = Vendor.find_by!(slug: row.fetch("vendor"))
    tier = vendor.tiers.find_or_initialize_by(name: row.fetch("name"))
    document = row["document"] && vendor.documents.find_by!(ota_path: row["document"])
    tier.update!(row.slice("answer", "opt_out", "quote", "position").merge(document:))
  end
end

puts "Seeded #{Vendor.count} vendors, #{Document.count} documents, #{Anchor.count} anchors, #{Tier.count} tiers."
