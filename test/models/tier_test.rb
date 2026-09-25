require "test_helper"

class TierTest < ActiveSupport::TestCase
  setup do
    @document = build_document
    @vendor = @document.vendor
    create = ->(text, from, to) { @document.clause_versions.create!(text:, sha256: Digest::SHA256.hexdigest(text), effective_at: from, last_seen_at: to, ota_commit_sha: SecureRandom.hex(4)) }
    create.("We train on your data. Extra.", Time.utc(2025, 1, 1), Time.utc(2025, 1, 5))
    create.("We train on your data. Other extra.", Time.utc(2025, 3, 1), Time.utc(2025, 3, 5))
  end

  test "the quote must be verbatim in the current clause" do
    tier = @vendor.tiers.new(name: "Free", answer: "trains_opt_out", document: @document, quote: "We never train.")
    assert_not tier.valid?
    tier.quote = "We train on your data."
    assert tier.valid?
  end

  test "on record since counts back through states that contain the quote" do
    tier = @vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "We train on your data.")
    assert_equal Date.new(2025, 1, 1), tier.effective_on
    assert tier.since_first_capture?
  end

  test "a capture gap before the quote appeared is reported" do
    tier = @vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "Other extra.")
    assert_equal Date.new(2025, 3, 1), tier.effective_on
    assert_equal Date.new(2025, 1, 5), tier.previous_capture_on
  end

  test "verification is mechanical: the date of the latest capture holding the quote" do
    tier = @vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "We train on your data.")
    assert tier.stale?
    Tier.refresh_verification!
    assert_equal Date.new(2025, 3, 5), tier.reload.verified_on
    assert tier.stale?, "a capture from 2025 is older than 30 days"

    gone = @vendor.tiers.create!(name: "Pro", answer: "trains_opt_out", document: @document, quote: "Extra.")
    gone.update_columns(quote: "Not in any capture.")
    Tier.refresh_verification!
    assert_nil gone.reload.verified_on
  end

  test "a row is public only when the quote is current and the answer is confirmed" do
    tier = @vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "We train on your data.")
    Tier.refresh_verification!
    assert_not Tier.verified.exists?(tier.id)
    tier.update_columns(confirmed_by: "human", confirmed_at: Time.current)
    assert Tier.verified.exists?(tier.id)
  end
end
