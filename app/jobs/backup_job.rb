# Nightly, before the refresh, so the copy predates the day's changes.
class BackupJob < ApplicationJob
  queue_as :default

  def perform
    result = TrainedOn::Backup.new.run!
    Rails.logger.info("[backup] #{result.key ? "uploaded #{result.key}" : "local only: #{result.path}"}")
  end
end
