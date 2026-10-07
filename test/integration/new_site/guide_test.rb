require "test_helper"

# The guide to making a pet in Godot, in steps, each a page of its own at
# its own address: every section with its recordings, screenshots, and code,
# each file served, the buttons to the step before and after, and a link to
# it that unfurls as the guide.
class NewSiteGuideTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  STEPS = {
    "setup-godot" => "Set up Godot",
    "hackatime" => "Install Godot Hackatime, and set up Hackatime on your machine",
    "github" => "Make a GitHub Repository",
    "sync" => "Sync your Godot project with the GitHub repo you just made",
    "commands" => "Important commands",
    "start" => "Finally, we’re set up! Let's start making the pet",
    "transparent" => "Let's make the scene transparent!",
    "pretty" => "Making it pretty!",
    "script" => "Yay! The scene is set up, now we can add the functionality",
    "movement" => "Movement",
    "pick-project" => "Pick your pet's project",
    "on-screen" => "Keep it on screen",
    "bounce" => "Bounce off the edges",
    "animations" => "Animations",
    "break" => "Let it take a break",
    "drag" => "Pick it up and drag it around",
    "your-own" => "Make it your own!",
    "publish" => "Export your pet and put it on itch.io"
  }.freeze
  SNIPPETS = Rails.root.join("app/views/guides/snippets")
  # Each step's sections, in order: the anchor of each h2.
  SECTIONS = {
    "setup" => %w[sign-in-title setup-godot github sync commands],
    "scene" => %w[start transparent pick-project],
    "art" => %w[pretty script],
    "move" => %w[movement on-screen bounce],
    "animate" => %w[animations break drag],
    "publish" => %w[your-own publish ship]
  }.freeze
  NAMES = [ "Set up", "Build the scene", "Art and script", "Make it move", "Animate and drag", "Publish and ship" ].freeze
  # The scene's transparency settings in order, each screenshot beside its
  # step: the Advanced Settings toggle first, so every setting shows, then
  # the Window tab's settings, Per Pixel Transparency with them, then
  # Rendering's.
  SCENE_SETTINGS = [ "Click Project > Project Settings…", "project-settings-menu", "make sure the Advanced Settings toggle",
                     "under the Window tab", "set Viewport Width", "make sure", "are on", "window-settings",
                     "Then search for Per Pixel", "per-pixel-transparency", "once you’ve done that search for Rendering",
                     "transparent-background", "You’ll see a pop up", "save-and-restart" ].freeze

  test "the guide shows every section on its step, with its recordings, screenshots, and code" do
    seen = []
    all_steps do |step|
      assert_select "h1", "Build a desktop pet in Godot"
      assert_equal SECTIONS.fetch(step.slug), css_select(".guide-step h2").map { it["id"] }, step.slug
      STEPS.each { |id, title| assert_select "##{id}", title if step.anchors.include?(id) }
      seen.concat(css_select(".guide-step h2, .guide-step h3").filter_map { it["id"] })
    end
    assert_empty STEPS.keys - seen, "every section is on a step"

    videos = all_steps { css_select("video") }.flatten(1)
    assert_equal GuideHelper::VIDEOS.size, videos.size
    GuideHelper::VIDEOS.each do |slug, (width, height, av1)|
      video = videos.select { it.matches?("video[muted][loop][playsinline][preload=none][width='#{width / 2}'][height='#{height / 2}'][poster*='/guide/#{slug}-poster-']") }
      assert_equal 1, video.size, slug
      assert video.first["aria-label"].start_with?("Screen recording: "), slug
      types = css_select(video.first, "source").map { it["type"] }
      assert_equal [ ('video/webm; codecs="av01.0.08M.08"' if av1), "video/mp4" ].compact, types, "the smaller copy goes first, for #{slug}"
    end
    # A click on the recording itself pauses or plays it. It has no button.
    assert_equal GuideHelper::VIDEOS.size, all_steps { css_select(".guide-video video[role=button][tabindex='0'][data-action*='video-click#toggle']").size }.sum
    assert_equal 0, all_steps { css_select(".guide-video button").size }.sum

    shots = all_steps { css_select("img.guide-shot") }.flatten(1)
    assert_equal NewSiteHelper::STEP_SHOTS.size, shots.size
    NewSiteHelper::STEP_SHOTS.each do |name, (width, height)|
      image = shots.select { it.matches?("img.guide-shot[src*='/guide/#{name}-'][width='#{width / 2}'][height='#{height / 2}'][loading=lazy]") }
      assert_equal 1, image.size, name
      assert_operator image.first["alt"].length, :>, 10, name
    end

    count = ->(selector) { all_steps { css_select(selector).size }.sum }
    assert_equal SNIPPETS.children.size, count.(".code-block")
    assert_equal 4, count.(".code-block code.language-shell")
    assert_equal SNIPPETS.glob("*.gd").size, count.(".code-block code.language-gdscript")
    # Only the shell commands copy. The pet's GDScript is for typing out.
    assert_equal SNIPPETS.glob("*.sh").size, count.(".code-block button.code-copy")
    assert_equal 0, count.(".code-block.no-copy button")
    assert_equal SNIPPETS.glob("*.gd").size, count.(".code-block.no-copy code.language-gdscript")
  end

  test "each step has its own address and title, and /guide shows the first" do
    get guide_path
    assert_select "title", "Build a desktop pet in Godot · playground"
    # Inside the old desktop's window, the article offers its own address in a new tab.
    article = -> { response.body[/<article.*<\/article>/m].sub(%r{<p class="guide-new-tab">.*?</p>}, "") }
    first = article.()
    get "/guide/setup"
    assert_response :ok
    assert_equal first, article.(), "/guide and /guide/setup show the same step"

    assert_equal %w[/guide/setup /guide/scene /guide/art /guide/move /guide/animate /guide/publish], GuidePage.all.map(&:path)
    assert_equal NAMES, GuidePage.all.map(&:name)
    GuidePage.all.drop(1).each do |step|
      get step.path
      assert_select "title", "#{step.name} · Build a desktop pet in Godot · playground"
    end
    # The intro opens the guide, on its first step only.
    get "/guide/setup"
    assert_select ".guide header p", /You’ll build a little pet/
    get "/guide/scene"
    assert_select ".guide header p", text: /You’ll build a little pet/, count: 0

    get "/guide/nope"
    assert_response :not_found
    # The steps' addresses leave the guide's own frames where they were.
    get guide_check_path(frame: "pick-step")
    assert_response :ok
  end

  test "under the guide, a button to the step before on the left and to the step after on the right, but none before the first or after the last" do
    all_steps do |step|
      back, on = step.previous, step.following
      assert_select ".hub-main > article.guide + nav.guide-pager", 1, step.slug
      assert_select ".guide-pager a", [ back, on ].compact.size, step.slug
      if back
        assert_select ".guide-pager a.guide-prev:first-child[rel=prev][href=?]", back.path, text: "← previous step: #{back.name}"
      end
      if on
        assert_select ".guide-pager a.guide-next.primary:last-child[rel=next][href=?]", on.path, text: "next step: #{on.name} →"
      end
    end
    get "/guide/setup"
    assert_select ".guide-prev", 0
    get "/guide/publish"
    assert_select ".guide-next", 0
  end

  test "the outline and the guide's own list name every step, mark the one that shows, and leave no overview" do
    all_steps do |step|
      assert_equal NAMES.each_with_index.map { |name, i| "#{i + 1} #{name}" }, css_select(".hub-outline .outline-step > a").map { it.text.squish }
      assert_equal GuidePage.all.map(&:path), css_select(".hub-outline .outline-step > a").map { it["href"] }
      assert_select ".hub-outline .outline-step > a[aria-current=page]", 1
      assert_select ".hub-outline .outline-step > a[aria-current=page][href=?]", step.path
      # The step that shows holds the list its sections fill.
      assert_select ".hub-outline .outline-step:has(> a[aria-current=page]) > ol[data-outline-target=sections]"
      assert_select ".hub-outline ol[data-outline-target=sections]", 1

      assert_equal GuidePage.all.map(&:path), css_select(".guide-contents a").map { it["href"] }
      assert_select ".guide-contents a[aria-current=page][href=?]", step.path, text: "#{step.number} #{step.name}"
      assert_select ".guide-contents a[data-action='guide-pager#go']", 6
      # The step shows only to a screen reader, as the lists mark it.
      assert_select ".guide header .visually-hidden", "step #{step.number} of 6: #{step.name}"
    end
    assert_select "#guide-overview", 0
    assert_select ".guide-count", 0
  end

  test "each step lists every anchor on its page, so an old link to one long page finds its step" do
    all_steps do |step|
      ids = css_select("article.guide [id]").map { it["id"] } - %w[guide]
      assert_equal step.anchors.sort, ids.sort, step.slug
    end
    assert_equal GuidePage.all.sum { it.anchors.size }, GuidePage.anchor_paths.size, "no anchor is on two steps"
  end

  test "an old link to the one long page goes on to the step that holds its anchor, before the step shows" do
    get guide_path
    script = css_select(".page > script").first.text
    assert_includes script, %("movement":"/guide/move")
    assert_includes script, %("ship-step":"/guide/publish")
    # The parts that moved go on to the part that took their place.
    assert_includes script, %("connect-hackatime":"pick-project")
    assert_includes script, %("hackatime-step":"pick-step")
    assert_not_includes script, %("connect-hackatime":"/guide/setup")
    assert_includes script, %(!== "/guide/setup")
    assert_includes script, "location.replace(`${step}#${anchor}`)"
    get "/guide/move"
    assert_includes css_select(".page > script").first.text, %(!== "/guide/move")
  end

  test "Set up has no Hackatime to connect, GitHub starts at its new repository page, and the Window tab's settings sit together" do
    get "/guide/setup"
    assert_select "#connect-hackatime, #hackatime-step, turbo-frame", 0
    assert_select "#hackatime", "Install Godot Hackatime, and set up Hackatime on your machine"
    assert_select "section[aria-labelledby=github] p", text: /sign up if you don/, count: 0
    assert_select "section[aria-labelledby=github] p", /\Aopen https:\/\/github.com\/new to create a new repository/

    get "/guide/scene"
    assert_equal SCENE_SETTINGS, scene_settings
  end

  test "every recording, poster, and screenshot the guide names is served, and small" do
    files = all_steps { css_select("source").map { it["src"] } + css_select("video").map { it["poster"] } + css_select("img.guide-shot").map { it["src"] } }.flatten(1)
    assert_equal GuideHelper::VIDEOS.size * 2 + GuideHelper::VIDEOS.values.count(&:last) + NewSiteHelper::STEP_SHOTS.size, files.uniq.size
    files.each do |path|
      get path
      assert_response :ok, path
      assert_includes %w[video/mp4 video/webm image/webp], response.media_type, path
      assert_operator response.body.bytesize, :<, 1.megabyte, path
    end
    # Each screenshot is its file's size, halved.
    NewSiteHelper::STEP_SHOTS.each do |name, size|
      image = Vips::Image.new_from_file(Rails.root.join("app/assets/images/guide/#{name}.webp").to_s)
      assert_equal size, [ image.width, image.height ], name
    end
  end

  test "each piece of code the guide adds is part of the one script it builds" do
    script = file_fixture("guide_pet.gd").read.split("\n")
    shown = []
    SNIPPETS.glob("*.gd").each do |snippet|
      snippet.read.split("\n").each do |line|
        line = line.delete_prefix("~")
        assert_includes script, line, "#{snippet.basename}: #{line.inspect} is not in the finished script" unless line.empty?
        shown << line
      end
    end
    assert_empty script.reject(&:empty?) - shown, "every line of the finished script is in the guide"
  end

  test "the shell blocks are shell, with straight quotes and one command a line" do
    commits = all_steps { css_select("code.language-shell").map(&:text) }.flatten(1)
    assert_includes commits, "git add .\ngit commit -m \"things-added\"\ngit push"
    commits.each { assert_no_match(/[“”‘’]/, it) }
  end

  test "without a script, every computer's version shows, each labelled" do
    count = ->(selector) { all_steps { css_select(selector).size }.sum }
    # The switch and the buttons do nothing without a script, so they hide.
    assert_equal 0, count.(".os-switch")
    assert_equal 4, count.(".os-note[hidden]")
    assert_equal SNIPPETS.glob("*.sh").size, count.("button.code-copy[hidden]")
    get "/guide/setup"
    assert_select ".os-step[data-os=macos] h3", "macOS"
    assert_select ".os-step[data-os=windows] h3", "Windows"
    assert_select ".os-step[data-os=linux] h3", "Linux"
    assert_select ".os-step[hidden]", 0
    # Each shortcut names both keys and whose they are.
    shortcuts = all_steps { css_select(".os-keys") }.flatten(1)
    assert_equal 5, shortcuts.size
    shortcuts.each do |shortcut|
      assert_equal %w[macos windows\ linux], css_select(shortcut, "[data-os]").map { it["data-os"] }
      assert_match(/on macOS or .* on Windows and Linux/, shortcut.text)
    end
    assert_equal 2, shortcuts.count { it.text.match?(/⌘S.*on macOS or Ctrl\+S on Windows and Linux/) }
    assert_equal 3, shortcuts.count { it.text.match?(/⌘B.*on macOS or F5 on Windows and Linux/) }
  end

  test "a shared link to the guide unfurls as the guide, with its own picture" do
    host! "playground.hackclub.com"
    https!
    get guide_path
    tag = ->(name) { css_select("meta[property='#{name}'], meta[name='#{name}']").first&.[]("content") }
    assert_equal "Build a desktop pet in Godot", tag.("og:title")
    assert_equal "Build a desktop pet in Godot", tag.("twitter:title")
    assert_equal "https://playground.hackclub.com/guide", tag.("og:url")
    assert_match(/desktop pet/, tag.("og:description"))
    assert_match %r{\Ahttps://playground\.hackclub\.com/assets/guide-opengraph-\w+\.png\z}, tag.("og:image")
    assert_match "build a virtual pet in Godot", tag.("og:image:alt")
    assert_equal [ "1200", "630" ], [ tag.("og:image:width"), tag.("og:image:height") ]

    get URI(tag.("og:image")).path
    assert_response :ok
    assert_operator response.body.bytesize, :<, 300.kilobytes
    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal [ 1200, 630 ], [ image.width, image.height ]
  end

  test "the guide's links out open in a new tab, and its last line goes to the Slack channel" do
    all_steps do
      css_select(".guide a[href^='http']").each do |link|
        assert_equal "_blank", link["target"], link["href"]
        assert_equal "noopener", link["rel"], link["href"]
      end
    end
    # Shipping comes last, after the export and the itch.io upload, with the
    # ship step and a link to the requirements.
    get GuidePage.all.last.path
    assert_select "a[href='https://hackclub.slack.com/archives/C0ASBTMS82H']", "#Playground"
    assert_select ".guide-step > section[aria-labelledby=ship]:last-child turbo-frame#ship-step"
    assert_select "section[aria-labelledby=ship] a[href=?][target=_blank]", requirements_path
  end

  private

  # The transparency section's steps and screenshots, in order: each step's
  # first words, each screenshot's name.
  def scene_settings
    css_select("section[aria-labelledby=transparent] > p, section[aria-labelledby=transparent] > img").drop(2).map do |part|
      next part["src"][%r{guide/([a-z-]+)-\w+\.webp}, 1] if part.name == "img"
      SCENE_SETTINGS.find { part.text.strip.start_with?(it) } || part.text.strip
    end
  end

  # Runs the block on each step's page, signed out, so the sign in section
  # shows too, and gives back each result.
  def all_steps
    GuidePage.all.map do |step|
      get step.path
      assert_response :ok, step.path
      yield step
    end
  end
end
