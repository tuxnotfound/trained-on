#!/usr/bin/env ruby
# frozen_string_literal: true

# Trained On: the go/no-go test.
#
# Walks every recorded version of every document for the vendors procurement
# actually asks about, normalises the markdown, locates the paragraphs that talk
# about training models on user data, hashes that block, and collapses runs of
# identical hashes. What is left is the denoised clause history.
#
# Gate (from control-tower/projects/trained-on/STATUS.md):
#   BUILD only if  distinct clause states >= 20
#              AND transitions with real word changes >= 6
#              AND the locator hits >= 10 of 13 vendors
#   DROP if       states < 10, OR word-change transitions < 3, OR misses > 3 vendors
#
# Usage:  ruby scripts/denoise.rb [corpus_dir] [report_path]
# Cost:   EUR 0, no network after the clone. Pure Ruby stdlib.

require "digest"
require "open3"
require "time"

CORPUS = ARGV[0] || File.expand_path("../corpus/genai-contrib-versions", __dir__)
REPORT = ARGV[1] || File.expand_path("../results/denoise-report.md", __dir__)

VENDORS = [
  "ChatGPT", "Claude.ai", "Microsoft Copilot", "GitHub Copilot",
  "Google Generative AI Services", "Perplexity", "Grok", "Cursor",
  "Codeium", "DeepSeek", "Midjourney", "Jasper", "Le Chat"
].freeze

GATE = { states: 20, word_transitions: 6, vendors_hit: 10 }.freeze
DROP = { states: 10, word_transitions: 3, vendors_missed: 3 }.freeze

# --- the net ---------------------------------------------------------------
# A paragraph is "the clause" when it contains the construction itself: the
# vendor using (or not using) material to train / improve a model, an opt-in or
# opt-out tied to training, or "model training" as a named purpose. Plus a
# reference to the user's material. The exclusions strip the false positives
# seen in the corpus (security training, training materials, "training data
# may be biased", and restrictions on the USER training a rival model).
#
# First cut was looser (train + model + your, anywhere in the paragraph) and it
# pulled in ads, browser and indemnification paragraphs of the huge OpenAI
# privacy policies, so the block set flickered on edits that had nothing to do
# with training. Tightened 2026-09-24 after reading the first report.
CLAUSE = /
    \b(?:do|does|did|will|shall|may|might|can|could|would|won't|don't|doesn't|never|not)\s+(?:not\s+)?(?:be\s+)?(?:use[ds]?|using|train(?:s|ed|ing)?|utili[sz]e[ds]?)\b[^.;]{0,160}?\b(?:train|training|fine[- ]?tun|improv(?:e|ing)\s+(?:our|its|the|their)\s+(?:ai\s+)?(?:models?|technolog))
  | \b(?:use[ds]?|using|utili[sz]ed?)\s+(?:it\s+|them\s+|this\s+|that\s+)?(?:for|to)\s+(?:model\s+)?(?:train|fine[- ]?tun)
  | \b(?:used?|using)\s+(?:for|to)\s+(?:help\s+)?(?:develop|improve|enhance)[^.;]{0,60}?\btrain
  | \btrain(?:s|ed|ing)?\s+(?:and\s+improv(?:e|ing)\s+)?(?:our|its|their|the|any|new|more)?\s*(?:advanced\s+|ai\s+|machine[- ]learning\s+|artificial\s+intelligence\s+|large\s+language\s+|generative\s+)*(?:models?|ai\b|llms?|technolog)
  | \bopt[- ]?(?:in|out|ed)\b[^.;]{0,120}?\btrain
  | \btrain[^.;]{0,120}?\bopt[- ]?(?:in|out)\b
  | \bmodel\s+training\b
  | \btraining\s+(?:of\s+)?(?:our|its|their)\s+(?:ai\s+|large\s+language\s+)?models?
  | \btraining\s+purposes?\b
/ix
SUBJECT = /\b(?:your|you|customer|users?|inputs?|outputs?|prompts?|content|conversations?|materials?|submissions?|business\s+data|personal\s+data|customer\s+data|property|feedback|interactions?|publicly\s+available|public)\b/i
EXCLUDE = [
  /\bsecurity\s+(?:awareness\s+)?training\b/i,
  /\bsecure\s+code\s+training\b/i,
  /\btraining\s+(?:materials?|curriculum|program(?:me)?s?)\b/i,
  /\btraining,\s+consulting\b/i,
  /\bprofessional\s+services\b/i,
  /\btraining\s+data\s+(?:may|could|might)\b/i,
  /\bcompet(?:e|ing|itive)\b/i,           # "do not use the Service to train a competing model"
  /\bmodel\s+(?:scraping|distillation|extraction)\b/i,
  /\brobots\.txt\b/i,
  /\bcrawl(?:ing|ers?)?\b/i
].freeze

def clause?(block)
  return false unless block.match?(CLAUSE) && block.match?(SUBJECT)
  EXCLUDE.none? { |re| block.match?(re) }
end

# --- normalisation -----------------------------------------------------------
ZERO_WIDTH = /[​‌‍⁠﻿­]/

def normalise(md)
  s = md.dup.force_encoding("UTF-8")
  s = s.scrub("")
  s = s.unicode_normalize(:nfc)
  s = s.gsub(ZERO_WIDTH, "")
  s = s.gsub(/\[([^\]]*)\]\([^)]*\)/) { $1 }          # [text](url) -> text; kills rotating link params
  s = s.gsub(/<[^>]+>/, " ")                          # inline html
  s = s.gsub(/[ \t ]+/, " ")
  s = s.gsub(/[“”]/, '"').gsub(/[‘’]/, "'")
  s = s.gsub(/\r\n?/, "\n")
  s.strip
end

def blocks(normalised)
  normalised.split(/\n\s*\n/).map { |b| b.gsub(/\s*\n\s*/, " ").strip }.reject(&:empty?)
end

def clause_state(md)
  hits = blocks(normalise(md)).select { |b| clause?(b) }
  hits.map { |b| b.sub(/\A(?:[#>*\-|]+\s*)+/, "").strip }.uniq
end

def words(text)
  text.downcase.gsub(/[^\p{L}\p{N}\s]/, " ").split
end

# --- git ---------------------------------------------------------------------
def git(*args)
  out, err, st = Open3.capture3("git", "-C", CORPUS, *args)
  raise "git #{args.join(' ')} failed: #{err}" unless st.success?
  out
end

# Every version of a document, oldest first. No --follow: OTA never renames, and
# rename detection happily jumps between near-identical documents of sibling
# services (ChatGPT's "Platform to Business Notice" followed into DALL·E's).
def versions(path)
  git("-c", "core.quotepath=false", "log", "--format=%H%x09%cI", "--", path)
    .each_line.map { |l| sha, date = l.chomp.split("\t"); { sha: sha, date: Time.iso8601(date), path: path } }
    .reverse
end

def show(sha, path)
  git("show", "#{sha}:#{path}")
end

# --- run ---------------------------------------------------------------------
report = []
summary = []
totals = { commits: 0, states: 0, transitions: 0, word_transitions: 0, reflows: 0 }
vendors_hit = []

report << "# Trained On: denoised clause history over the OTA `genai-contrib` corpus"
report << ""
report << "Generated #{Time.now.utc.iso8601} by `scripts/denoise.rb`. Corpus HEAD `#{git('rev-parse', '--short', 'HEAD').strip}`."
report << "Source data: Open Terms Archive contributors, ODC-By 1.0."
report << ""

VENDORS.each do |vendor|
  docs = Dir.glob(File.join(CORPUS, vendor, "*.md")).map { |f| File.basename(f) }.sort
  vendor_states = 0
  vendor_word_transitions = 0
  vendor_commits = 0
  vendor_hit = false
  vendor_lines = []

  docs.each do |doc|
    path = "#{vendor}/#{doc}"
    vs = versions(path)
    vendor_commits += vs.size
    totals[:commits] += vs.size

    runs = [] # [{hash, state(Array<String>), first_seen, last_seen, sha}]
    vs.each do |v|
      state = clause_state(show(v[:sha], v[:path]))
      h = Digest::SHA256.hexdigest(state.join("\n\n"))
      if runs.last && runs.last[:hash] == h
        runs.last[:last_seen] = v[:date]
        runs.last[:count] += 1
      else
        runs << { hash: h, state: state, first_seen: v[:date], last_seen: v[:date], sha: v[:sha], count: 1 }
      end
    end

    located = runs.any? { |r| !r[:state].empty? }
    next unless located
    vendor_hit = true

    # A "state" is a distinct located clause set; the empty set counts only as a gap, not a state.
    nonempty = runs.reject { |r| r[:state].empty? }
    vendor_states += nonempty.size
    totals[:states] += nonempty.size

    vendor_lines << "### #{doc}"
    vendor_lines << ""
    vendor_lines << "#{vs.size} recorded versions, #{runs.size} runs after collapsing, #{nonempty.size} non-empty clause states."
    vendor_lines << ""

    runs.each_cons(2) do |a, b|
      totals[:transitions] += 1
      wa = words(a[:state].join(" "))
      wb = words(b[:state].join(" "))
      removed = (wa - wb).uniq
      added   = (wb - wa).uniq
      # bag difference: words whose COUNT changed, not just presence
      count = ->(arr) { arr.each_with_object(Hash.new(0)) { |w, h| h[w] += 1 } }
      ca, cb = count.(wa), count.(wb)
      changed = (ca.keys | cb.keys).select { |w| ca[w] != cb[w] }
      kind =
        if a[:state].empty? then "clause appears"
        elsif b[:state].empty? then "clause disappears (locator lost it or vendor removed it)"
        elsif changed.empty? then "reflow only"
        else "WORDS CHANGED"
        end
      if kind == "WORDS CHANGED" || kind == "clause appears" || kind.start_with?("clause disappears")
        vendor_word_transitions += 1 if kind == "WORDS CHANGED"
        totals[:word_transitions] += 1 if kind == "WORDS CHANGED"
      else
        totals[:reflows] += 1
      end

      label = kind == "WORDS CHANGED" ? "WORDS CHANGED (#{changed.size} words differ)" : kind
      vendor_lines << "#### #{b[:first_seen].strftime('%Y-%m-%d')}: #{label}"
      vendor_lines << ""
      vendor_lines << "Previous state held from #{a[:first_seen].strftime('%Y-%m-%d')} across #{a[:count]} version(s). New state introduced in commit `#{b[:sha][0, 7]}`."
      vendor_lines << ""
      gone = a[:state] - b[:state]
      came = b[:state] - a[:state]
      unless gone.empty?
        vendor_lines << "Paragraphs removed or rewritten (old text):"
        vendor_lines << ""
        gone.each { |p| vendor_lines << "> #{p}" << ">" }
        vendor_lines.pop
        vendor_lines << ""
      end
      unless came.empty?
        vendor_lines << "Paragraphs added or rewritten (new text):"
        vendor_lines << ""
        came.each { |p| vendor_lines << "> #{p}" << ">" }
        vendor_lines.pop
        vendor_lines << ""
      end
      if kind == "WORDS CHANGED"
        vendor_lines << "- removed words: #{removed.first(40).join(', ')}#{removed.size > 40 ? ' ...' : ''}"
        vendor_lines << "- added words: #{added.first(40).join(', ')}#{added.size > 40 ? ' ...' : ''}"
        vendor_lines << ""
      end
    end

    if runs.size == 1
      vendor_lines << "Single state, unchanged since #{runs.first[:first_seen].strftime('%Y-%m-%d')}:"
      vendor_lines << ""
      runs.first[:state].each { |p| vendor_lines << "> #{p}" << ">" }
      vendor_lines.pop
      vendor_lines << ""
    end
  end

  vendors_hit << vendor if vendor_hit
  summary << [vendor, vendor_commits, vendor_states, vendor_word_transitions, vendor_hit ? "yes" : "NO"]

  report << "## #{vendor}"
  report << ""
  if vendor_hit
    report.concat(vendor_lines)
  else
    report << "Locator found no training clause in any version of any document. Documents: #{docs.join(', ')}."
    report << ""
  end
end

# --- verdict -----------------------------------------------------------------
missed = VENDORS - vendors_hit
pass = totals[:states] >= GATE[:states] && totals[:word_transitions] >= GATE[:word_transitions] && vendors_hit.size >= GATE[:vendors_hit]
fail = totals[:states] < DROP[:states] || totals[:word_transitions] < DROP[:word_transitions] || missed.size > DROP[:vendors_missed]
verdict = pass ? "PASS (mechanical)" : fail ? "FAIL (mechanical)" : "GREY ZONE: between drop and build thresholds"

table = []
table << "| Vendor | Versions walked | Distinct clause states | Word-change transitions | Located |"
table << "|---|---:|---:|---:|---|"
summary.each { |r| table << "| #{r.join(' | ')} |" }
table << "| **Total** | **#{totals[:commits]}** | **#{totals[:states]}** | **#{totals[:word_transitions]}** | **#{vendors_hit.size} of #{VENDORS.size}** |"

head = []
head << "## Verdict: #{verdict}"
head << ""
head << "| Gate | Build needs | Drop below | Measured |"
head << "|---|---:|---:|---:|"
head << "| Distinct clause states | #{GATE[:states]} | #{DROP[:states]} | #{totals[:states]} |"
head << "| Transitions with word changes | #{GATE[:word_transitions]} | #{DROP[:word_transitions]} | #{totals[:word_transitions]} |"
head << "| Vendors located | #{GATE[:vendors_hit]} of 13 | miss > #{DROP[:vendors_missed]} | #{vendors_hit.size} of 13#{missed.empty? ? '' : " (missed: #{missed.join(', ')})"} |"
head << ""
head << "Versions walked: #{totals[:commits]}. Transitions between runs: #{totals[:transitions]}, of which #{totals[:reflows]} were pure reflow. Denoising ratio: #{totals[:commits]} recorded versions collapse to #{totals[:states]} clause states."
head << ""
head << "\"Word-change\" is mechanical: the bag of words differs. Whether a change is meaning-bearing is a human call; read each WORDS CHANGED entry below."
head << ""
head.concat(table)
head << ""

File.write(REPORT, (report[0..4] + head + report[5..]).join("\n"))

puts head.join("\n")
puts
puts "Full report: #{REPORT}"
