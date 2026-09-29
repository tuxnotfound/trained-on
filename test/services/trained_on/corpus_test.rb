require "test_helper"

class TrainedOn::CorpusTest < ActiveSupport::TestCase
  test "declaration changes for one service, read from origin/main" do
    Dir.mktmpdir do |tmp|
      upstream = File.join(tmp, "upstream")
      FileUtils.mkdir_p(File.join(upstream, "declarations"))
      git = ->(*args, env: {}) { system(env, "git", "-C", upstream, *args, exception: true, out: File::NULL, err: File::NULL) }
      git.("init", "--quiet", "--initial-branch=main")
      { "Acme.json" => "2025-01-31T15:00:00Z", "Other.json" => "2025-02-01T09:00:00Z", "Acme.filters.js" => "2025-03-01T09:00:00Z" }.each do |file, date|
        File.write(File.join(upstream, "declarations", file), date)
        git.("add", ".")
        git.("-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", file, env: { "GIT_AUTHOR_DATE" => date, "GIT_COMMITTER_DATE" => date })
      end

      clone = TrainedOn::Corpus.new(File.join(tmp, "clone"), remote: upstream).ensure_clone!
      assert_equal [ Time.utc(2025, 3, 1, 9), Time.utc(2025, 1, 31, 15) ], clone.declaration_changes("Acme")
    end
  end
end
