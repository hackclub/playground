# A building block's page (BuildingBlock), which a card in the guide's
# "Make it your own" step opens in a new tab. It shows the same to everyone,
# signed in or not, with the new site or not, so a club's readers, who may
# have no account, can read it. It wears the side guides' layout, and its
# logo goes back to the guide the reader came from: /guide/blocks/<slug> is
# the new site's, and /stardance/blocks/<slug> or /clubs/blocks/<slug> a side
# guide's (SideGuide).
class BuildingBlocksController < ApplicationController
  layout "side_guide"

  def show
    @block = BuildingBlock.find(params[:block])
    raise ActionController::RoutingError, "no such building block" unless @block
    @side_guide = SideGuide.find(params[:guide])
    @link_preview = { title: "#{@block.title} · Build a desktop pet in Godot" }
  end
end
