require "test_helper"

class TrainedOn::BackupTest < ActiveSupport::TestCase
  class FakeS3
    Obj = Struct.new(:key)
    attr_reader :objects, :deleted
    def initialize(existing = []) = (@objects, @deleted = existing.map { |k| Obj.new(k) }, [])
    def put_object(bucket:, key:, body:, content_type:) = (@objects << Obj.new(key); @last_body = body.read)
    def list_objects_v2(bucket:, prefix:) = Struct.new(:contents).new(@objects.select { |o| o.key.start_with?(prefix) })
    def delete_object(bucket:, key:) = (@deleted << key; @objects.reject! { |o| o.key == key })
    def last_body = @last_body
  end

  setup do
    @dir = Rails.root.join("tmp/backups-test-#{SecureRandom.hex(4)}")
    ENV["R2_BUCKET"] = "test-bucket"
  end

  teardown do
    FileUtils.rm_rf(@dir)
    ENV.delete("R2_BUCKET")
  end

  test "writes a gzipped SQLite copy and uploads it under the app's prefix" do
    s3 = FakeS3.new
    result = TrainedOn::Backup.new(client: s3, dir: @dir, prefix: "trained-on/test").run!

    assert result.path.to_s.end_with?(".sqlite3.gz")
    assert File.exist?(result.path)
    assert_match %r{\Atrained-on/test/test-\d{8}-\d{4}\.sqlite3\.gz\z}, result.key
    assert_equal s3.last_body, File.binread(result.path)
    sql = Zlib::GzipReader.open(result.path, &:read)
    assert sql.start_with?("SQLite format 3"), "the upload is a real SQLite file"
  end

  test "keeps only the newest remote copies" do
    existing = (1..31).map { |i| format("trained-on/test/test-202601%02d-0330.sqlite3.gz", i) }
    s3 = FakeS3.new(existing)
    TrainedOn::Backup.new(client: s3, dir: @dir, prefix: "trained-on/test").run!
    assert_equal 30, s3.objects.size
    assert_equal [ "trained-on/test/test-20260101-0330.sqlite3.gz", "trained-on/test/test-20260102-0330.sqlite3.gz" ], s3.deleted
  end

  test "without R2 settings it keeps the local copy and reports no key" do
    ENV.delete("R2_BUCKET")
    result = TrainedOn::Backup.new(dir: @dir).run!
    assert_nil result.key
    assert File.exist?(result.path)
  end
end
