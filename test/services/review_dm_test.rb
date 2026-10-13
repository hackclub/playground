require "test_helper"

# The Slack DM on each review outcome, with the fake Slack standing in.
class ReviewDmTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    SlackDm::Fake.reset!
    @admin = User.create!(hca_id: "ident!dm-admin", email: "a@example.com", admin: true, display_name: "Ada & Co")
    @user = User.create!(hca_id: "ident!dm-#{SecureRandom.hex(3)}", email: "kid@example.com", slack_id: "U0KID", display_name: "Pixel Fox",
                         verification_status: "verified", ysws_eligible: true)
    @project = @user.projects.create!(name: "rock")
    @ship = @project.ships.create!(user: @user, claimed_seconds: 7200)
    clear_enqueued_jobs
  end

  teardown { SlackDm::Fake.reset! }

  def approve(ship = @ship, feedback: "Lovely.")
    ship.approve_review!(by: @admin, seconds: 5400, judgement: "ok", feedback:)
    ship.pass_fraud!(by: @admin)
  end

  def dm_jobs = enqueued_jobs.select { it["job_class"] == "ReviewDmJob" }

  test "the approved DM has the facts and the placeholders" do
    perform_enqueued_jobs { approve }
    assert_equal 1, SlackDm::Fake.sent.size
    dm = SlackDm::Fake.sent.last
    assert_equal "U0KID", dm[:channel]
    text = dm[:text]
    assert_includes text, "[[ARMAND: greeting]] Pixel Fox"
    assert_includes text, "*Pet:* rock\n*[[ARMAND: reviewed by label]]* Ada &amp; Co\n*Approved hours:* 1h 30m"
    assert_includes text, "> Lovely."
    assert_includes text, "<http://example.com/projects/#{@project.id}|"
    [ "greeting", "approved body", "reviewed by label", "feedback heading", "link text", "sign-off" ].each { assert_includes text, "[[ARMAND: #{it}]]" }
  end

  test "changes needed and rejected each send their own DM" do
    perform_enqueued_jobs { @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Add a screenshot.") }
    other = @project.ships.create!(user: @user, claimed_seconds: 3600)
    perform_enqueued_jobs { other.reject_review!(by: @admin, judgement: "no", feedback: nil) }
    changes, rejected = SlackDm::Fake.sent.pluck(:text)
    assert_includes changes, "[[ARMAND: changes body]]"
    assert_includes changes, "> Add a screenshot."
    assert_includes rejected, "[[ARMAND: rejected body]]"
    assert_not_includes rejected, "feedback heading"
    assert_not_includes rejected, "Approved hours"
    assert_no_match(/\n{3,}/, rejected)
  end

  test "one DM per transition, none on a re-save or a move back to pending" do
    @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.")
    assert_equal 1, dm_jobs.size
    @ship.update!(review_feedback: "Fix it, please.")
    @ship.touch
    @ship.update!(state: "pending", review_status: "pending")
    assert_equal 1, dm_jobs.size
    approve
    assert_equal 2, dm_jobs.size
    @ship.update!(approved_seconds: 100)
    assert_equal 2, dm_jobs.size
  end

  test "the review approval alone sends nothing, the fraud pass sends the approval" do
    @ship.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil)
    assert_empty dm_jobs
    @ship.pass_fraud!(by: @admin)
    assert_equal [ [ @ship.id, "approved" ] ], dm_jobs.map { it["arguments"] }
  end

  test "a ban rejects the ship and sends the rejection" do
    @ship.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil)
    perform_enqueued_jobs { @ship.ban_for_fraud!(by: @admin, notes: "copied") }
    assert_equal 1, SlackDm::Fake.sent.size
    assert_includes SlackDm::Fake.sent.last[:text], "> This project was rejected."
  end

  test "a reviewer with a Slack id is mentioned" do
    @admin.update!(slack_id: "U0ADA")
    perform_enqueued_jobs { @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.") }
    assert_includes SlackDm::Fake.sent.last[:text], "*[[ARMAND: reviewed by label]]* <@U0ADA>"
  end

  test "a fraud ban names the banner, on the banned ship and on each pending ship it rejects" do
    banner = User.create!(hca_id: "ident!dm-banner", email: "b@example.com", admin: true, slack_id: "U0BAN")
    other = @user.projects.create!(name: "owl").ships.create!(user: @user, claimed_seconds: 3600)
    @ship.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil)
    perform_enqueued_jobs { @ship.ban_for_fraud!(by: banner, notes: "copied") }
    assert_equal banner, other.reload.fraud_reviewer
    texts = SlackDm::Fake.sent.pluck(:text)
    assert_equal 2, texts.size
    texts.each { assert_includes it, "*[[ARMAND: reviewed by label]]* <@U0BAN>" }
  end

  test "with no reviewer on record the reviewed by line goes" do
    @ship.update_columns(state: "approved", approved_seconds: 3600)
    text = ReviewDm.text(@ship.reload, "approved")
    assert_includes text, "*Pet:* rock\n*Approved hours:* 1h 0m"
    assert_not_includes text, "reviewed by"
    assert_not_includes text, ReviewDm::ABSENT
    assert_no_match(/\n{3,}/, ReviewDm.text(@ship, "rejected"))
  end

  test "a participant with no Slack id gets nothing" do
    @user.update!(slack_id: nil)
    perform_enqueued_jobs { approve }
    assert_empty SlackDm::Fake.sent
  end

  test "text from the participant and the reviewer is escaped and quoted line by line" do
    @project.update!(name: "<!channel> & co")
    perform_enqueued_jobs { approve(feedback: "Nice <@U123>.\nAlso > this.") }
    text = SlackDm::Fake.sent.last[:text]
    assert_includes text, "*Pet:* &lt;!channel&gt; &amp; co"
    assert_includes text, "> Nice &lt;@U123&gt;.\n> Also &gt; this."
  end

  test "a real send with a placeholder left posts nothing and logs" do
    posted = []
    with_methods(FakeServices, on?: -> { false }) do
      with_methods(SlackDm, configured?: -> { true }, post: ->(*args) { posted << args }) do
        approve
        logs = capture_log { perform_enqueued_jobs }
        assert_includes logs, "the copy is not written yet"
      end
    end
    assert_empty posted
  end

  test "a real send with the copy written posts to the Slack id" do
    posted = []
    with_methods(FakeServices, on?: -> { false }) do
      with_methods(ReviewDm, text: ->(*) { "Your pet is approved." }) do
        with_methods(SlackDm, configured?: -> { true }, post: ->(*args) { posted << args }) do
          perform_enqueued_jobs { approve }
        end
      end
    end
    assert_equal [ [ "U0KID", "Your pet is approved." ] ], posted
  end

  test "a Slack error such as missing_scope is logged, and the review stands" do
    with_methods(SlackDm, post: ->(*) { raise SlackDm::Error, "missing_scope" }) do
      logs = capture_log { perform_enqueued_jobs { @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.") } }
      assert_includes logs, "missing_scope"
    end
    assert @ship.reload.changes_needed?
  end

  test "Slack's rate limit and a refused connection try again later" do
    [ HttpJson::Error.new("429", status: 429), SlackDm::Error.new("ratelimited"), Errno::ECONNREFUSED.new ].each do |error|
      with_methods(SlackDm, post: ->(*) { raise error }) do
        assert_raises(ReviewDm::TryLater) { ReviewDm.deliver(@ship.id, "rejected") }
      end
    end
  end

  test "a 5xx or a read timeout is logged, not tried again, since Slack may have posted" do
    [ HttpJson::Error.new("500", status: 500), Net::ReadTimeout.new ].each do |error|
      with_methods(SlackDm, post: ->(*) { raise error }) do
        assert_nothing_raised { ReviewDm.deliver(@ship.id, "rejected") }
      end
    end
  end

  test "a failure to queue the DM does not undo the review" do
    with_methods(ReviewDmJob, perform_later: ->(*) { raise ActiveRecord::ConnectionNotEstablished }) do
      @ship.reject_review!(by: @admin, judgement: "no", feedback: "Not a pet.")
    end
    assert @ship.reload.rejected?
  end

  private

  # Swaps singleton methods for the block, and puts them back.
  def with_methods(target, replacements)
    originals = replacements.keys.to_h { [ it, target.method(it) ] }
    replacements.each { |name, body| target.define_singleton_method(name, &body) }
    yield
  ensure
    originals.each { |name, original| target.define_singleton_method(name, &original) }
  end

  def capture_log
    io = StringIO.new
    old = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = old
  end
end
