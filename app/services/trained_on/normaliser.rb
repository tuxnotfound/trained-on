module TrainedOn
  # Turns one OTA markdown snapshot into comparable paragraphs. Everything here
  # removes a source of phantom change seen in the corpus: rotating tracking IDs
  # inside link targets (the openaicom-did case), word joiners, smart quotes,
  # reflowed whitespace.
  module Normaliser
    ZERO_WIDTH = /[​-‍⁠﻿­]/
    MD_LINK = /\[([^\]]*)\]\([^)]*\)/
    LEADING_MARKUP = /\A(?:[#>*\-|]+\s*)+/
    # Screen-reader label OpenAI appends to link text and removes again at random.
    LINK_LABELS = /\s*\(opens in a new (?:window|tab)\)/i

    module_function

    def normalise(markdown)
      s = markdown.dup.force_encoding("UTF-8").scrub("")
      s = s.unicode_normalize(:nfc)
      s = s.gsub(ZERO_WIDTH, "")
      s = s.gsub(MD_LINK) { Regexp.last_match(1) } # compare link text, never the target
      s = s.gsub(LINK_LABELS, "")
      s = s.gsub(/<[^>]+>/, " ")
      s = s.gsub(/[“”]/, '"').gsub(/[‘’]/, "'")
      s = s.gsub(/\r\n?/, "\n")
      s = s.gsub(/[ \t ]+/, " ")
      s.strip
    end

    # Paragraphs of a normalised document, each collapsed to one line with its
    # leading markdown (headings, bullets, table pipes) removed.
    def paragraphs(markdown)
      normalise(markdown)
        .split(/\n\s*\n/)
        .map { |b| b.gsub(/\s*\n\s*/, " ").strip.sub(LEADING_MARKUP, "").strip }
        .reject(&:empty?)
    end

    # The unit the locator anchors on. A paragraph is split at bullet markers and
    # table cells, because OTA flattens whole purpose tables and bullet lists
    # into one paragraph: anchoring the paragraph would make an unrelated edit
    # anywhere in the table look like a change to the training clause.
    def segments(markdown)
      paragraphs(markdown).flat_map do |para|
        para.split(/\s\|\s|\s\|\z|\A\|\s|\s[*•]\s/)
            .map { |seg| seg.strip.sub(LEADING_MARKUP, "").strip }
            .reject { |seg| seg.empty? || seg.match?(/\A[-:| ]+\z/) }
      end
    end

    # Key used to compare an anchor phrase against a paragraph.
    def fold(text) = text.downcase.gsub(/\s+/, " ").strip
  end
end
