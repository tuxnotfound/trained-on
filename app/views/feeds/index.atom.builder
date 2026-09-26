atom_feed(root_url: root_url, id: "tag:trained-on,2026:#{request.path}") do |feed|
  feed.title @title
  feed.subtitle "Every time an AI company changed what its terms say about training on your prompts. Derived from Open Terms Archive, ODC-By 1.0."
  feed.updated(@events.first&.reviewed_at || Time.current)

  @events.each do |event|
    feed.entry(event, url: change_url(event), id: "tag:trained-on,2026:change/#{event.slug}", published: event.occurred_on.to_time, updated: event.reviewed_at || event.updated_at) do |entry|
      entry.title "#{event.vendor.name}: #{event.one_line}"
      entry.content(<<~HTML, type: "html")
        <p>#{ERB::Util.h(event.one_line)}</p>
        <p>#{ERB::Util.h(ApplicationHelper::CLASSIFICATION_LABEL[event.classification])}, recorded #{event.occurred_on.iso8601} in #{ERB::Util.h(event.document.name)}.</p>
      HTML
      entry.author { |author| author.name "Trained On" }
    end
  end
end
