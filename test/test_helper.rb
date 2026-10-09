ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# The network stays out of tests: GitHub and the gate's URL probes answer from
# these stubs. Every URL loads, but those in unreachable. Hackatime and Hack
# Club Auth use FakeServices.
module OfflineGithub
  REPO = Github::Repo.new(full_name: "pet/rock", private: false, default_branch: "main", pushed_at: "2026-09-22T00:00:00Z",
                          commits: 12, readme: true, stars: 3)
  def self.install!
    Github.define_singleton_method(:repo) { |_name| OfflineGithub.repo }
    Github.define_singleton_method(:release_for) { |url| url.to_s.include?("/releases") ? OfflineGithub.release : nil }
    Github.define_singleton_method(:readme_html) { |_name| "<h1>rock</h1><script>alert(1)</script>" }
    Github.define_singleton_method(:recent_commits) { |_name, **| [] }
    SubmitGate.prepend(Module.new do
      private
      def status_ok?(url) = !OfflineGithub.unreachable.include?(url)
    end)
  end

  class << self
    attr_writer :repo, :release
    def repo = @repo || REPO
    def release = @release || Github::Release.new(tag: "v1", url: "x", assets: [ { "name" => "RockPet.dmg", "size" => 1000, "url" => "x" } ])
    def unreachable = @unreachable ||= []
    def reset! = (@repo = @release = @unreachable = nil)
  end
end
OfflineGithub.install!

# Stardance's database stays out of tests too. The repos shipped on Stardance
# are none, unless a test sets them or an error. asked counts the reads.
module OfflineStardance
  REAL = StardanceRepos.method(:fetch)

  def self.install!
    StardanceRepos.define_singleton_method(:fetch) do |mcp = nil|
      next OfflineStardance::REAL.call(mcp) if mcp
      OfflineStardance.asked += 1
      raise OfflineStardance.error if OfflineStardance.error
      OfflineStardance.urls
    end
  end

  class << self
    attr_accessor :urls, :error, :asked
    def reset! = (@urls = []; @error = nil; @asked = 0)
  end
end
OfflineStardance.install!
OfflineStardance.reset!

# R2 stand-in for tests only. Development and production never use it.
class MemoryScreenshotStore
  attr_reader :objects, :deleted

  def initialize = (@objects = {}; @deleted = [])
  def configured? = true
  def put(key, bytes) = (@objects[key] = bytes; url(key))
  def delete(key) = (@deleted << key; @objects.delete(key))
  def url(key) = "https://playground.hackclub-assets.com/#{key}"
end

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    setup do
      OfflineGithub.reset!
      OfflineStardance.reset!
      ScreenshotStore.current = MemoryScreenshotStore.new
      # A window from 2000 to tomorrow, so the fake's time all counts whatever
      # the date. Tests of the window itself set their own.
      ProgramWindow.current = ProgramWindow.new(starts_at: Time.utc(2000), ends_at: 1.day.from_now)
      # The NPS form asks nobody, so nps.exe stays shut and a ship needs no
      # answer. Tests of the form turn it on.
      NpsResponse.asking = false
    end
  end
end

# A real image of the given size, built with libvips.
require "vips"
def image_bytes(width, height, format: :png)
  image = Vips::Image.black(width, height, bands: 3) + [ 60, 110, 180 ]
  image.cast(:uchar).public_send(:"#{format}save_buffer")
end

class ActionDispatch::IntegrationTest
  def upload_screenshot(project, bytes = image_bytes(1280, 720), type = "image/png", replace: nil)
    file = Rack::Test::UploadedFile.new(StringIO.new(bytes), type, true, original_filename: "shot.png")
    post project_screenshots_path(project), params: { screenshot: file, replace: }.compact, headers: { "Accept" => "application/json" }
  end

  def log_in(kind)
    get dev_login_path(as: kind)
    User.find_by!(hca_id: "ident!dev-#{kind}")
  end
end

# Tests of the new site (NewSite). In them every development login signs in
# a user with the new site on, and signed-out visitors get the new site too.
# The gate itself has its own tests.
module NewSiteTests
  extend ActiveSupport::Concern
  KINDS = %w[participant newbie unverified admin froppii red].freeze

  included do
    setup do
      NewSite.for_visitors = true
      KINDS.each { NewSiteTests.dev_user(it) }
    end
    teardown { NewSite.for_visitors = true }
  end

  # The user the development login signs in as, made first with the new site
  # on. The login finds it, so it keeps the flag.
  def self.dev_user(kind)
    User.create!(hca_id: "ident!dev-#{kind}", email: "#{kind}@example.com", first_name: kind.capitalize, last_name: "Dev",
                 verification_status: kind == "unverified" ? "needs_submission" : "verified", ysws_eligible: kind != "unverified",
                 admin: kind.in?(%w[admin froppii]), new_site: true)
  end
end
