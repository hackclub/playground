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
    ship.approve_review!(by: @admin, seconds: 5400, judgement: "ok", feedback:, deflation_reason: "idle")
    ship.pass_fraud!(by: @admin)
  end

  def dm_jobs = enqueued_jobs.select { it["job_class"] == "ReviewDmJob" }

  test "the approved DM greets, links the pet, quotes the feedback and names the reviewer" do
    perform_enqueued_jobs { approve }
    assert_equal 1, SlackDm::Fake.sent.size
    dm = SlackDm::Fake.sent.last
    assert_equal "U0KID", dm[:channel]
    assert_equal "Hey Pixel Fox!\n\nYour pet <http://example.com/projects/#{@project.id}|rock> has been approved!\n\nFeedback:\n> Lovely.\n- Ada &amp; Co", dm[:text]
  end

  test "changes needed and rejected each send their own DM" do
    perform_enqueued_jobs { @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Add a screenshot.") }
    other = @project.ships.create!(user: @user, claimed_seconds: 3600)
    perform_enqueued_jobs { other.reject_review!(by: @admin, judgement: "no", feedback: nil) }
    changes, rejected = SlackDm::Fake.sent.pluck(:text)
    url = "http://example.com/projects/#{@project.id}"
    assert_equal "Hey Pixel Fox!\n\nYour pet <#{url}|rock> has some feedback\n\nFeedback:\n> Add a screenshot.\n- Ada &amp; Co", changes
    assert_equal "Hey Pixel Fox!\n\nYour pet <#{url}|rock> has been rejected\n\n- Ada &amp; Co", rejected
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
    @ship.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil, deflation_reason: "idle")
    assert_empty dm_jobs
    @ship.pass_fraud!(by: @admin)
    assert_equal [ [ @ship.id, "approved" ] ], dm_jobs.map { it["arguments"] }
  end

  test "a ban rejects the ship and sends the rejection" do
    @ship.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil, deflation_reason: "idle")
    perform_enqueued_jobs { @ship.ban_for_fraud!(by: @admin, notes: "copied") }
    assert_equal 1, SlackDm::Fake.sent.size
    assert_includes SlackDm::Fake.sent.last[:text], "> This project was rejected."
  end

  test "a reviewer with a Slack id is mentioned" do
    @admin.update!(slack_id: "U0ADA")
    perform_enqueued_jobs { @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.") }
    assert SlackDm::Fake.sent.last[:text].end_with?("\n- <@U0ADA>")
  end

  test "a fraud ban names no one, on the banned ship and on each pending ship it rejects" do
    banner = User.create!(hca_id: "ident!dm-banner", email: "b@example.com", admin: true, slack_id: "U0BAN")
    other = @user.projects.create!(name: "owl").ships.create!(user: @user, claimed_seconds: 3600)
    @ship.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil, deflation_reason: "idle")
    perform_enqueued_jobs { @ship.ban_for_fraud!(by: banner, notes: "copied") }
    assert_equal banner, other.reload.fraud_reviewer
    texts = SlackDm::Fake.sent.pluck(:text)
    assert_equal 2, texts.size
    texts.each do
      assert_not_includes it, "\n- "
      assert_not_includes it, "U0BAN"
      assert_includes it, "has been rejected"
    end
  end

  test "with no reviewer on record the reviewed by line goes" do
    @ship.update_columns(state: "approved", approved_seconds: 3600, review_feedback: "Fine.")
    text = ReviewDm.text(@ship.reload, "approved")
    assert_equal "Hey Pixel Fox!\n\nYour pet <http://example.com/projects/#{@project.id}|rock> has been approved!\n\nFeedback:\n> Fine.", text
    assert_not_includes text, ReviewDm::ABSENT
  end

  test "with no feedback the DM has no Feedback line" do
    perform_enqueued_jobs { approve(feedback: nil) }
    assert_equal "Hey Pixel Fox!\n\nYour pet <http://example.com/projects/#{@project.id}|rock> has been approved!\n\n- Ada &amp; Co", SlackDm::Fake.sent.last[:text]
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
    assert_includes text, "|&lt;!channel&gt; &amp; co> has been approved!"
    assert_includes text, "> Nice &lt;@U123&gt;.\n> Also &gt; this."
  end

  test "a real send with a placeholder left posts nothing and logs" do
    posted = []
    with_methods(FakeServices, on?: -> { false }) do
      with_methods(ReviewDm, text: ->(*) { "Hey [[ARMAND: greeting]]" }) do
      with_methods(SlackDm, configured?: -> { true }, post: ->(*args) { posted << args }) do
        approve
        logs = capture_log { perform_enqueued_jobs }
        assert_includes logs, "the copy is not written yet"
      end
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
