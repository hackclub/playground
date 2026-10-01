# What ship.exe shows: the meter, goals, and the participant's pets. Signed
# out it has none of these, so it sends the visitor to the login.
class DashboardController < ApplicationController
  layout "app"

  def show
    return redirect_to(login_path) unless current_user
    TrackedTime.refresh_all(current_user)
    @hours = current_user.hours
    @projects = current_user.projects.includes(:ships).order(updated_at: :desc)
    @redemptions = current_user.redemptions.index_by(&:goal_key)
  end
end
