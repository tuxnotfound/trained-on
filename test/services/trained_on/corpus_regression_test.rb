require "test_helper"

# Runs the committed anchors over the real OTA corpus. Guards the two findings
# the build rests on: the six locator artefacts from the human read stay gone,
# and the real changes of position are still found. Skipped without a clone.
class TrainedOn::CorpusRegressionTest < ActiveSupport::TestCase
  CORPUS = TrainedOn::Corpus.versions_repo

  setup do
    skip "OTA corpus not cloned (see README)" unless CORPUS.present?
    skip "SKIP_CORPUS set" if ENV["SKIP_CORPUS"]
    load Rails.root.join("db/seeds.rb")
  end

  def events_for(ota_path)
    document = Document.find_by!(ota_path:)
    TrainedOn::Backfill.new(document, corpus: CORPUS).call
    document.clause_events.pluck(:occurred_on, :kind).map { |date, kind| [ date.iso8601, kind ] }
  end

  test "ChatGPT privacy: no event for the false Temporary Chat removal, the ad-controls edit or the ads-data edit" do
    dates = events_for("ChatGPT/Privacy Policy.md").map(&:first)
    %w[2026-09-17 2026-07-15 2026-08-25].each { |d| assert_not_includes dates, d }
    assert_includes dates, "2026-05-18"
  end

  test "Claude commercial terms: indemnification churn produces no event" do
    assert_empty events_for("Claude.ai/Commercial Terms.md")
  end

  test "DeepSeek: the legal-basis table leaving and returning produces no event" do
    dates = events_for("DeepSeek/Privacy Policy.md").map(&:first)
    assert_not_includes dates, "2025-07-04"
    assert_not_includes dates, "2025-07-18"
  end

  test "Cursor and Le Chat: unrelated paragraphs produce no event" do
    assert_not_includes events_for("Cursor/Terms of Service.md").map(&:first), "2025-06-19"
    assert_not_includes events_for("Le Chat/Terms of Service.md").map(&:first), "2025-10-08"
  end

  test "Claude.ai's opt-in to opt-out flip is found" do
    assert_includes events_for("Claude.ai/Privacy Policy.md"), [ "2025-08-29", "change" ]
  end

  test "every registry quote is verbatim in its tracked clause" do
    Document.find_each { |d| TrainedOn::Backfill.new(d, corpus: CORPUS).call if d.vendor.tiers.any? }
    Tier.includes(:vendor, document: :clause_versions).each do |tier|
      assert tier.quote_in_clause?, "#{tier.vendor.name} / #{tier.name}"
    end
  end
end
