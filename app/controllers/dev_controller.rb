# Development only. Stands in for Hackatime's OAuth so the flow runs without
# OAuth apps: it links fake Hackatime, or with deny=1 fails the way a declined
# consent does. Both land where the real callback does.
class DevController < ApplicationController
  before_action { raise ActionController::RoutingError, "not found" unless FakeServices.on? }
  before_action :require_login

  def hackatime
    return redirect_to auth_failure_path(strategy: "hackatime", message: "access_denied") if params[:deny]
    current_user.update!(hackatime_access_token: "fake")
    redirect_to root_path(open: "goal"), notice: "fake Hackatime linked"
  end
end
