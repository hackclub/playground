# Open /rails/mailers/ship_mailer in development.
class ShipMailerPreview < ActionMailer::Preview
  def approved = ShipMailer.approved(sample_ship(state: "approved", approved_seconds: 9000, review_feedback: "Nice work on the animations."))

  def changes_needed = ShipMailer.changes_needed(sample_ship(state: "changes_needed", review_feedback: "The README needs a screenshot.\nAlso add install steps."))

  private

  def sample_ship(attrs)
    user = User.new(id: 0, display_name: "Pixel Fox", email: "pixel@example.com")
    project = Project.new(id: 1, name: "Rock Pet", user:)
    Ship.new(attrs.merge(id: 1, user:, project:))
  end
end
