require "test_helper"

# The hourly read of the playground mission's hours by stage, with the MCP
# swapped out: StardanceStages.fetch answers canned projects.
class StardanceHoursJobTest < ActiveSupport::TestCase
  H = 3600

  setup do
    @token = "sd_token"
    @projects = [
      StardanceStages::Entry.new(repo: "https://github.com/ann/orbit", tracked: 10 * H, ships: [ StardanceStages::ShipRow.new(status: "pending", shipped: 6 * H, paid: 6 * H) ]),
      StardanceStages::Entry.new(repo: "https://github.com/nova/comet", tracked: 5 * H,
                                 ships: [ StardanceStages::ShipRow.new(status: "approved", shipped: 3 * H, paid: 2 * H) ])
    ]
    @originals = [ [ StardanceMcp, :token, StardanceMcp.method(:token) ], [ StardanceStages, :fetch, StardanceStages.method(:fetch) ] ]
    test = self
    StardanceMcp.define_singleton_method(:token) { test.instance_variable_get(:@token) }
    StardanceStages.define_singleton_method(:fetch) do |*|
      raise test.instance_variable_get(:@error) if test.instance_variable_get(:@error)
      test.instance_variable_get(:@projects)
    end
  end

  teardown { @originals.each { |target, name, original| target.define_singleton_method(name, &original) } }

  def stored = StardanceHours.latest&.attributes&.slice(*%w[approved_seconds pending_seconds unshipped_seconds projects left_out_projects left_out_seconds])

  test "without a token it reads nothing and stores nothing" do
    @token = nil
    @error = RuntimeError.new("asked")
    StardanceHoursJob.perform_now
    assert_nil StardanceHours.latest
  end

  test "it keeps the totals in one row, replaced on each read" do
    StardanceHoursJob.perform_now
    assert_equal({ "approved_seconds" => 2 * H, "pending_seconds" => 6 * H, "unshipped_seconds" => 6 * H,
                   "projects" => 2, "left_out_projects" => 0, "left_out_seconds" => 0 }, stored)
    @projects = @projects.first(1)
    StardanceHoursJob.perform_now
    assert_equal 1, StardanceHours.count
    assert_equal 1, StardanceHours.latest.projects
  end

  test "a project that is also a pet counted here is left out" do
    ann = User.create!(hca_id: "ident!sd-hours-ann", email: "ann@example.com", display_name: "ann", display_name_source: "generated")
    ann.projects.create!(name: "orbit", hackatime_projects: [ "orbit" ], tracked_seconds: 8 * H, code_url: "https://github.com/Ann/orbit/")
    StardanceHoursJob.perform_now
    assert_equal({ "approved_seconds" => 2 * H, "pending_seconds" => 0, "unshipped_seconds" => 2 * H,
                   "projects" => 1, "left_out_projects" => 1, "left_out_seconds" => 10 * H }, stored)
  end

  test "a failed read keeps the last totals, and a rejected token logs one line" do
    StardanceHoursJob.perform_now
    before = StardanceHours.latest
    @error = StardanceMcp::Rejected.new(StardanceMcp::REJECTED, status: 401)
    assert_nothing_raised { StardanceHoursJob.perform_now }
    @error = StardanceMcp::Error.new("down")
    assert_nothing_raised { StardanceHoursJob.perform_now }
    assert_equal [ before ], StardanceHours.all.to_a
  end
end
