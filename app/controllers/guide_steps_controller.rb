# The guide's Hackatime steps, each a frame inside the guide: link Hackatime
# where the plugin goes in, and, once the participant has coded, pick the
# pet's project from Hackatime's list, which asks Hackatime again while it
# waits. Picking a project makes the pet when there is none.
#
# The guide's pet is the one the participant set active, or with none, the
# newest pet that never shipped (GuidePet).
class GuideStepsController < ApplicationController
  # A Hackatime project codes now when its latest heartbeat is this recent.
  CODING_NOW = 10.minutes
  # The list shows this many projects, most recent first.
  LISTED = 8
  FRAMES = %w[hackatime-step pick-step].freeze

  before_action :require_new_site
  before_action :require_login, only: %i[link side ship]
  before_action { @frame = params[:frame].presence_in(FRAMES) || FRAMES.first }

  # What Hackatime sees: the pet's projects, and the others with time in the
  # program window that no other pet holds.
  def check
    @pet = current_user && GuidePet.for(current_user, active_pet_id)
    @just_set = flash[:active_pet_set]
    return unless current_user&.hackatime_connected?
    projects = free_projects
    @linked = @pet ? projects.select { linked?(it.name) } : []
    @others = projects.reject { @pet && linked?(it.name) }.first(LISTED)
    # Coding now, the least time first: a project just made in Godot has
    # little time yet, and the list suggests the first.
    @coding_now = @others.select { it.most_recent_heartbeat&.after?(CODING_NOW.ago) }.sort_by(&:total_seconds)
    @just_linked = flash[:guide_linked]
  rescue Hackatime::Unlinked
    current_user.hackatime_unlinked = true
  rescue HttpJson::Error => e
    @error = e.message
  end

  # The ship step with its pet's ship list, after the guide's page loads, and
  # again after a step above it is done.
  def ship
    @ship_pet = @project = GuidePet.to_ship(current_user, active_pet_id)
    @just_set = flash[:active_pet_set]
    if @project
      TrackedTime.refresh(@project)
      @checklist = ShipChecklist.new(@project)
    end
    render partial: "guide_steps/ship_step"
  end

  # A part beside the guide, again, after a step is done: the next step, or
  # the hours.
  def side
    @hub = Hub.new(current_user, active_pet_id)
    @just_set = flash[:active_pet_set]
    render partial: "guides/side_frame", locals: { part: params[:part].presence_in(%w[next side]) || "side" }
  end

  # The participant picks a project from the list. Only a name Hackatime
  # lists for them, and no other pet holds, can be picked. With no pet yet,
  # the pick makes one. A pet takes the name of its first project, and a
  # second, such as the folder's name, leaves the name alone. A pet the pick
  # makes becomes the active pet.
  def link
    @pet = GuidePet.for(current_user, active_pet_id)
    name = free_projects.map(&:name).find { it == params[:name] }
    if name
      @pet ||= current_user.projects.new
      @pet.name = name.first(80) if @pet.hackatime_projects.empty?
      @pet.hackatime_projects = @pet.hackatime_projects + [ name ]
      made = @pet.new_record?
      if @pet.save
        remember_active_pet(@pet) if made
        TrackedTime.refresh(@pet, force: true)
        flash[:guide_linked] = true
      end
    end
    redirect_to guide_check_path(frame: @frame)
  rescue HttpJson::Error
    redirect_to guide_check_path(frame: @frame)
  end

  private

  # Hackatime's projects with time in the window, minus those the
  # participant's other pets link or shipped.
  def free_projects
    taken = (@pet || current_user.projects.new).hackatime_projects_taken.map { Project.hackatime_key(it) }
    Hackatime.for(current_user).projects.reject { taken.include?(Project.hackatime_key(it.name)) }
  end

  def linked?(name) = @pet.hackatime_projects.any? { Project.hackatime_key(it) == Project.hackatime_key(name) }
end
