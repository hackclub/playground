# The guide's code blocks, screen recordings, and screenshots. Every file
# they name sits under app/assets, so each gets a digest in its name.
module GuideHelper
  SNIPPETS = Rails.root.join("app/views/guides/snippets")
  LANGUAGES = { ".gd" => %w[gdscript GDScript], ".sh" => %w[shell shell] }.freeze

  # GDScript's words by kind, for a light highlight in the site's colours.
  GDSCRIPT = /(?<comment>#.*)|(?<string>"[^"]*")|(?<keyword>@\w+|\b(?:extends|var|func|if|elif|else|or|and|not|is|return|pass|true|false)\b)|(?<number>\b\d+(?:\.\d+)?\b)|(?<node>\$\w+)/

  # Each recording's size in pixels, and whether a smaller AV1 copy of it
  # exists. A copy that saved less than a tenth was left out.
  VIDEOS = {
    "new-project" => [ 1200, 1040, true ],
    "install-wakatime" => [ 1280, 882, true ],
    "github-repo" => [ 1280, 1042, false ],
    "2d-scene" => [ 1280, 788, true ],
    "add-node" => [ 1280, 834, true ],
    "collision-child" => [ 606, 550, true ],
    "import-sprites" => [ 1280, 458, true ],
    "sprite-frames" => [ 940, 1000, true ],
    "sprite-sheet" => [ 1280, 1052, true ],
    "play-animation" => [ 1280, 938, true ],
    "collision-shape" => [ 1280, 522, false ],
    "attach-script" => [ 1280, 714, true ],
    "clear-script" => [ 1280, 750, true ],
    "install-templates" => [ 1280, 1044, false ],
    "itch-upload" => [ 1280, 938, true ]
  }.freeze

  # Each screenshot's size in pixels. It shows at half that, so it stays
  # sharp on a screen with two pixels to the point.
  SHOTS = {
    "finder-show-path-bar" => [ 814, 1024 ],
    "finder-open-in-terminal" => [ 1360, 920 ],
    "explorer-open-in-terminal" => [ 1360, 979 ],
    "scene-tree" => [ 570, 984 ],
    "project-settings-menu" => [ 950, 647 ],
    "window-settings" => [ 1360, 871 ],
    "transparent-background" => [ 1360, 871 ],
    "per-pixel-transparency" => [ 1360, 871 ],
    "save-and-restart" => [ 1360, 58 ],
    "animated-sprite-selected" => [ 556, 208 ],
    "walk-animation" => [ 590, 332 ],
    "embedded-game" => [ 1360, 820 ],
    "embed-game-off" => [ 1360, 318 ],
    "export-templates" => [ 1024, 601 ],
    "installed-templates" => [ 1360, 333 ],
    "export-button" => [ 1024, 601 ],
    "add-windows" => [ 670, 712 ],
    "embed-pck" => [ 1360, 876 ],
    "export-project-1" => [ 362, 128 ],
    "export-project-2" => [ 1036, 130 ],
    "itch-new-project" => [ 370, 162 ],
    "itch-fill-out" => [ 1360, 987 ],
    "itch-visibility" => [ 1096, 326 ]
  }.freeze

  # Each shortcut the guide names, for each computer, as Godot's editor has
  # it: Save Scene, and Play, which is F5 off a Mac. A Mac's keys have their
  # names for a screen reader, which may not read the symbol.
  KEYS = {
    save: { "macos" => [ "⌘S", "Command S" ], "windows linux" => [ "Ctrl+S" ] },
    play: { "macos" => [ "⌘B", "Command B" ], "windows linux" => [ "F5" ] }
  }.freeze
  SYSTEMS = { "macos" => "macOS", "windows" => "Windows", "linux" => "Linux", "windows linux" => "Windows and Linux" }.freeze

  # A shortcut, each computer's keys labelled with it. os_controller.js shows
  # only the reader's, without its label.
  def guide_keys(action)
    variants = KEYS.fetch(action).map do |systems, (keys, spoken)|
      shown = spoken ? tag.span(keys, "aria-hidden": true) + tag.span(spoken, class: "visually-hidden") : keys
      tag.span(tag.kbd(shown) + tag.span(" on #{SYSTEMS.fetch(systems)}", class: "os-label"), data: { os: systems })
    end
    tag.span(safe_join(variants, tag.span(" or ", class: "os-label")), class: "os-keys")
  end

  # One snippet from app/views/guides/snippets as a code block. A shell block
  # has a copy button, since its commands are only to run. A GDScript block has
  # none, and its text can't be selected, so the reader types the pet's code
  # out. A line that starts with ~ is only there to show where the rest goes,
  # as the lines around a selection do in a screenshot of the editor: it shows
  # faded, and the copy button leaves it out.
  def guide_code(name)
    path = SNIPPETS.glob("#{name}.*").first
    language, label = LANGUAGES.fetch(path.extname)
    lines = path.read.chomp.split("\n", -1).map do |line|
      context = line.start_with?("~")
      tag.span(highlight_code(line.delete_prefix("~"), language), class: [ "line", ("context" if context) ])
    end
    copyable = language == "shell"
    tag.div(class: [ "code-block", ("no-copy" unless copyable) ], data: { controller: ("code-block" if copyable) }) do
      tag.div(class: "code-bar") do
        tag.span(label, class: "code-lang") +
          (copyable ? tag.button("copy", type: "button", class: "code-copy", "aria-label": "copy the #{label}", hidden: true,
                                         data: { action: "code-block#copy", code_block_target: "button" }) : "".html_safe)
      end +
        tag.pre(tag.code(safe_join(lines, "\n"), class: "language-#{language}", data: { code_block_target: "code" }))
    end
  end

  # A screen recording as a silent loop, with its poster, the frame it opens
  # on, until it plays. guide_video_controller.js plays it while it shows.
  def guide_video(slug, label)
    width, height, av1 = VIDEOS.fetch(slug)
    sources = []
    sources << tag.source(src: video_path("guide/#{slug}.webm"), type: 'video/webm; codecs="av01.0.08M.08"') if av1
    sources << tag.source(src: video_path("guide/#{slug}.mp4"), type: "video/mp4")
    tag.figure(class: "guide-video", data: { controller: "guide-video" }) do
      tag.video(safe_join(sources), muted: true, loop: true, playsinline: true, preload: "none",
                                    poster: image_path("guide/#{slug}-poster.webp"), width: width / 2, height: height / 2,
                                    "aria-label": label, data: { guide_video_target: "video" }) +
        tag.button("pause", type: "button", class: "video-toggle", "aria-label": "pause the recording", hidden: true,
                            data: { action: "guide-video#toggle", guide_video_target: "toggle" })
    end
  end

  def guide_shot(name, alt)
    width, height = SHOTS.fetch(name)
    image_tag("guide/#{name}.webp", alt:, width: width / 2, height: height / 2, loading: "lazy", decoding: "async", class: "guide-shot")
  end

  private

  def highlight_code(text, language)
    return text unless language == "gdscript"
    parts = []
    last = 0
    text.scan(GDSCRIPT) do
      match = Regexp.last_match
      parts << text[last...match.begin(0)]
      parts << tag.span(match[0], class: "tok-#{match.names.find { match[it] }}")
      last = match.end(0)
    end
    parts << text[last..]
    safe_join(parts)
  end
end
