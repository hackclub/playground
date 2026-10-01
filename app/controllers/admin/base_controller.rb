# The admin page for program organizers. The participant is the unit of work: a person page runs every stage for one
# participant, and the queues run one stage across everyone.
module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :require_admin

    helper_method :flow?

    private

    # One-shot mode: verdicts return to the person page instead of the queue.
    def flow? = params[:flow].present?

    def skipped(stage) = (session[:skipped] ||= {})[stage] ||= []
  end
end
