# A building block's page (BuildingBlock), which a card in the guide's
# "Make it your own" step opens in a new tab. It shows the same to everyone,
# signed in or not, with the new site or not, so a club's readers, who may
# have no account, can read it. It wears the layout of the guide it came
# from: /guide/blocks/<slug> the new site's, with its top bar and tabs, and
# /stardance/blocks/<slug> or /clubs/blocks/<slug> a side guide's (SideGuide),
# whose logo goes back to that guide.
class BuildingBlocksController < ApplicationController
  layout -> { @side_guide ? "side_guide" : "app" }
  # The new site's look for everyone, as the side guides have it.
  before_action { request.variant = :new_site }

  def show
    @block = BuildingBlock.find(params[:block])
    raise ActionController::RoutingError, "no such building block" unless @block
    @side_guide = SideGuide.find(params[:guide])
    @link_preview = { title: "#{@block.title} · Build a desktop pet in Godot" }
  end
end
