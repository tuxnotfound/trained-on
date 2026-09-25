require "test_helper"

class TrainedOn::NormaliserTest < ActiveSupport::TestCase
  test "a rotating openaicom-did tracking ID is not a change (commit 88d6254)" do
    before = fixture_text("openaicom_did_before.md")
    after = fixture_text("openaicom_did_after.md")
    assert_not_equal before, after, "the raw files really differ"
    assert_equal TrainedOn::Normaliser.normalise(before), TrainedOn::Normaliser.normalise(after)
  end

  test "strips word joiners and zero-width characters" do
    assert_equal "Free plan", TrainedOn::Normaliser.normalise("Free⁠ plan​")
  end

  test "keeps link text and drops the target" do
    assert_equal "see this notice.", TrainedOn::Normaliser.normalise("see this [notice](https://x.com/a?utm=1).")
  end

  test "drops the screen-reader link label" do
    assert_equal "Read our instructions on how", TrainedOn::Normaliser.normalise("Read our instructions(opens in a new window) on how")
  end

  test "folds typographic quotes and whitespace" do
    assert_equal %(We "may" use it's), TrainedOn::Normaliser.normalise("We  “may” use it’s")
  end

  test "segments split table cells and bullets but keep prose paragraphs whole" do
    markdown = <<~MD
      | Purpose | Basis |
      | --- | --- |
      | To improve the Services * If training is enabled, we use content | Legitimate interests |

      We may use your Inputs and Outputs to train our models. Even if you opt out, we will use flagged content.
    MD
    segments = TrainedOn::Normaliser.segments(markdown)
    assert_includes segments, "If training is enabled, we use content"
    assert_includes segments, "Legitimate interests"
    assert_includes segments, "We may use your Inputs and Outputs to train our models. Even if you opt out, we will use flagged content."
    assert_not segments.any? { |s| s.match?(/\A[-| ]+\z/) }
  end
end
