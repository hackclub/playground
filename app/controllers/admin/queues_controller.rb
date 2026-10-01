# Rapid-fire mode: "next" is the oldest item nobody else holds, that this
# admin has not skipped this session, and that is not their own.
module Admin
  class QueuesController < BaseController
    def review = next_in(Ship.awaiting_review, "review") { admin_ship_path(it, stage: "review") }
    def fraud = next_in(Ship.awaiting_fraud, "fraud") { admin_ship_path(it, stage: "fraud") }
    def fulfillment = next_in(Redemption.to_fulfill, "fulfillment") { admin_redemption_path(it) }

    private

    def next_in(scope, stage)
      skipped(stage).clear if params[:reset]
      skipped(stage) << params[:skip].to_i if params[:skip].present?
      skipped(stage).uniq!
      held = Claim.live.where(stage: stage, claimable_type: scope.klass.name).where.not(user: current_user).select(:claimable_id)
      item = scope.where.not(id: held).where.not(id: skipped(stage)).where.not(user_id: current_user.id).first
      return redirect_to(yield(item)) if item

      @stage = stage
      @left = scope.count
      @skipped = skipped(stage).size
      render :empty
    end
  end
end
