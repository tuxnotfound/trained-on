ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: 1)

    def fixture_text(name) = file_fixture(name).read

    # Minimal records for a document with anchors, without YAML fixtures.
    def build_document(anchors: [ "train our models" ], ota_path: "Acme/Privacy Policy.md", vendor_name: "Acme")
      vendor = Vendor.create!(name: vendor_name, slug: vendor_name.parameterize, ota_service: vendor_name)
      document = vendor.documents.create!(name: "Privacy Policy", ota_path:)
      anchors.each { |phrase| document.anchors.create!(phrase:) }
      document
    end
  end
end

# An in-memory stand-in for an OTA versions repository.
class FakeCorpus
  def initialize(versions_by_path)
    @data = versions_by_path.transform_values do |versions|
      versions.each_with_index.map do |(date, text, subject), i|
        [ TrainedOn::Corpus::Version.new(sha: format("%040x", i + 1 + (text.hash.abs % 10_000) * 100), committed_at: Time.iso8601("#{date}T12:00:00Z"), path: nil, subject: subject || "Record new changes"), text ]
      end
    end
  end

  def versions(path) = @data.fetch(path).map { |v, _| v.with(path:) }
  def show(sha, path) = @data.fetch(path).find { |v, _| v.sha == sha }.last
  def pull! = nil
end
