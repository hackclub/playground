# The guide to making a pet in Godot: a page of its own for anyone, and
# guide.txt's page on the desktop. A shared link to it unfurls as the guide.
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
  end
end
