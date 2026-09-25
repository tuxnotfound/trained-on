module TrainedOn
  # Rebuilds one document's clause history from the OTA versions repo:
  # locate the anchored clause in every recorded version, collapse runs of
  # identical hashes into ClauseVersions, and emit a ClauseEvent per genuine
  # transition.
  #
  # Rebuilding is the only mode. It is cheap (the corpus is small) and it means
  # a re-anchor immediately re-derives history. Human review survives the
  # rebuild: verdicts are carried over by (date, resulting clause hash, kind),
  # so an event whose outcome is unchanged keeps its decision.
  class Backfill
    Run = Struct.new(:result, :first, :last, :count, keyword_init: true) do
      def sha256 = result.sha256
      def lost? = result.anchor_lost
    end

    # Everything a review produced, carried across a rebuild.
    REVIEW_ATTRS = %w[state classification direction one_line note panel decided_by reviewed_at].freeze

    attr_reader :document, :created_events

    def initialize(document, corpus: Corpus.versions_repo)
      @document = document
      @corpus = corpus
      @created_events = []
    end

    def call
      phrases = document.anchors.pluck(:phrase)
      return self if phrases.empty?

      @versions = @corpus.versions(document.ota_path)
      runs = collapse(@versions, Locator.new(phrases))
      return self if runs.empty?

      ClauseEvent.transaction do
        carried = carry_over_reviews
        document.clause_events.delete_all
        document.clause_versions.delete_all
        versions = runs.map { |run| create_version(run) }
        versions.last.update!(unanchored_hits: head_unanchored_hits(runs.last))
        emit_events(runs, versions, carried)
        document.update!(versions_walked: @versions.size, phantom_versions: @phantoms, walked_at: Time.current)
      end
      self
    end

    private

    # Also counts phantom versions: recorded as a change by OTA, identical to
    # the previous version once normalised (tracking IDs, word joiners, spacing).
    def collapse(versions, locator)
      @phantoms = 0
      previous = nil
      versions.each_with_object([]) do |version, runs|
        markdown = @corpus.show(version.sha, version.path)
        normalised = Normaliser.normalise(markdown)
        @phantoms += 1 if previous == normalised
        previous = normalised
        result = locator.call(markdown)
        if runs.last && runs.last.sha256 == result.sha256 && runs.last.lost? == result.anchor_lost
          runs.last.last = version
          runs.last.count += 1
        else
          runs << Run.new(result:, first: version, last: version, count: 1)
        end
      end
    end

    def head_unanchored_hits(run)
      phrases = document.anchors.pluck(:phrase)
      Locator.new(phrases).call(@corpus.show(run.last.sha, run.last.path), with_net: true).unanchored_hits
    end

    def create_version(run)
      document.clause_versions.create!(
        text: run.result.text,
        sha256: run.sha256,
        effective_at: run.first.committed_at,
        last_seen_at: run.last.committed_at,
        ota_commit_sha: run.first.sha,
        versions_count: run.count,
        anchor_lost: run.lost?
      )
    end

    # An anchor_lost run is recorded as its own event and then skipped over:
    # the next located run is compared with the last located one, so an OTA
    # capture gap between two identical clauses produces no change event.
    def emit_events(runs, versions, carried)
      last_located = runs.first.lost? ? nil : versions.first
      runs.each_with_index.drop(1).each do |run, i|
        version = versions[i]
        if run.lost?
          create_event(kind: "anchor_lost", from: last_located, to: version, run:, carried:)
        else
          if last_located.nil? || last_located.sha256 != version.sha256
            create_event(kind: "change", from: last_located, to: version, run:, carried:)
          end
          last_located = version
        end
      end
    end

    def create_event(kind:, from:, to:, run:, carried:)
      occurred_on = run.first.committed_at.to_date
      attrs = {
        kind:, from_version: from, to_version: to, occurred_on:,
        suspected_extraction: ExtractionCheck.suspected?(@versions, run.first),
        reverses_event: (kind == "change" && from ? reversed_change(from, to) : nil)
      }
      key = [ occurred_on, to.sha256, kind ]
      event = document.clause_events.create!(attrs.merge(carried.fetch(key, {})))
      @created_events << event unless carried.key?(key)
    end

    # Every existing event is carried over, reviewed or not: an event already
    # in the queue is not "new" again, so the nightly email does not repeat it.
    # The most recent earlier change that this one undoes: wording it added is
    # gone again, and wording it removed is back. Paragraph-level, so a partial
    # reversal counts when whole sentences come back.
    def reversed_change(from, to)
      gone = from.paragraphs - to.paragraphs
      came = to.paragraphs - from.paragraphs
      return if gone.empty? || came.empty?
      document.clause_events.where(kind: "change").where.not(from_version_id: nil)
              .includes(:from_version, :to_version).order(occurred_on: :desc, id: :desc).find do |earlier|
        earlier_gone = earlier.from_version.paragraphs - earlier.to_version.paragraphs
        earlier_came = earlier.to_version.paragraphs - earlier.from_version.paragraphs
        (earlier_came & gone).any? && (earlier_gone & came).any?
      end
    end

    def carry_over_reviews
      document.clause_events.includes(:to_version).each_with_object({}) do |event, memo|
        memo[[ event.occurred_on, event.to_version.sha256, event.kind ]] = event.attributes.slice(*REVIEW_ATTRS)
      end
    end
  end
end
