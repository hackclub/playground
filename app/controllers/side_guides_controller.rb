# The guide in steps for Stardance and for clubs (SideGuide), at /stardance
# and /clubs, with each step at its own address, such as /stardance/move. It
# shows the same to everyone: signed out, signed in, with the new site or
# without. It wears the new site's look in a layout of its own, which no flag
# gates, with a top bar of only the logo, back to this guide, and help.
#
# Opening one remembers it in a cookie, so / sends this browser back to it
# (LandingController). Opening the other one remembers that one instead.
class SideGuidesController < ApplicationController
  layout "side_guide"

  def show
    @side_guide = SideGuide.find(params[:guide])
    @step = params[:step] ? GuidePage.find(params[:step]) : GuidePage.first
    raise ActionController::RoutingError, "no such step of the guide" unless @side_guide && @step
    cookies.permanent[SideGuide::COOKIE] = { value: @side_guide.slug, httponly: true, same_site: :lax }
    @link_preview = {
      title: "Build a desktop pet in Godot",
      description: "a step by step guide to your first desktop pet: a Godot sprite that walks your screen, rests, and lets you drag it around. from playground, a Hack Club program.",
      image: "guide-opengraph.png",
      image_width: 1200,
      image_height: 630,
      image_alt: "The Hack Club playground logo over a blue sky and a green hill, with the words: the guide, build a virtual pet in Godot."
    }
  end
end
