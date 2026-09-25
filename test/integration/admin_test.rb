require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup do
    ENV["TRAINED_ON_ADMIN_USER"] = "reviewer"
    ENV["TRAINED_ON_ADMIN_PASSWORD"] = "correct horse"
    @auth = { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("reviewer", "correct horse") }
    @document = build_document(anchors: [ "train" ])
    version = @document.clause_versions.create!(text: "We may train on your data.", sha256: "b", effective_at: Time.utc(2025, 2, 1), ota_commit_sha: "b" * 40)
    @event = @document.clause_events.create!(to_version: version, occurred_on: Date.new(2025, 2, 1), classification: "position", one_line: "Acme trains.")
  end

  teardown do
    ENV.delete("TRAINED_ON_ADMIN_USER")
    ENV.delete("TRAINED_ON_ADMIN_PASSWORD")
  end

  test "requires credentials, and refuses everything when none are configured" do
    get admin_root_path
    assert_response :unauthorized
    get admin_root_path, headers: { "HTTP_AUTHORIZATION" => ActionController::HttpAuthentication::Basic.encode_credentials("reviewer", "wrong") }
    assert_response :unauthorized
    ENV.delete("TRAINED_ON_ADMIN_PASSWORD")
    get admin_root_path, headers: @auth
    assert_response :forbidden
  end

  test "publishing from the review screen makes the event public" do
    get admin_event_path(@event.id), headers: @auth
    assert_response :success
    patch admin_event_path(@event.id), params: { decision: "publish", clause_event: { one_line: "Acme now trains on your data." } }, headers: @auth
    assert_redirected_to admin_root_path
    assert_equal "published", @event.reload.state

    get change_path(@event)
    assert_response :success
    assert_match "Acme now trains on your data.", response.body
  end

  test "an unpublishable verdict is refused with the reason" do
    patch admin_event_path(@event.id), params: { decision: "publish", clause_event: { classification: "wording" } }, headers: @auth
    assert_response :unprocessable_content
    assert_equal "pending", @event.reload.state
  end

  test "preview shows drafts on the public pages" do
    post admin_preview_path, headers: @auth
    get root_path
    assert_match "Acme trains.", response.body
    assert_match "draft", response.body
  end

  test "anchor edits and rebuilds are available per document" do
    get admin_document_path(@document), headers: @auth
    assert_response :success
    post admin_document_anchors_path(@document), params: { anchor: { phrase: "opt out" } }, headers: @auth
    assert_equal [ "opt out", "train" ].sort, @document.anchors.pluck(:phrase).sort
  end
end
