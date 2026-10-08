# A building block: a short reference page about one Godot node or function
# a participant can add to their pet, such as a sound or a speech bubble. The
# guide's "Make it your own" step shows a card for each, in the order of ALL,
# with its demo GIF, and each card opens the block's own page in a new tab, at
# /guide/blocks/<slug> (BuildingBlocksController).
#
# Each block is a folder, app/assets/images/blocks/<slug>/, which holds its
# page, guide.md, and the pictures that page names, in images/. The page is
# written in a small part of Markdown, which BuildingBlock::Page turns into
# HTML. The pictures sit under app/assets, so each gets a digest in its name.
#
# To add a block, copy its folder in (guide.md, and images/ with only the
# files guide.md names, plus result.gif) and add a line to ALL, where its
# card should show.
class BuildingBlock < Data.define(:slug, :title, :gif)
  ROOT = Rails.root.join("app/assets/images/blocks")

  # The card shows the page's demo GIF unless a block names another, such as
  # a shorter loop made for the card.
  def initialize(slug:, title:, gif: "result.gif") = super

  ALL = [
    new(slug: "sound-effect", title: "Sound effect", gif: "result.gif"),
    new(slug: "save-and-load", title: "Save and load", gif: "result.gif"),
    new(slug: "click-the-pet", title: "Click the pet", gif: "result.gif"),
    new(slug: "speech-bubble", title: "Speech bubble", gif: "result.gif"),
    new(slug: "particles", title: "Particles", gif: "result.gif"),
    new(slug: "follow-the-mouse", title: "Follow the mouse", gif: "result.gif"),
    new(slug: "fall-to-the-taskbar", title: "Fall to the taskbar", gif: "result.gif")
  ].freeze

  def self.all = ALL
  def self.find(slug) = ALL.find { it.slug == slug.to_s }

  def to_param = slug
  def folder = ROOT.join(slug)

  # A file in the block's folder by the path its page gives, such as
  # images/result.gif, as the asset helpers name it.
  def asset(path) = "blocks/#{slug}/#{path}"

  # The card's GIF, as an asset, and its size in pixels.
  def gif_asset = asset("images/#{gif}")
  def gif_size = Page.image_size(folder.join("images", gif))

  def page = Page.new(folder.join("guide.md").read)
end
