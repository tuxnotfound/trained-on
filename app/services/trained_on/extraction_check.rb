module TrainedOn
  # Flags events that coincide with a change to OTA's own extraction rules.
  # OTA commits those as "Apply technical or declaration upgrade on <doc>";
  # the next recorded text can then differ because of the extraction (a new
  # CSS selector, a new URL), not because the vendor changed anything. Flagged
  # events are not rejected automatically. The reviewer decides.
  module ExtractionCheck
    WINDOW = 1.day

    module_function

    # versions: every recorded version of the document; first: the first
    # version of the run whose text changed.
    def suspected?(versions, first)
      versions.any? do |v|
        v.extraction_upgrade? && v.committed_at <= first.committed_at && v.committed_at >= first.committed_at - WINDOW
      end
    end
  end
end
