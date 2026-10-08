# Building blocks (BuildingBlock): their cards in the guide's "Make it your
# own" step, and each block's page, drawn from its guide.md in the guide's
# look: its headings, its screenshots, and its code blocks.
module BuildingBlocksHelper
  # The languages a page's code block may name, each with the label on its
  # bar, as the guide's own code blocks have them.
  CODE_LANGUAGES = { "gdscript" => %w[gdscript GDScript], "gd" => %w[gdscript GDScript],
                     "shell" => %w[shell shell], "sh" => %w[shell shell], "bash" => %w[shell shell] }.freeze

  # A block's page, from the guide this reader came from: the new site's at
  # /guide/blocks/<slug>, or a side guide's, such as /clubs/blocks/<slug>.
  def building_block_page_path(block) = building_block_path(side_guide&.slug || "guide", block)

  # The guide's step that holds the blocks' cards, at their part, on the guide
  # this reader came from. A visitor to the old desktop has no guide in
  # steps, so they go to /guide.
  def building_blocks_guide_path
    return guide_path unless side_guide || new_site?
    "#{guide_step_path(GuidePage.holding("your-own"))}#your-own"
  end

  # Everything on a block's page under its title, which the page's header shows.
  def building_block_body(block)
    safe_join(block.page.parts.reject { it.kind == :h1 }.map { building_block_part(block, it) }, "\n")
  end

  private

  def building_block_part(block, part)
    case part.kind
    when :h2, :h3
      content_tag(part.kind, block_inline(block, part.text), id: block_anchor(part.text))
    when :p then tag.p(block_inline(block, part.text))
    when :ul, :ol then content_tag(part.kind, safe_join(part.text.map { tag.li(block_inline(block, it)) }))
    when :code then code_block(part.text, *CODE_LANGUAGES.fetch(part.extra, [ part.extra, part.extra ]))
    when :image then block_image(block, part.extra, part.text)
    end
  end

  # A picture on a line of its own. A screenshot shows at half its file's
  # size, as the guide's do, so it stays sharp on a screen with two pixels to
  # the point. The demo GIF shows full width.
  def block_image(block, path, alt)
    width, height = BuildingBlock::Page.image_size(block.folder.join(path))
    gif = path.end_with?(".gif")
    width, height = width / 2, height / 2 if width && !gif
    image_tag(block.asset(path), alt:, width:, height:, loading: (gif ? "eager" : "lazy"), decoding: "async",
                                 class: gif ? "block-result" : "guide-shot")
  end

  # A line's `code`, **bold**, and [links](to). A link to a file of the block,
  # such as images/result.mp4, goes to that file. Every link opens in a new
  # tab, as the guide's links out do.
  INLINE = /`([^`]+)`|\*\*(.+?)\*\*|\[((?:[^\]`]|`[^`]*`)+)\]\(([^)\s]+)\)/

  def block_inline(block, text)
    parts = []
    last = 0
    text.scan(INLINE) do
      match = Regexp.last_match
      parts << text[last...match.begin(0)]
      parts << if match[1] then tag.code(match[1])
      elsif match[2] then tag.strong(block_inline(block, match[2]))
      else
        link_to(block_inline(block, match[3]), block_href(block, match[4]), target: "_blank", rel: "noopener")
      end
      last = match.end(0)
    end
    parts << text[last..]
    safe_join(parts)
  end

  # A link out stays as it is. A path in the block's folder goes to that
  # file. Any other scheme, such as javascript:, links nowhere.
  def block_href(block, to)
    return to if to.match?(%r{\Ahttps?://}i)
    return "#" if to.match?(/\A[a-z][a-z0-9+.-]*:/i) || to.start_with?("/")
    asset_path(block.asset(to))
  end

  # A heading's anchor, from its words, as the guide's outline makes one.
  def block_anchor(text) = text.gsub(/`|\*\*/, "").downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
end
