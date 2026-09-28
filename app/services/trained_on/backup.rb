require "zlib"

module TrainedOn
  # A consistent copy of the SQLite database, gzipped, shipped to Cloudflare
  # R2 (S3-compatible) every night. One shared box means one disk, so the
  # copy must leave the box before anything is public. Uses the same R2_*
  # settings as the other apps on that box.
  class Backup
    KEEP_LOCAL = 7
    KEEP_REMOTE = 30
    Result = Data.define(:path, :key)

    def self.configured? = %w[R2_ENDPOINT R2_BUCKET R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY].all? { |k| ENV[k].present? }

    def initialize(client: nil, dir: Rails.root.join("storage/backups"), prefix: "trained-on/#{Rails.env}")
      @client = client
      @dir = dir
      @prefix = prefix
    end

    # Always writes the local copy. Uploads when R2 is configured, and
    # otherwise says so loudly, because a local-only backup on the box is
    # not a backup.
    def run!
      path = snapshot!
      key = upload(path)
      Rails.logger.warn("[backup] R2 is not configured; the copy stayed on the box at #{path}") unless key
      prune_local
      Result.new(path:, key:)
    end

    private

    def snapshot!
      FileUtils.mkdir_p(@dir)
      stamp = Time.current.utc.strftime("%Y%m%d-%H%M")
      raw = @dir.join("#{Rails.env}-#{stamp}.sqlite3")
      source = ActiveRecord::Base.connection.raw_connection
      destination = SQLite3::Database.new(raw.to_s)
      copy = SQLite3::Backup.new(destination, "main", source, "main")
      # A writer holding the database makes step return BUSY or LOCKED; wait a
      # little rather than ship an empty file.
      10.times do
        status = copy.step(-1)
        break if status == SQLite3::Constants::ErrorCode::DONE
        sleep 0.5
      end
      remaining = copy.remaining
      copy.finish
      destination.close
      raise "backup incomplete: #{remaining} pages left" unless remaining.zero?

      gz = "#{raw}.gz"
      Zlib::GzipWriter.open(gz) { |out| File.open(raw, "rb") { |io| IO.copy_stream(io, out) } }
      File.delete(raw)
      Pathname(gz)
    end

    def upload(path)
      return nil unless @client || self.class.configured?
      key = "#{@prefix}/#{path.basename}"
      File.open(path, "rb") { |io| client.put_object(bucket: bucket, key:, body: io, content_type: "application/gzip") }
      prune_remote
      key
    end

    def prune_local
      Dir.glob(@dir.join("#{Rails.env}-*.sqlite3.gz")).sort[0...-KEEP_LOCAL].each { |old| File.delete(old) }
    end

    def prune_remote
      keys = client.list_objects_v2(bucket: bucket, prefix: "#{@prefix}/").contents.map(&:key).sort
      keys[0...-KEEP_REMOTE].each { |old| client.delete_object(bucket: bucket, key: old) }
    end

    def bucket = ENV.fetch("R2_BUCKET")

    def client
      @client ||= begin
        require "aws-sdk-s3"
        Aws::S3::Client.new(
          endpoint: ENV.fetch("R2_ENDPOINT"), region: "auto",
          access_key_id: ENV.fetch("R2_ACCESS_KEY_ID"), secret_access_key: ENV.fetch("R2_SECRET_ACCESS_KEY"),
          force_path_style: true
        )
      end
    end
  end
end
