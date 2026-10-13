require "net/http"

# The Slack DM a participant gets when a reviewer approves a ship, asks for
# changes, or rejects it. The copy is in config/locales/review_dm.en.yml.
# A participant with no Slack id gets nothing. A real send holding an
# unwritten [[ARMAND: ...]] slot is skipped and logged.
class ReviewDm
  STATES = %w[approved changes_needed rejected].freeze
  PLACEHOLDER = "[[ARMAND:"

  # Slack's rate limit, or no connection to Slack. Nothing was posted, so the
  # job tries again.
  class TryLater < StandardError; end

  # Connection errors raised before the request reaches Slack.
  NOT_SENT = [ SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Net::OpenTimeout ].freeze

  # Sends the DM for the state the ship moved into. Raises only TryLater. Any
  # other problem, such as missing_scope, invalid_auth, or user_not_found, is
  # logged and dropped, as a retry would fail the same way.
  def self.deliver(ship_id, state)
    ship = Ship.includes(:user, :project, :reviewer, :fraud_reviewer).find_by(id: ship_id)
    return unless ship && state.in?(STATES) && SlackDm.configured?
    slack_id = ship.user.slack_id
    if slack_id.blank?
      Rails.logger.info("review dm: no Slack id, no DM for ship #{ship.id}")
      return
    end
    message = text(ship, state)
    # Only a real send needs the copy. The Fake may carry placeholders.
    if !FakeServices.on? && message.include?(PLACEHOLDER)
      Rails.logger.info("review dm: the copy is not written yet, no DM for ship #{ship.id}")
      return
    end
    SlackDm.post(slack_id, message)
  rescue SlackDm::Error => e
    raise TryLater, e.message if e.message.in?(%w[ratelimited rate_limited])
    Rails.logger.warn("review dm failed for ship #{ship_id}: #{e.message.first(120)}")
  rescue HttpJson::Error => e
    raise TryLater, e.message.first(120) if e.status == 429
    Rails.logger.warn("review dm failed for ship #{ship_id}: #{e.message.first(120)}")
  rescue *NOT_SENT => e
    raise TryLater, "#{e.class}: #{e.message.first(120)}"
  rescue StandardError => e
    # A read timeout or a 5xx may come after Slack posted, so no retry.
    Rails.logger.warn("review dm failed for ship #{ship_id}: #{e.class}: #{e.message.first(120)}")
  end

  # Stands for a block that is absent. A line holding only it is dropped.
  ABSENT = "\u0000"

  # The message in Slack mrkdwn. Text from the participant and the reviewer
  # is escaped, so it can't make links or mentions.
  def self.text(ship, state)
    feedback = ship.review_feedback.to_s.strip
    quote = feedback.lines.map { "> #{escape(it.chomp)}" }.join("\n")
    reviewer = mention(reviewer(ship, state))
    I18n.t("review_dm.#{state}",
           name: escape(ship.user.display_name),
           pet: escape(ship.project.name),
           hours: Hours.format(ship.approved_seconds.to_i),
           reviewed_by: reviewer ? I18n.t("review_dm.reviewed_by", reviewer:) : ABSENT,
           feedback: feedback.empty? ? "" : I18n.t("review_dm.feedback", quote:),
           url: pet_url(ship.project))
      .gsub(/^#{ABSENT}\n?/, "").gsub(/\n{3,}/, "\n\n").strip
  end

  # Who decided. The reviewer, else the fraud reviewer. A rejection from a
  # fraud ban names no one. The ban still records its fraud reviewer for audit.
  def self.reviewer(ship, state)
    return if state == "rejected" && ship.fraud_status == "banned"
    ship.reviewer || ship.fraud_reviewer
  end

  # A Slack mention when the user has a Slack id, else their escaped name.
  def self.mention(user)
    return unless user
    user.slack_id.to_s.match?(/\A[A-Z0-9]+\z/) ? "<@#{user.slack_id}>" : escape(user.display_name)
  end

  # Slack's three control characters:
  # https://docs.slack.dev/messaging/formatting-message-text/#escaping
  def self.escape(text) = text.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")

  # The host is the mailer's, set per environment.
  def self.pet_url(project)
    Rails.application.routes.url_helpers.project_url(project, **Rails.application.config.action_mailer.default_url_options)
  end
  private_class_method :reviewer, :mention, :escape, :pet_url
end
