module Admin
  class HomeController < BaseController
    def show
      @counts = {
        review: Ship.awaiting_review.count,
        fraud: Ship.awaiting_fraud.count,
        fulfillment: Redemption.to_fulfill.count
      }
      @people = User.count
      @events = AuditEvent.includes(:actor).order(created_at: :desc).limit(25)
    end
  end
end
