# A building block's page, read from its guide.md, as a list of parts in
# order, for BuildingBlocksHelper to draw. It reads only the Markdown the
# pages use: a # title, ## and ### headings, paragraphs, a picture on a line
# of its own, - and 1. lists, and ``` code blocks with their language. Inside
# a line it reads `code`, **bold**, and [links](to). Anything else stays as
# written, as text.
class BuildingBlock::Page
  Part = Data.define(:kind, :text, :extra)

  HEADING = /\A(\#{1,3})\s+(.+)\z/
  IMAGE = /\A!\[([^\]]*)\]\(([^)\s]+)\)\z/
  FENCE = /\A```\s*([\w-]*)\s*\z/
  BULLET = /\A[-*]\s+(.+)\z/
  NUMBERED = /\A\d+\.\s+(.+)\z/

  attr_reader :parts

  def initialize(markdown)
    @parts = parse(markdown.to_s.gsub("\r\n", "\n").split("\n"))
  end

  # The page's # title.
  def title = parts.find { it.kind == :h1 }&.text

  # The alt text the page gives a picture, by its path, such as images/result.gif.
  def alt_for(path) = parts.find { it.kind == :image && it.extra == path }&.text

  # A PNG's or a GIF's size in pixels, from its header, or nil for another file.
  def self.image_size(path)
    head = File.binread(path, 24) || ""
    if head.start_with?("\x89PNG".b) then head.byteslice(16, 8).unpack("NN")
    elsif head.start_with?("GIF8") then head.byteslice(6, 4).unpack("vv")
    end
  rescue Errno::ENOENT
    nil
  end

  private

  def parse(lines)
    parts = []
    paragraph = []
    flush = -> { parts << Part.new(:p, paragraph.join(" "), nil) if paragraph.any?; paragraph = [] }
    i = 0
    while i < lines.size
      line = lines[i]
      stripped = line.strip
      if (fence = stripped.match(FENCE))
        flush.()
        code = []
        i += 1
        while i < lines.size && !lines[i].strip.match?(/\A```\s*\z/)
          code << lines[i]
          i += 1
        end
        parts << Part.new(:code, code.join("\n"), fence[1].presence || "text")
      elsif stripped.empty?
        flush.()
      elsif (heading = stripped.match(HEADING))
        flush.()
        parts << Part.new(:"h#{heading[1].size}", heading[2], nil)
      elsif (image = stripped.match(IMAGE))
        flush.()
        parts << Part.new(:image, image[1], image[2])
      elsif (item = stripped.match(BULLET) || stripped.match(NUMBERED))
        flush.()
        kind = stripped.match?(BULLET) ? :ul : :ol
        if parts.last&.kind == kind && lines[i - 1].strip.present?
          parts.last.text << item[1]
        else
          parts << Part.new(kind, [ item[1] ], nil)
        end
      else
        paragraph << stripped
      end
      i += 1
    end
    flush.()
    parts
  end
end
