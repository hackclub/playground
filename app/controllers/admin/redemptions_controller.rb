module Admin
  class RedemptionsController < BaseController
    before_action :set_redemption
    before_action :no_store, only: %i[show reveal]
    before_action :refuse_own_redemption, only: :verdict

    def show
      @claim, took = Claim.acquire(@redemption, "fulfillment", current_user, force: params[:take].present?) if @redemption.status.in?(%w[pending on_hold])
      @held = @claim && !took
    end

    # The address stays hidden until an admin asks, and each reveal is logged.
    def reveal
      @address = @redemption.reveal_address!(by: current_user)
      @claim = Claim.find_by(claimable: @redemption, stage: "fulfillment")
      render :show
    end

    def verdict
      return redirect_to(admin_redemption_path(@redemption), alert: "someone else holds this") if Claim.held_by_other?(@redemption, "fulfillment", current_user)
      case params[:verdict]
      when "fulfill" then @redemption.fulfill!(by: current_user, tracking: params[:tracking], cost_cents: params[:cost].presence && (params[:cost].to_f * 100).round, notes: params[:notes])
      when "hold" then @redemption.hold!(by: current_user, notes: params[:notes])
      when "release"
        @redemption.release!(by: current_user)
        return redirect_to(admin_redemption_path(@redemption, flow: params[:flow]))
      when "reject" then @redemption.reject!(by: current_user, notes: params[:notes])
      else return head(:bad_request)
      end
      @redemption.claims.delete_all
      redirect_to flow? ? admin_person_path(@redemption.user) : admin_fulfillment_path, notice: "#{@redemption.goal.name}: #{@redemption.status.tr("_", " ")}"
    rescue ArgumentError => e
      redirect_to admin_redemption_path(@redemption, flow: params[:flow]), alert: e.message
    end

    private

    def set_redemption = @redemption = Redemption.find(params[:id])

    # The queue skips an admin's own redemptions, and a direct post can't
    # settle one.
    def refuse_own_redemption
      redirect_to admin_redemption_path(@redemption), alert: "someone else settles your own redemption" if @redemption.user_id == current_user.id
    end
  end
end
