require "test_helper"

class Changes::AnnounceServiceTest < ActiveSupport::TestCase
  setup do
    document = build_document
    version = document.clause_versions.create!(text: "We may train our models.", sha256: "a", effective_at: Time.utc(2025, 1, 1), last_seen_at: Time.utc(2025, 1, 1), ota_commit_sha: "a" * 40)
    @event = document.clause_events.create!(to_version: version, occurred_on: Date.new(2025, 1, 1), classification: "position", one_line: "Acme now trains on your data.")
    @indexnow = stub_request(:post, "https://api.indexnow.org/indexnow").to_return(status: 200)
  end

  test "announces a change published in the window, its vendor and the pages that list changes" do
    @event.publish!
    service = Changes::AnnounceService.new(since: 1.hour.ago)

    assert service.call
    assert_equal [ "https://trainedon.me/changes/2025-01-01-acme-privacy-policy", "https://trainedon.me/vendors/acme",
                   "https://trainedon.me/changes", "https://trainedon.me/", "https://trainedon.me/press" ], service.urls
    assert_requested(:post, "https://api.indexnow.org/indexnow") { |request| JSON.parse(request.body)["urlList"] == service.urls }
  end

  test "stays quiet when nothing was published in the window" do
    @event.update!(state: "published", reviewed_at: 2.days.ago)
    service = Changes::AnnounceService.new(since: 1.hour.ago)

    assert service.call
    assert_empty service.urls
    assert_not_requested @indexnow
  end

  test "pending and rejected changes are never announced" do
    @event.reject!
    assert Changes::AnnounceService.new(since: 1.hour.ago).call
    assert_not_requested @indexnow
  end

  test "refuses without a window" do
    service = Changes::AnnounceService.new
    assert_not service.call
    assert service.errors.of_kind?(:since, :blank)
  end
end
