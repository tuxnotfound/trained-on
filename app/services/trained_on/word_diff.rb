require "diff/lcs"

module TrainedOn
  # Word-level diff between two clause texts. Line diffs are useless on legal
  # prose that reflows; words are the unit a reader compares.
  #
  # A raw LCS diff of a rewritten sentence is unreadable: it keeps every shared
  # "the", "to" and "our" and interleaves the rest word by word. So changes
  # separated by a short run of shared words are merged into one removal and
  # one addition, which reads as "this phrase became that phrase".
  class WordDiff
    Chunk = Data.define(:action, :text) # action: "=", "-", "+"

    TOKEN = /\n\n|[ \t]+|[^\s]+/
    GLUE_WORDS = 3 # shared runs this short between two changes are absorbed
    REWRITE_BELOW = 0.25 # below this share of shared words, show old then new

    def initialize(old_text, new_text)
      @old = old_text.to_s.scan(TOKEN)
      @new = new_text.to_s.scan(TOKEN)
    end

    def chunks
      @chunks ||= rewrite? ? whole_rewrite : render(glue(regions))
    end

    # A clause replaced almost wholesale reads better as "this, then that" than
    # as two texts threaded through a handful of shared words.
    def rewrite?
      old_words = @old.count { |t| t.match?(/\S/) }
      new_words = @new.count { |t| t.match?(/\S/) }
      return false if old_words.zero? || new_words.zero?
      shared = regions.select { |r| r.first == :same }.sum { |r| r[1].count { |t| t.match?(/\S/) } }
      # Both sides mostly unshared. A pure addition (old text intact) or a pure
      # deletion (new text is what is left of the old) still reads best inline.
      shared.to_f / old_words < REWRITE_BELOW && shared.to_f / new_words < REWRITE_BELOW
    end

    def changed? = chunks.any? { |c| c.action != "=" }
    def added_words = chunks.select { |c| c.action == "+" }.sum { |c| c.text.split.size }
    def removed_words = chunks.select { |c| c.action == "-" }.sum { |c| c.text.split.size }

    def to_s
      chunks.map do |c|
        case c.action
        when "=" then c.text
        when "-" then "[-#{c.text}-]"
        else "{+#{c.text}+}"
        end
      end.join
    end

    private

    def whole_rewrite
      [ Chunk.new(action: "-", text: @old.join), Chunk.new(action: "=", text: "\n\n"), Chunk.new(action: "+", text: @new.join) ]
    end

    # Alternating regions: [:same, tokens] and [:change, removed, added].
    def regions
      @regions ||= compute_regions
    end

    def compute_regions
      out = []
      Diff::LCS.traverse_sequences(@old, @new, Class.new {
        define_method(:initialize) { |o| @o = o }
        define_method(:match) { |e| @o.last&.first == :same ? @o.last[1] << e.old_element : @o << [ :same, [ e.old_element ] ] }
        define_method(:discard_a) { |e| change(@o)[1] << e.old_element }
        define_method(:discard_b) { |e| change(@o)[2] << e.new_element }
        define_method(:change) { |o| o.last&.first == :change ? o.last : (o << [ :change, [], [] ]).last }
      }.new(out))
      out
    end

    def glue(regions)
      out = []
      regions.each_with_index do |region, i|
        prev_change = out.last&.first == :change
        next_change = regions[i + 1]&.first == :change
        short = region.first == :same && region[1].count { |t| t.match?(/\S/) } <= GLUE_WORDS && region[1].none? { |t| t == "\n\n" }
        if short && prev_change && next_change
          out.last[1].concat(region[1])
          out.last[2].concat(region[1])
        elsif region.first == :change && prev_change
          out.last[1].concat(region[1])
          out.last[2].concat(region[2])
        else
          out << region.map { |x| x.is_a?(Array) ? x.dup : x }
        end
      end
      out
    end

    def render(regions)
      regions.flat_map do |region|
        if region.first == :same
          [ Chunk.new(action: "=", text: region[1].join) ]
        else
          removed, added = region[1].join, region[2].join
          # keep the whitespace outside the markers
          [ (Chunk.new(action: "-", text: removed) unless removed.strip.empty?),
           (Chunk.new(action: "+", text: added) unless added.strip.empty?),
           (Chunk.new(action: "=", text: " ") if removed.strip.empty? && added.strip.empty? && !(removed + added).empty?) ].compact
        end
      end
    end
  end
end
