module TrainedOn
  # Three readers, one model from each of three companies, decide what a
  # person no longer has time to. Every reader sees only the texts: never
  # another reader's answer, never the suggested verdict, never the vendor's
  # reputation. The panel publishes a change only when all three agree it is a
  # change of position, a scope change or a disclosure, and a final check
  # accepts one of their summaries. Everything else waits for a person.
  class Panel
    MIN_READERS = 3
    PUBLIC = ClauseEvent::PUBLIC_CLASSIFICATIONS

    Outcome = Data.define(:decision, :reason)
    Reading = Data.define(:provider, :model, :answer, :error) do
      def ok? = error.nil?
    end

    EVENT_SYSTEM = <<~PROMPT.freeze
      You compare two versions of the clause in an AI vendor's terms that says whether the vendor trains AI models on its users' data. You see only the old and new text of that clause.
      Classify the change:
      - position: what is trained on, the default (opt-in or opt-out), who may train, or whether an opt-out exists changed.
      - scope: a plan, product, data source or purpose was added to or removed from an existing rule.
      - disclosure: new description of existing practice; the position did not change.
      - wording: renames, links, punctuation, or a restatement with the same meaning.
      - churn: the texts differ only because different paragraphs were captured, not because the vendor changed anything.
      - unrelated: the change is not about training on user data.
      direction: now_trains, no_longer_trains, scope_widened, scope_narrowed, disclosure or wording_only.
      material: true only for position and scope.
      one_line: one plain sentence of at most 30 words for someone deciding whether their company may use this tool. Name the company, quote the decisive words, keep every qualifier such as "by default", "in certain markets" or "unless you opt out", and state no motive.
      confidence: high, medium or low.
      concerns: anything ambiguous or that could be read two ways; otherwise an empty string.
      Answer from the text alone. Do not use outside knowledge of the vendor.
    PROMPT

    EVENT_SCHEMA = {
      "type" => "object",
      "properties" => {
        "classification" => { "type" => "string", "enum" => ClauseEvent::CLASSIFICATIONS },
        "direction" => { "type" => "string", "enum" => ClauseEvent::DIRECTIONS },
        "one_line" => { "type" => "string" },
        "material" => { "type" => "boolean" },
        "confidence" => { "type" => "string", "enum" => %w[high medium low] },
        "concerns" => { "type" => "string" }
      },
      "required" => %w[classification direction one_line material confidence concerns],
      "additionalProperties" => false
    }.freeze

    SKEPTIC_SYSTEM = <<~PROMPT.freeze
      You check one-line summaries of a change to the clause in an AI vendor's terms about training on users' data. You see the old and new text and several candidate summaries.
      Choose the one summary that states only what the texts show, keeps every qualifier (such as "by default", "in certain markets", "unless you opt out"), names the company, quotes the decisive words, and attributes no motive. Between two accurate summaries prefer the shorter and more cautious one.
      If none is acceptable, or every one is longer than 35 words, answer -1 and say what is wrong with them.
      Answer with the 0-based index of your choice.
    PROMPT

    SKEPTIC_SCHEMA = {
      "type" => "object",
      "properties" => {
        "index" => { "type" => "integer", "description" => "0-based index of the acceptable summary, or -1 if none is acceptable" },
        "reason" => { "type" => "string" }
      },
      "required" => %w[index reason],
      "additionalProperties" => false
    }.freeze

    TIER_SYSTEM = <<~PROMPT.freeze
      You check one row of a registry that answers, per vendor plan, whether an AI tool trains on its users' inputs. You see the plan name, the current training clause from the vendor's document, and the sentence the registry quotes. Pick the answer the clause supports for that plan:
      - trains_opt_out: trains on inputs by default; the user can opt out.
      - trains_no_opt_out: trains on inputs; no opt-out is stated.
      - trains_regional_opt_out: trains on inputs; an opt-out exists only in some regions.
      - no_training_default: does not train by default; may with an opt-in.
      - no_training: does not train on inputs.
      - unclear: the clause does not say clearly.
      reason: one sentence quoting the decisive words. confidence: high, medium or low.
      Answer from the clause alone. Do not use outside knowledge of the vendor.
    PROMPT

    TIER_SCHEMA = {
      "type" => "object",
      "properties" => {
        "answer" => { "type" => "string", "enum" => Tier::ANSWERS.keys },
        "reason" => { "type" => "string" },
        "confidence" => { "type" => "string", "enum" => %w[high medium low] }
      },
      "required" => %w[answer reason confidence],
      "additionalProperties" => false
    }.freeze

    attr_reader :readers

    def initialize(readers: Readers.configured, skeptic: nil)
      @readers = readers
      @skeptic = skeptic || readers.find { |r| r.is_a?(Readers::AnthropicReader) } || readers.first
    end

    def enough_readers? = readers.size >= MIN_READERS

    # --- events ---------------------------------------------------------------

    def review_event(event)
      return Outcome.new("skipped", "not a pending change") unless event.kind == "change" && event.state == "pending"
      if event.suspected_extraction
        return record_event(event, "human", "coincides with a change to Open Terms Archive's capture rules; a person must compare the captures", {})
      end

      user = event_prompt(event)
      readings = ask_all(EVENT_SYSTEM, user, EVENT_SCHEMA)
      result = { "ran_at" => Time.current.utc.iso8601, "readers" => readings.map(&:to_h) }
      decision, reason, source, extra = decide_event(readings, user)
      record_event(event, decision, reason, result.merge(extra), source)
    end

    # --- registry rows --------------------------------------------------------

    def check_tier(tier)
      version = tier.document&.last_located_version
      return Outcome.new("skipped", "quote is not in the latest capture") unless version && tier.quote_in_clause?

      readings = ask_all(TIER_SYSTEM, tier_prompt(tier, version), TIER_SCHEMA)
      result = { "ran_at" => Time.current.utc.iso8601, "readers" => readings.map(&:to_h) }
      decision, reason = decide_tier(tier, readings)
      result = result.merge("decision" => decision, "reason" => reason)

      if decision == "confirmed"
        attrs = { panel: result }
        attrs.merge!(confirmed_by: "panel", confirmed_at: Time.current) if tier.confirmed_by.nil?
        tier.update_columns(attrs)
      else
        # A panel confirmation is withdrawn on disagreement; a person's stands.
        attrs = { panel: result }
        attrs.merge!(confirmed_by: nil, confirmed_at: nil) if tier.confirmed_by == "panel"
        tier.update_columns(attrs)
      end
      Outcome.new(decision, reason)
    end

    private

    def event_prompt(event)
      <<~TEXT
        Vendor: #{event.vendor.name_with_company}
        Document: #{event.document.name}
        First recorded: #{event.occurred_on.iso8601}
        #{reversal_note(event)}

        OLD TEXT:
        #{event.from_version&.text.presence || "(no training clause was found in earlier captures)"}

        NEW TEXT:
        #{event.to_version.text.presence || "(no training clause found)"}
      TEXT
    end

    # Context from the record itself, not from any reader: a change that undoes
    # an earlier one should be read as the mirror of that change.
    def reversal_note(event)
      return "" unless event.reverses_event
      earlier = event.reverses_event
      "Note from the record: this change reverses a change first recorded on #{earlier.occurred_on.iso8601}. Wording introduced then is removed again, and wording removed then is back."
    end

    def tier_prompt(tier, version)
      <<~TEXT
        Vendor: #{tier.vendor.name_with_company}
        Plan: #{tier.name}
        Document: #{tier.document.name}

        CURRENT CLAUSE:
        #{version.text}

        THE REGISTRY QUOTES: "#{tier.quote}"
      TEXT
    end

    def decide_event(readings, user)
      ok = readings.select(&:ok?)
      failed = readings.reject(&:ok?)
      return [ "human", "only #{readers.size} of #{MIN_READERS} readers configured; three from different companies are needed to decide", nil, {} ] unless enough_readers?
      return [ "human", "no answer from #{failed.map(&:provider).join(', ')}: #{failed.map(&:error).join('; ')}", nil, {} ] if failed.any?

      classes = ok.map { |r| r.answer["classification"] }.uniq
      if classes.size > 1
        return [ "human", "readers disagree: " + ok.map { |r| "#{r.provider} says #{r.answer['classification']}" }.join(", "), nil, {} ]
      end
      low = ok.select { |r| r.answer["confidence"] == "low" }
      if low.any?
        return [ "human", "not confident: " + low.map { |r| "#{r.provider}: #{r.answer['concerns'].presence || 'no reason given'}" }.join("; "), nil, {} ]
      end

      classification = classes.first
      return [ "rejected", "all #{ok.size} readers call it #{classification}", ok.first, {} ] unless PUBLIC.include?(classification)

      choice = pick_summary(user, ok)
      index = choice["index"]
      if index.nil?
        [ "human", "agreed it is #{classification}, but no summary was accepted: #{choice['reason']}", nil, { "skeptic" => choice } ]
      else
        [ "published", "all #{ok.size} readers agree: #{classification}; summary by #{ok[index].provider}", ok[index], { "skeptic" => choice } ]
      end
    end

    def decide_tier(tier, readings)
      ok = readings.select(&:ok?)
      failed = readings.reject(&:ok?)
      return [ "flagged", "only #{readers.size} of #{MIN_READERS} readers configured" ] unless enough_readers?
      return [ "flagged", "no answer from #{failed.map(&:provider).join(', ')}: #{failed.map(&:error).join('; ')}" ] if failed.any?
      answers = ok.map { |r| r.answer["answer"] }.uniq
      return [ "flagged", "readers disagree: " + ok.map { |r| "#{r.provider} says #{r.answer['answer']}" }.join(", ") ] if answers.size > 1
      return [ "flagged", "all #{ok.size} readers read it as #{answers.first}; the row says #{tier.answer}" ] unless answers.first == tier.answer
      [ "confirmed", "all #{ok.size} readers read it as #{tier.answer}" ]
    end

    # The candidate summaries are shown unlabelled, in reader order.
    def pick_summary(user, readings)
      candidates = readings.each_with_index.map { |r, i| "[#{i}] #{r.answer['one_line']}" }.join("\n")
      answer = @skeptic.ask(system: SKEPTIC_SYSTEM, user: "#{user}\nCANDIDATE SUMMARIES:\n#{candidates}\n", schema: SKEPTIC_SCHEMA)
      index = Integer(answer["index"], exception: false)
      index = nil unless index && index.between?(0, readings.size - 1)
      { "provider" => @skeptic.provider, "model" => @skeptic.model, "index" => index, "reason" => answer["reason"].to_s }
    rescue Readers::Error => e
      { "provider" => @skeptic.provider, "model" => @skeptic.model, "index" => nil, "reason" => e.message }
    end

    def ask_all(system, user, schema)
      readers.map { |reader| Thread.new { read(reader, system, user, schema) } }.map(&:value)
    end

    def read(reader, system, user, schema)
      answer = reader.ask(system:, user:, schema:)
      validate!(answer, schema)
      Reading.new(provider: reader.provider, model: reader.model, answer:, error: nil)
    rescue Readers::Error => e
      Rails.logger.warn("[panel] #{reader.provider}: #{e.message}")
      Reading.new(provider: reader.provider, model: reader.model, answer: nil, error: e.message.to_s[0, 400])
    end

    def validate!(answer, schema)
      raise Readers::Error, "answer is not an object" unless answer.is_a?(Hash)
      schema["required"].each { |key| raise Readers::Error, "answer lacks #{key}" unless answer.key?(key) }
      schema["properties"].each do |key, spec|
        next unless spec["enum"] && answer.key?(key)
        raise Readers::Error, "#{key} is #{answer[key].inspect}, not one of #{spec['enum'].join('/')}" unless spec["enum"].include?(answer[key])
      end
    end

    def record_event(event, decision, reason, result, source = nil)
      panel = result.merge("decision" => decision, "reason" => reason)
      case decision
      when "published"
        event.update!(state: "published", classification: source.answer["classification"], direction: source.answer["direction"],
                      one_line: source.answer["one_line"], decided_by: "panel", reviewed_at: Time.current, panel:)
      when "rejected"
        event.update!(state: "rejected", classification: source.answer["classification"], direction: source.answer["direction"],
                      decided_by: "panel", reviewed_at: Time.current, panel:)
      else
        event.update!(panel:)
      end
      Outcome.new(decision, reason)
    end
  end
end
