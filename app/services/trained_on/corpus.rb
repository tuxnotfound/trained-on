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

    VERSIONS_REMOTE = "https://github.com/OpenTermsArchive/genai-contrib-versions.git"
    DECLARATIONS_REMOTE = "https://github.com/OpenTermsArchive/genai-contrib-declarations.git"

    def self.versions_repo = new(ENV.fetch("TRAINED_ON_CORPUS", Rails.root.join("corpus/genai-contrib-versions").to_s))

    # OTA's capture rules, cloned next to the versions.
    def self.declarations_repo
      dir = ENV.fetch("TRAINED_ON_DECLARATIONS") { File.join(File.dirname(versions_repo.dir), "genai-contrib-declarations") }
      new(dir, remote: DECLARATIONS_REMOTE)
    end

    attr_reader :dir

    def initialize(dir, remote: VERSIONS_REMOTE)
      @dir = dir
      @remote = remote
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

    # Declarations are only read from origin/main, so fetching is enough and a
    # local clone may sit on any branch.
    def fetch! = git("fetch", "--quiet", "origin", "main")

    # When the rules for capturing a service changed on OTA's main branch: the
    # declaration, its filters and its history file. First parent, so a merged
    # pull request counts from the moment it was merged.
    def declaration_changes(service)
      paths = %w[json filters.js history.json].map { |ext| "declarations/#{service}.#{ext}" }
      git("log", "--first-parent", "--format=%cI", "origin/main", "--", *paths).split.map { |t| Time.iso8601(t) }
    end

    # A fresh server has no corpus yet. A blobless clone is a few megabytes;
    # file contents are fetched lazily the first time a version is shown.
    def ensure_clone!
      return self if present?
      FileUtils.mkdir_p(File.dirname(dir))
      _, err, status = Open3.capture3("git", "clone", "--quiet", "--filter=blob:none", @remote, dir)
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
