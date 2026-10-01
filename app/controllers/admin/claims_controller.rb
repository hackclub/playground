module Admin
  class ClaimsController < BaseController
    TYPES = { "Ship" => Ship, "Redemption" => Redemption }.freeze

    # The page calls this every 30 seconds. force takes over a live claim.
    def heartbeat
      item = TYPES.fetch(params[:type]).find(params[:id])
      claim, took = Claim.acquire(item, params[:stage], current_user, force: params[:force].present?)
      render json: { ok: took, holder: claim.user.display_name }
    end
  end
end
