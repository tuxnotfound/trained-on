require "test_helper"

class PublicSiteTest < ActionDispatch::IntegrationTest
  setup do
    @document = build_document(anchors: [ "train" ])
    @vendor = @document.vendor
    old = @document.clause_versions.create!(text: "We will not train on your data.", sha256: "a", effective_at: Time.utc(2025, 1, 1), last_seen_at: Time.utc(2025, 1, 2), ota_commit_sha: "a" * 40)
    new = @document.clause_versions.create!(text: "We may train on your data unless you opt out.", sha256: "b", effective_at: Time.utc(2025, 2, 1), last_seen_at: Time.utc(2025, 2, 1), ota_commit_sha: "b" * 40)
    @event = @document.clause_events.create!(from_version: old, to_version: new, occurred_on: Date.new(2025, 2, 1),
                                             classification: "position", direction: "now_trains", one_line: "Acme started training on your data by default.")
    @tier = @vendor.tiers.create!(name: "Free", answer: "trains_opt_out", document: @document, quote: "We may train on your data unless you opt out.")
    Tier.refresh_verification!
  end

  def confirm_tier = @tier.update_columns(confirmed_by: "human", confirmed_at: Time.current)

  test "pending events and unverified rows are not public" do
    get root_path
    assert_response :success
    assert_no_match "Acme started training", response.body
    assert_no_match "We may train on your data", response.body
    get change_path(@event)
    assert_response :not_found
    get vendor_path(@vendor)
    assert_response :not_found
  end

  test "published events and confirmed rows are public, with the diff and the window" do
    @event.publish!
    confirm_tier

    get root_path
    assert_match "Acme started training", response.body
    assert_match "We may train on your data unless you opt out.", response.body

    get change_path(@event)
    assert_response :success
    assert_select "del", /will not/
    assert_select "ins", /may/
    assert_match "between", response.body
    assert_match "A person, after reading both versions", response.body

    get vendor_path(@vendor)
    assert_response :success
  end

  test "a panel decision says so on the change page" do
    @event.update!(state: "published", decided_by: "panel", reviewed_at: Time.current,
                   panel: { "decision" => "published", "readers" => [ { "provider" => "Claude (Anthropic)" }, { "provider" => "GPT (OpenAI)" }, { "provider" => "Gemini (Google)" } ] })
    get change_path(@event)
    assert_match "Three independent AI readers agreed: Claude (Anthropic), GPT (OpenAI), Gemini (Google)", response.body
  end

  test "data files and feeds only carry reviewed material" do
    get api_v1_vendors_path
    assert_equal [], response.parsed_body["rows"]
    assert_equal "ODC-By-1.0", response.parsed_body["license"]

    @event.publish!
    confirm_tier

    get api_v1_vendors_path
    assert_equal "Acme", response.parsed_body["rows"].first["vendor"]
    get registry_csv_path
    assert_match "We may train on your data unless you opt out.", response.body
    get changes_csv_path
    assert_match "Acme started training", response.body
    get changes_feed_path
    assert_response :success
    assert_match "Acme started training", response.body
    get vendor_feed_path(@vendor.slug)
    assert_response :success
  end

  test "methodology and data pages render" do
    get methodology_path
    assert_response :success
    assert_match "openaicom-did", response.body
    get data_path
    assert_response :success
  end
end
