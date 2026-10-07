# Development only. Stands in for Hackatime's OAuth so the flow runs without
# OAuth apps: it links fake Hackatime, or with deny=1 fails the way a declined
# consent does. Both land where the real callback does. On the new site it
# also stands in for the heartbeats Godot sends, for the guide's live check.
class DevController < ApplicationController
  before_action { raise ActionController::RoutingError, "not found" unless FakeServices.on? }
  before_action :require_login

  def hackatime
    return redirect_to auth_failure_path(strategy: "hackatime", message: "access_denied") if params[:deny]
    current_user.update!(hackatime_access_token: "fake")
    back = guide_return(params[:origin]) if new_site?
    redirect_to back || root_path(open: "goal"), notice: "fake Hackatime linked"
  end

  # Stands in for Godot's Hackatime plugin: from now on, fake Hackatime lists
  # a project of this name, coding since this moment. Back to the guide step
  # that asked.
  def heartbeat
    require_new_site
    FakeHeartbeats.start(current_user, params[:name])
    redirect_to guide_check_path(frame: params[:frame])
  end
end
