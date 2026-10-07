require "test_helper"

class ShipMailerTest < ActionMailer::TestCase
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(hca_id: "ident!mail-admin", email: "a@example.com", admin: true)
    @user = User.create!(hca_id: "ident!mail-#{SecureRandom.hex(3)}", email: "kid@example.com", verification_status: "verified", ysws_eligible: true)
    @project = @user.projects.create!(name: "rock")
    @ship = @project.ships.create!(user: @user, claimed_seconds: 7200)
    clear_enqueued_jobs
  end

  def approve(ship = @ship)
    ship.approve_review!(by: @admin, seconds: 5400, judgement: "ok", feedback: "Lovely.")
    ship.pass_fraud!(by: @admin)
  end

  def mail_jobs = enqueued_jobs.select { it["job_class"] == "ActionMailer::MailDeliveryJob" }

  test "the approved email has the fields and the placeholders" do
    approve
    mail = ShipMailer.approved(@ship.reload)
    assert_equal [ "kid@example.com" ], mail.to
    assert_includes mail.subject, "rock"
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, @ship.user.display_name
      assert_includes body, "rock"
      assert_includes body, "1h 30m"
      assert_includes body, "Lovely."
      assert_includes body, "http://example.com/projects/#{@project.id}"
      %w[greeting approved\ body sign-off].each { assert_includes body, "[[ARMAND: #{it}]]" }
    end
    assert_includes mail.subject, "[[ARMAND: approved subject]]"
  end

  test "the changes email has the feedback and the placeholders" do
    @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Add a screenshot.")
    mail = ShipMailer.changes_needed(@ship.reload)
    assert_includes mail.subject, "needs changes"
    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, "Add a screenshot."
      assert_includes body, "rock"
      assert_includes body, "[[ARMAND: changes body]]"
      assert_includes body, "[[ARMAND: sign-off]]"
    end
  end

  test "one email per transition, none on a re-save" do
    @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.")
    assert_equal 1, mail_jobs.size
    @ship.update!(review_feedback: "Fix it, please.")
    @ship.touch
    assert_equal 1, mail_jobs.size
    @ship.update!(state: "pending", review_status: "pending")
    assert_equal 1, mail_jobs.size
    approve
    assert_equal 2, mail_jobs.size
    @ship.update!(approved_seconds: 100)
    assert_equal 2, mail_jobs.size
  end

  test "the review approval alone sends nothing, the fraud pass sends the approval" do
    @ship.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil)
    assert_empty mail_jobs
    @ship.pass_fraud!(by: @admin)
    assert_equal 1, mail_jobs.size
  end

  test "a rejection and a ban send nothing" do
    @ship.reject_review!(by: @admin, judgement: "no", feedback: "Not a pet.")
    assert_empty mail_jobs
    other = @user.projects.create!(name: "owl").ships.create!(user: @user, claimed_seconds: 3600)
    other.approve_review!(by: @admin, seconds: 3600, judgement: "ok", feedback: nil)
    other.ban_for_fraud!(by: @admin, notes: "copied")
    assert_empty mail_jobs
  end

  test "with the SMTP login missing nothing is queued and nothing raises" do
    with_smtp do
      with_env("SMTP_USERNAME" => nil, "SMTP_PASSWORD" => nil) do
        refute ShipMailer.enabled?
        @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.")
      end
    end
    assert_empty mail_jobs
    assert @ship.reload.changes_needed?
  end

  test "with the SMTP login set but placeholder copy present nothing is queued" do
    with_smtp do
      with_env("SMTP_USERNAME" => "me@gmail.com", "SMTP_PASSWORD" => "pw") do
        assert ShipMailer.enabled?
        @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.")
      end
    end
    assert_empty mail_jobs
    assert @ship.reload.changes_needed?
  end

  test "with the SMTP login set and the copy written the email is queued" do
    written = ShipMailer.singleton_class
    written.alias_method :orig_copy_written?, :copy_written?
    written.define_method(:copy_written?) { |_| true }
    with_smtp do
      with_env("SMTP_USERNAME" => "me@gmail.com", "SMTP_PASSWORD" => "pw") do
        @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "Fix it.")
      end
    end
    assert_equal 1, mail_jobs.size
  ensure
    written.alias_method :copy_written?, :orig_copy_written?
    written.remove_method :orig_copy_written?
  end

  test "the from address is MAIL_FROM, else the SMTP username" do
    @ship.return_for_changes!(by: @admin, judgement: "no", feedback: "x")
    with_env("MAIL_FROM" => nil, "SMTP_USERNAME" => "me@gmail.com") do
      assert_equal [ "me@gmail.com" ], ShipMailer.changes_needed(@ship).from
    end
    with_env("MAIL_FROM" => "play@hackclub.com", "SMTP_USERNAME" => "me@gmail.com") do
      assert_equal [ "play@hackclub.com" ], ShipMailer.changes_needed(@ship).from
    end
  end

  private

  def with_smtp
    old = ActionMailer::Base.delivery_method
    ActionMailer::Base.delivery_method = :smtp
    yield
  ensure
    ActionMailer::Base.delivery_method = old
  end

  def with_env(vars)
    old = vars.keys.to_h { [ it, ENV[it] ] }
    vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end
