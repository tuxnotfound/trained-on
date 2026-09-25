module ApplicationHelper
  ANSWER_TONE = {
    "trains_opt_out" => "trains", "trains_no_opt_out" => "trains", "trains_regional_opt_out" => "trains", "trains_in_some_markets" => "trains",
    "your_choice_default_unstated" => "unclear",
    "no_training_default" => "safe", "no_training" => "safe", "unclear" => "unclear"
  }.freeze

  CLASSIFICATION_LABEL = {
    "position" => "Change of position", "scope" => "Scope change", "disclosure" => "New disclosure",
    "wording" => "Wording only", "churn" => "Not a real change", "unrelated" => "Not about training"
  }.freeze

  def answer_badge(tier)
    tag.span(tier.answer_text, class: "answer answer--#{ANSWER_TONE.fetch(tier.answer)}")
  end

  def classification_badge(event)
    return "" unless event.classification
    tag.span(CLASSIFICATION_LABEL.fetch(event.classification), class: "kind kind--#{event.classification}")
  end

  def date_tag(date, format: :long)
    return tag.span("n/a", class: "date") unless date
    date = date.to_date
    tag.time(format == :iso ? date.iso8601 : l(date, format: format), datetime: date.iso8601, class: "date")
  end

  # "between 3 Mar and 9 Mar 2026", or a single date when OTA captured daily.
  def change_window(event)
    if event.gap?
      safe_join([ "between ", date_tag(event.window_start), " and ", date_tag(event.occurred_on) ])
    else
      safe_join([ "on ", date_tag(event.occurred_on) ])
    end
  end

  # The date OTA first recorded the quoted words, plus the caveat that bounds it:
  # either it is OTA's very first capture (the words may be older), or OTA had
  # a capture gap before it (the change happened somewhere in the gap).
  def in_force_since(tier, inline: false)
    return tag.span("n/a", class: "date") unless tier.effective_on
    caveat =
      if tier.since_first_capture? then "first capture, may be older"
      elsif tier.previous_capture_on then safe_join([ "previous capture ", date_tag(tier.previous_capture_on) ])
      end
    return date_tag(tier.effective_on) unless caveat
    inline ? safe_join([ date_tag(tier.effective_on), " (", caveat, ")" ]) : safe_join([ date_tag(tier.effective_on), tag.span(caveat, class: "gap") ])
  end

  # Keeps preview on across links in development screenshots.
  def default_url_options = preview? && Rails.env.development? && params[:preview] ? { preview: "1" } : {}

  def render_diff(diff)
    parts = diff.chunks.map do |chunk|
      text = chunk.text.gsub("\n\n", "\n")
      case chunk.action
      when "=" then text
      when "-" then tag.del(text)
      else tag.ins(text)
      end
    end
    tag.div(safe_join(parts), class: "diff")
  end

  def clause_paragraphs(text)
    safe_join(text.to_s.split("\n\n").map { |p| tag.p(p) })
  end

  def draft_marker(record)
    return "" unless preview?
    draft = record.is_a?(Tier) ? record.verified_on.nil? : record.draft?
    draft ? tag.span("draft", class: "draft-marker") : ""
  end

  def page_title(*parts)
    content_for(:title, (parts.compact + [ "Trained On" ]).join(" · "))
  end
end
