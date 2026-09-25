require "test_helper"

class TrainedOn::LocatorTest < ActiveSupport::TestCase
  CHATGPT_ANCHORS = YAML.load_file(Rails.root.join("db/seeds/anchors.yml"))
    .find { |v| v["slug"] == "chatgpt" }["documents"].find { |d| d["ota_path"] == "ChatGPT/Privacy Policy.md" }["anchors"]

  test "the Temporary Chat sentence never left ChatGPT's privacy policy (commit 7346836)" do
    locator = TrainedOn::Locator.new(CHATGPT_ANCHORS)
    before = locator.call(fixture_text("chatgpt_privacy_2026-09-16.md"))
    after = locator.call(fixture_text("chatgpt_privacy_2026-09-17.md"))
    assert_match(/Temporary Chat/, after.text)
    assert_equal before.sha256, after.sha256, "anchored clause must not change on this commit"
  end

  test "matches anchors case-insensitively after normalisation" do
    result = TrainedOn::Locator.new([ "use your inputs and outputs to train" ]).call(<<~MD)
      # Privacy

      We may use your Inputs and Outputs to train our models, unless you opt out.

      We process payments.
    MD
    assert_equal [ "We may use your Inputs and Outputs to train our models, unless you opt out." ], result.paragraphs
    assert_not result.anchor_lost
  end

  test "reports anchor_lost instead of an empty clause" do
    result = TrainedOn::Locator.new([ "use your inputs and outputs to train" ]).call("Nothing about that here.")
    assert result.anchor_lost
    assert_empty result.paragraphs
  end

  test "the net proposes training segments that no anchor covers" do
    markdown = "We may use your content to train our models.\n\nWe use your conversations to train our AI models in some markets."
    result = TrainedOn::Locator.new([ "use your content to train" ]).call(markdown, with_net: true)
    assert_equal [ "We use your conversations to train our AI models in some markets." ], result.unanchored_hits
  end
end
