# Daily at 05:00, after the 04:00 refresh and panel. The window is 25 hours,
# so a change published between two runs is never missed; a page announced
# twice costs nothing.
class AnnounceChangesJob < ApplicationJob
  queue_as :default

  def perform
    Changes::AnnounceService.new(since: 25.hours.ago).call!
  end
end
