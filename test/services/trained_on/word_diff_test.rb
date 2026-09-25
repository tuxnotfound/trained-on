require "test_helper"

class TrainedOn::WordDiffTest < ActiveSupport::TestCase
  test "identical texts have no change" do
    diff = TrainedOn::WordDiff.new("We do not train.", "We do not train.")
    assert_not diff.changed?
  end

  test "a one-word edit is shown as that word" do
    diff = TrainedOn::WordDiff.new("By default, business data from ChatGPT Team, Enterprise", "By default, business data from ChatGPT Business, Enterprise")
    assert_equal "By default, business data from ChatGPT [-Team,-]{+Business,+} Enterprise", diff.to_s
  end

  test "a rewritten phrase reads as one removal and one addition, not interleaved words" do
    diff = TrainedOn::WordDiff.new(
      "We will not use your Inputs or Outputs to train our models, unless you opt in.",
      "We may use your Inputs and Outputs to train our models, unless you opt out."
    )
    assert_equal "We [-will not use your Inputs or-]{+may use your Inputs and+} Outputs to train our models, unless you opt [-in.-]{+out.+}", diff.to_s
  end

  test "a wholesale rewrite shows the old text, then the new" do
    diff = TrainedOn::WordDiff.new(
      "Use of Autocomplete User Content. We will never use it to improve generative models.",
      "Cognition may use Customer Data for model training purposes."
    )
    assert diff.rewrite?
    assert_equal "[-Use of Autocomplete User Content. We will never use it to improve generative models.-]\n\n{+Cognition may use Customer Data for model training purposes.+}", diff.to_s
  end

  test "a long addition to intact text stays inline" do
    diff = TrainedOn::WordDiff.new("We may train on content.", "We may train on content. " + "You can opt out in settings at any time. " * 5)
    assert_not diff.rewrite?
    assert diff.to_s.start_with?("We may train on content.")
  end

  test "counts added and removed words" do
    diff = TrainedOn::WordDiff.new("a b c", "a b c d e")
    assert_equal 2, diff.added_words
    assert_equal 0, diff.removed_words
  end

  test "a clause that appears from nothing is all addition" do
    diff = TrainedOn::WordDiff.new(nil, "We train on conversations.")
    assert_equal "{+We train on conversations.+}", diff.to_s
  end
end
