# The guide to making a pet in Godot: a page of its own for anyone, and
# guide.txt's page on the desktop. A shared link to it unfurls as the guide.
#
# On the new site (NewSite) the guide is the hub, one step at a time
# (GuidePage), at /guide and /guide/<step>. Signed in, the next step and the
# meter sit beside it, and the guide's steps that act on the site sit inside it.
class GuidesController < ApplicationController
  layout "app"

  def show
    @link_preview = {
      title: "Build a virtual pet in Godot",
      description: "a step by step guide to your first desktop pet: a Godot sprite that walks your screen, rests, and lets you drag it around. from playground, a Hack Club program.",
      image: "guide-opengraph.png",
      image_width: 1200,
      image_height: 630,
      image_alt: "The Hack Club playground logo over a blue sky and a green hill, with the words: the guide, build a virtual pet in Godot."
    }
    show_hub if new_site?
  end

  private

  def show_hub
    @step = params[:step] ? GuidePage.find(params[:step]) : GuidePage.first
    raise ActionController::RoutingError, "no such step of the guide" unless @step
    @link_preview[:title] = "Build a desktop pet in Godot"
    @hub = Hub.new(current_user, active_pet_id) if current_user
    @pet = @hub&.pet
    @ship_pet = GuidePet.to_ship(current_user, active_pet_id) if current_user && @step == GuidePage.all.last
  end
end
