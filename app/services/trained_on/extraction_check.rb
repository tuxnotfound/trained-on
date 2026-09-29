module TrainedOn
  # Flags events that coincide with a change to OTA's own capture rules, when
  # the next recorded text can differ because of the capture (a new CSS
  # selector, a new URL, another page combined in), not because the vendor
  # changed anything. Flagged events never reach the panel; a person decides.
  #
  # Two signals. OTA commits a re-extraction of an existing snapshot as "Apply
  # technical or declaration upgrade on <doc>". But a changed URL or a newly
  # combined page is fetched fresh and recorded as an ordinary change, so the
  # declarations' own history is checked too. That is how Jasper's EULA became
  # its Terms of Service on 2024-02-08 without any wording changing.
  module ExtractionCheck
    WINDOW = 1.day
    DECLARATION_WINDOW = 2.days # OTA captures twice a day; allow a missed run

    module_function

    # versions: every recorded version of the document; first: the first
    # version of the run whose text changed; declaration_changes: when the
    # service's capture rules changed.
    def suspected?(versions, first, declaration_changes = [])
      at = first.committed_at
      versions.any? { |v| v.extraction_upgrade? && v.committed_at <= at && v.committed_at >= at - WINDOW } ||
        declaration_changes.any? { |t| t <= at && t >= at - DECLARATION_WINDOW }
    end
  end
end
