# The participant sets their active pet, the one the guide's pet steps and
# the next step card act on, from the switch in each of them
# (active_pets/_switch). Asked from inside one of the guide's frames, it
# goes back to that frame, which then tells the others to ask again. Without
# scripts, it goes back to the page at that part. From my pets, it goes back
# to the pet's card there.
class ActivePetsController < ApplicationController
  before_action :require_new_site
  before_action :require_login

  def update
    pet = current_user.projects.find(params[:pet_id])
    remember_active_pet(pet)
    if (frame = frame_path(request.headers["Turbo-Frame"]))
      flash[:active_pet_set] = true
      redirect_to frame
    elsif params[:from] == "pets"
      redirect_to helpers.pet_card_path(pet)
    else
      redirect_to guide_return(params[:origin]) || guide_path
    end
  end

  private

  # Each frame the switch sits in, and the address it loads from.
  def frame_path(frame)
    case frame
    when "pick-step" then guide_check_path(frame:)
    when "ship-step" then guide_ship_path
    when "hub-next" then guide_side_path(part: "next")
    end
  end
end
