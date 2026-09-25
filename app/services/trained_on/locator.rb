module TrainedOn
  # Finds a document's training clause using its hand-chosen anchors.
  #
  # Result#paragraphs is the clause: every segment (paragraph, bullet or table cell) containing an anchor phrase,
  # in document order. When the document has anchors but none matched, the
  # result is anchor_lost, which the backfill records as an event for review:
  # a clause that moved is never reported as "no change".
  class Locator
    Result = Data.define(:paragraphs, :anchor_lost, :unanchored_hits) do
      def text = paragraphs.join("\n\n")
      def sha256 = Digest::SHA256.hexdigest(text)
    end

    def initialize(phrases)
      @phrases = phrases.map { |p| Normaliser.fold(Normaliser.normalise(p)) }.reject(&:empty?).uniq
    end

    def call(markdown, with_net: false)
      paras = Normaliser.segments(markdown)
      hits = paras.select { |p| anchored?(p) }.uniq
      unanchored = with_net ? paras.reject { |p| anchored?(p) }.select { |p| Net.hit?(p) }.uniq : []
      Result.new(paragraphs: hits, anchor_lost: @phrases.any? && hits.empty?, unanchored_hits: unanchored)
    end

    private

    def anchored?(paragraph)
      folded = Normaliser.fold(paragraph)
      @phrases.any? { |phrase| folded.include?(phrase) }
    end
  end
end
