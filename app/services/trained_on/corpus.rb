require "open3"

module TrainedOn
  # Read-only access to a local clone of an Open Terms Archive git repository.
  # Shells out to git: the corpus is small and rugged would add a native build.
  class Corpus
    Version = Data.define(:sha, :committed_at, :path, :subject) do
      # OTA labels commits that come from changing its own extraction rules.
      def extraction_upgrade? = subject.to_s.match?(/technical or declaration upgrade/i)
    end

    class Error < StandardError; end

    def self.versions_repo = new(ENV.fetch("TRAINED_ON_CORPUS", Rails.root.join("corpus/genai-contrib-versions").to_s))

    attr_reader :dir

    def initialize(dir)
      @dir = dir
    end

    def present? = File.directory?(File.join(dir, ".git"))

    # Every recorded version of a file, oldest first. No --follow: OTA never
    # renames, and rename detection jumps between near-identical sibling
    # documents (ChatGPT's notice followed into DALL·E's).
    def versions(path)
      git("-c", "core.quotepath=false", "log", "--format=%H%x09%cI%x09%s", "--", path)
        .each_line.map do |line|
          sha, date, subject = line.chomp.split("\t", 3)
          Version.new(sha:, committed_at: Time.iso8601(date), path:, subject:)
        end.reverse
    end

    def show(sha, path) = git("show", "#{sha}:#{path}").force_encoding("UTF-8")

    def head = git("rev-parse", "HEAD").strip

    def files(glob) = Dir.glob(File.join(dir, glob)).map { |f| f.delete_prefix("#{dir}/") }.sort

    def pull! = git("pull", "--ff-only", "--quiet")

    REMOTE = "https://github.com/OpenTermsArchive/genai-contrib-versions.git"

    # A fresh server has no corpus yet. A blobless clone is a few megabytes;
    # file contents are fetched lazily the first time a version is shown.
    def ensure_clone!
      return self if present?
      FileUtils.mkdir_p(File.dirname(dir))
      _, err, status = Open3.capture3("git", "clone", "--quiet", "--filter=blob:none", REMOTE, dir)
      raise Error, "clone failed: #{err}" unless status.success?
      self
    end

    private

    def git(*args)
      out, err, status = Open3.capture3("git", "-C", dir, *args)
      raise Error, "git #{args.join(' ')} failed: #{err}" unless status.success?
      out
    end
  end
end
