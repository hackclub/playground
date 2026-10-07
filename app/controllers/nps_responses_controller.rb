# nps.exe: the NPS form, on a page the desktop holds in a window. It opens
# there by itself every 12 hours (see NpsResponse), and its icon opens it
# any time. A sent answer closes the window with confetti, and the page
# behind it is a fresh form.
#
# The ship list asks the same questions as one of its steps, and sends the
# answer here marked with checks and the pet. It goes back to the list,
# which shows the step ticked, or still to do. On the new site the list in
# the guide sends from=guide, which goes back with it.
class NpsResponsesController < ApplicationController
  layout "app"
  before_action :require_login
  before_action :require_participant

  def show = @nps = NpsResponse.new

  def create
    project = current_user.projects.find(params[:project_id]) if params[:checks]
    @nps = NpsResponse.new(params.fetch(:nps_response, {}).permit(*NpsResponse::FIELDS)
                                 .merge(user: current_user, source: project ? "ship" : "daily", project:))
    saved = @nps.save
    if project
      flash[:nps_alert] = "pick a number and fill in the * ones first." unless saved
      redirect_to checks_project_path(project, from: params[:from].presence_in(%w[guide]), shown: params[:shown].presence), status: :see_other
    elsif saved
      redirect_to nps_path
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def require_participant
    redirect_to dashboard_path, alert: "only participants answer this" unless NpsResponse.participant?(current_user)
  end
end
