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

  test "pages carry a link preview card" do
    @event.publish!
    get change_path(@event)
    assert_select "meta[property='og:title'][content=?]", "2025-02-01: Acme Privacy Policy · Trained On"
    assert_select "meta[property='og:description'][content=?]", "Acme started training on your data by default."
    assert_select "meta[property='og:image'][content$='/og.png']"
    assert_select "meta[name='twitter:card'][content='summary_large_image']"
  end

  test "a panel decision replayed from the decisions file still names its readers" do
    @event.update!(state: "published", decided_by: "panel", reviewed_at: Time.current, panel: nil)
    get change_path(@event)
    assert_match "Three independent AI readers agreed: Claude (Anthropic), GPT (OpenAI), Gemini (Google)", response.body
  end

  test "clause text shows without markdown markers, and terms take a plural verb" do
    @event.from_version.update!(text: "(c) _Licenses to Jasper._ Customer grants a licence.\n\n11\\. Usage Data.** We will not train on your data.")
    @event.to_version.update!(text: "Opt Out.** We may train on your data unless you opt out.")
    @event.publish!
    get change_path(@event)
    assert_match "changed what its privacy policy says", response.body
    assert_no_match "**", response.body
    assert_match "(c) Licenses to Jasper. Customer grants", response.body
    assert_match "11. Usage Data. We will not train", response.body
    assert_match "Opt Out. We may train", response.body

    @document.update!(name: "Terms of Service")
    get change_path(@event)
    assert_match "changed what its terms of service say<", response.body
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

  test "public pages are cacheable at the edge and set no cookie" do
    @event.publish!
    confirm_tier
    [ root_path, changes_path, change_path(@event), vendor_path(@vendor), methodology_path, data_path, press_path, llms_path, sitemap_path,
      changes_feed_path, vendor_feed_path(@vendor.slug), api_v1_vendors_path, api_v1_changes_path, registry_csv_path ].each do |path|
      get path
      assert_response :success, path
      assert_match(/public/, response.headers["cache-control"], path)
      assert_match(/s-maxage=600/, response.headers["cache-control"], path)
      assert_match(/stale-if-error=86400/, response.headers["cache-control"], path)
      assert_nil response.headers["set-cookie"], "#{path} set a cookie"
    end
  end

  test "a missing page, the admin and the preview are never cacheable" do
    get vendor_path(@vendor)
    assert_response :not_found
    assert_no_match(/public/, response.headers["cache-control"].to_s)

    ENV["TRAINED_ON_ADMIN_USER"] = "reviewer"
    ENV["TRAINED_ON_ADMIN_PASSWORD"] = "correct horse"
    post admin_login_path, params: { username: "reviewer", password: "correct horse" }
    get admin_root_path
    assert_response :success
    assert_match(/private/, response.headers["cache-control"])

    post admin_preview_path
    get root_path
    assert_response :success
    assert_match "Drafts are visible", response.body
    assert_match(/private/, response.headers["cache-control"])
    assert_no_match(/public/, response.headers["cache-control"])
  ensure
    ENV.delete("TRAINED_ON_ADMIN_USER")
    ENV.delete("TRAINED_ON_ADMIN_PASSWORD")
  end

  test "the footer has a way to reach me" do
    get root_path
    assert_select "footer a[href^='mailto:']", /Email me/
  end

  test "titles ask the question people search, and every page names its canonical address" do
    @event.publish!
    confirm_tier
    get root_path
    assert_select "title", "Is this AI training on my prompts? · Trained On"
    get vendor_path(@vendor)
    assert_select "title", "Does Acme train on my prompts? · Trained On"
    get changes_path(type: "position")
    assert_select "link[rel='canonical'][href=?]", "http://www.example.com/changes"
  end

  test "the sitemap lists public pages only" do
    get sitemap_path
    assert_response :success
    assert_equal "application/xml", response.media_type
    assert_match "<loc>http://www.example.com/methodology</loc>", response.body
    assert_match "<loc>http://www.example.com/press</loc>", response.body
    assert_no_match change_path(@event), response.body
    assert_no_match vendor_path(@vendor), response.body

    @event.publish!
    get sitemap_path
    assert_match "<loc>http://www.example.com#{change_path(@event)}</loc>", response.body
    assert_match "<loc>http://www.example.com#{vendor_path(@vendor)}</loc>", response.body
  end

  test "the data page describes the dataset for search engines" do
    get data_path
    data = JSON.parse(css_select("script[type='application/ld+json']").first.text)
    assert_equal "Dataset", data["@type"]
    assert_equal "https://opendatacommons.org/licenses/by/1-0/", data["license"]
    assert_equal [ registry_csv_url, changes_csv_url, api_v1_vendors_url, api_v1_changes_url ], data["distribution"].pluck("contentUrl")
  end

  test "a change page carries a citation with its permanent address" do
    @event.publish!
    get change_path(@event)
    assert_select "a[href='#cite']"
    assert_select "#cite pre", text: %(Trained On, "Acme changed what its privacy policy says", first recorded 1 Feb 2025, ) +
                                     %(http://www.example.com/changes/2025-02-01-acme-privacy-policy. Derived from Open Terms Archive, ODC-By 1.0.)
    assert_select "#cite button[hidden]", "Copy"
  end

  test "the press page has the numbers, citations, the changes of position and a contact" do
    get press_path
    assert_response :success
    assert_no_match "Acme started training", response.body

    @event.publish!
    confirm_tier
    get press_path
    assert_select ".stat b", text: "1", minimum: 2
    assert_select ".citation pre", /http:\/\/www.example.com\/data/
    assert_select ".changes a[href=?]", change_path(@event), text: "Acme started training on your data by default."
    assert_select "main a[href^='mailto:']"
    get root_path
    assert_select "footer a[href=?]", press_path
  end

  test "llms.txt carries the reviewed registry and the changes of position, unescaped" do
    get llms_path
    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_no_match "We may train on your data", response.body

    @event.publish!
    confirm_tier
    get llms_path
    assert_match(/\A# Trained On\n/, response.body)
    assert_match '- [Acme, Free](http://www.example.com/vendors/acme): Yes, by default. You can opt out. In their words: "We may train on your data unless you opt out." (Privacy Policy;', response.body
    assert_match "- [2025-02-01, Acme privacy policy](http://www.example.com/changes/2025-02-01-acme-privacy-policy): Acme started training on your data by default.", response.body
  end

  test "methodology and data pages render" do
    get methodology_path
    assert_response :success
    assert_match "openaicom-did", response.body
    get data_path
    assert_response :success
  end
end
