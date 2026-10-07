# Tells a participant what a reviewer decided about a ship. Gmail SMTP in
# production, set by SMTP_USERNAME and SMTP_PASSWORD.
class ShipMailer < ApplicationMailer
  # False when the SMTP login is missing, so nothing is sent.
  def self.enabled?
    return true unless ActionMailer::Base.delivery_method == :smtp
    ENV["SMTP_USERNAME"].present? && ENV["SMTP_PASSWORD"].present?
  end

  PLACEHOLDER = "[[ARMAND:"

  # True when the subject and both parts hold no unwritten copy.
  def self.copy_written?(message)
    [ message.subject, message.html_part&.body&.to_s, message.text_part&.body&.to_s ].none? { it.to_s.include?(PLACEHOLDER) }
  end

  # Queues the email for the ship's state. Never raises: a mail problem must
  # not undo a review.
  def self.notify(ship)
    unless enabled?
      Rails.logger.info("ShipMailer: SMTP_USERNAME or SMTP_PASSWORD is missing, no email for ship #{ship.id}")
      return
    end
    return if ship.user.email.blank?
    message = public_send(ship.state, ship)
    # Only a real send needs the copy. Development and test mail may carry placeholders.
    if ActionMailer::Base.delivery_method == :smtp && !copy_written?(message)
      Rails.logger.info("ShipMailer: the email copy is not written yet, no email for ship #{ship.id}")
      return
    end
    message.deliver_later
  rescue StandardError => e
    Rails.logger.error("ShipMailer: could not queue email for ship #{ship.id}: #{e.class}")
  end

  def approved(ship)
    prepare(ship)
    @hours = Hours.format(ship.approved_seconds.to_i)
    mail to: @ship.user.email, subject: "[[ARMAND: approved subject]] #{@pet_name} is approved"
  end

  def changes_needed(ship)
    prepare(ship)
    mail to: @ship.user.email, subject: "[[ARMAND: changes subject]] #{@pet_name} needs changes"
  end

  private

  def prepare(ship)
    @ship = ship
    @name = ship.user.display_name
    @pet_name = ship.project.name
    @feedback = ship.review_feedback
    @pet_url = project_url(ship.project)
  end
end
