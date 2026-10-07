# What ship.exe shows: the meter, goals, and the participant's pets. Signed
# out it has none of these, so it sends the visitor to the login. The new
# site (NewSite) has no dashboard: the meter, goals, and pets sit beside its
# guide, so the address goes there, and a message on the way stays.
class DashboardController < ApplicationController
  layout "app"

  def show
    return redirect_to(login_path) unless current_user
    return forward_to_guide if new_site?
    TrackedTime.refresh_all(current_user)
    @hours = current_user.hours
    @projects = current_user.projects.includes(:ships).order(updated_at: :desc)
    @redemptions = current_user.redemptions.index_by(&:goal_key)
  end

  private

  def forward_to_guide
    flash.keep
    redirect_to guide_path
  end
end
