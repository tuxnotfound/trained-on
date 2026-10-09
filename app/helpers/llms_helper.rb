module LlmsHelper
  # The registry row's source line in /llms.txt, with the same caveats the
  # registry page shows, so a model quoting it carries them too.
  def llms_source(tier)
    return "" unless tier.document
    parts = [ tier.document.name ]
    if tier.effective_on
      parts << "on record since #{tier.effective_on.iso8601}#{", Open Terms Archive's first capture, so the words may be older" if tier.since_first_capture?}"
    end
    parts << "the archive's capture is broken; last good capture #{tier.document.last_located_version.last_seen_at.to_date.iso8601}" if tier.document.capture_broken?
    parts << "last seen #{tier.verified_on.iso8601}" if tier.verified_on
    " (#{parts.join("; ")})"
  end
end
