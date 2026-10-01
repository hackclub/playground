class ProjectsController < ApplicationController
  layout "app"
  before_action :require_login
  before_action :set_project, only: %i[show edit update destroy checks trash ship]

  # The desktop's icons for the participant's pets, which it asks for again
  # after a page in one of its windows adds, renames, or deletes one.
  def index
    respond_to do |format|
      format.json { render json: current_user.projects.order(:id).map(&:desktop_icon) }
      format.html { redirect_to dashboard_path }
    end
  end

  def show = TrackedTime.refresh(@project)

  # A pet dragged into the desktop's trash: the delete popups, alone on a
  # clear page that the desktop lays over itself.
  def trash = render(layout: "popups")

  # The ship popup's list, and its own page when opened in a new tab.
  def checks
    TrackedTime.refresh(@project)
    render_checks
  end

  # A new pet starts with a name and a description. The Hackatime picker waits
  # for edit, so new never asks Hackatime for the list.
  def new = @project = current_user.projects.new

  def create
    @project = current_user.projects.new(project_params)
    if @project.save
      TrackedTime.refresh(@project, force: true)
      redirect_to @project
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit = load_hackatime

  # The ship popup saves one field at a time, marked with checks, and gets
  # its list back with that field's error, if any. The desktop renames a pet
  # in JSON, and hears back its icon, or the error the edit page would show.
  def update
    saved = @project.update(project_params)
    TrackedTime.refresh(@project, force: true) if saved
    if params[:checks]
      respond_to do |format|
        format.turbo_stream { render_checks(status: saved ? :ok : :unprocessable_entity) }
        format.html { saved ? redirect_to(checks_project_path(@project)) : render_checks(status: :unprocessable_entity) }
      end
    elsif request.format.json?
      if saved
        render json: @project.desktop_icon
      else
        render json: { error: @project.errors.full_messages.to_sentence }, status: :unprocessable_entity
      end
    elsif saved
      redirect_to @project
    else
      load_hackatime
      render :edit, status: :unprocessable_entity
    end
  end

  # The desktop's trash asks for JSON, and hears back only whether it worked.
  def destroy
    if @project.ships.any?
      respond_to do |format|
        format.html { redirect_to @project, alert: "a shipped pet cannot be deleted" }
        format.json { head :unprocessable_entity }
      end
      return
    end
    @project.destroy!
    respond_to do |format|
      format.html { redirect_to dashboard_path }
      format.json { head :no_content }
    end
  end

  # Ship re-checks on fresh data. When that finds a blocker, the popup shows
  # it above the list, and the list says how to fix it.
  def ship
    Shipper.ship!(@project)
    redirect_to @project, notice: "shipped! your hours are pending review."
  rescue Shipper::Blocked => e
    respond_to do |format|
      format.turbo_stream do
        @alert = "not yet: #{e.message}"
        TrackedTime.refresh(@project)
        render_checks(status: :unprocessable_entity)
      end
      format.html { redirect_to checks_project_path(@project), alert: "not yet: #{e.message}" }
    end
  end

  private

  def set_project = @project = current_user.projects.find(params[:id])

  # A failed save leaves the typed values and errors on @project for the
  # fields, and the checks judge what is saved. The picker's Hackatime list
  # loads before the checks run, so both go by the same answer from Hackatime.
  def render_checks(status: :ok)
    saved = @project.changed? ? current_user.projects.find(@project.id) : @project
    load_hackatime if saved.hackatime_projects.empty? || Array(params[:shown]).include?("hackatime_projects")
    @checklist = ShipChecklist.new(saved, shown: params[:shown])
    render :checks, status:
  end

  def project_params
    params.require(:project).permit(:name, :description, :code_url, :playable_url, :ship_message_url, hackatime_projects: [])
  end

  # The multi-select: every Hackatime project with time in the program window,
  # most recent heartbeat first, minus those the participant's other pets link
  # or shipped. A project this pet links stays, even with no time in the
  # window, so a save never drops it. It has no heartbeat, which the picker says.
  def load_hackatime
    @hackatime_projects = []
    return unless current_user.hackatime_connected?
    taken = @project.hackatime_projects_taken.map { Project.hackatime_key(it) }
    listed = Hackatime.for(current_user).projects.reject { taken.include?(Project.hackatime_key(it.name)) }
    kept = Array(@project.hackatime_projects_in_database).reject { taken.include?(Project.hackatime_key(it)) } - listed.map(&:name)
    @hackatime_projects = listed + kept.map { Hackatime::Project.new(name: it, total_seconds: 0, most_recent_heartbeat: nil) }
  rescue Hackatime::Unlinked
    current_user.hackatime_unlinked = true
  rescue HttpJson::Error => e
    @hackatime_error = e.message
  end
end
