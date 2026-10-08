require "test_helper"

# The guide to making a pet in Godot, as a page of its own: every step with
# its recordings, screenshots, and code, each file served, and a link to it
# that unfurls as the guide.
class GuideTest < ActionDispatch::IntegrationTest
  setup { NewSite.for_visitors = false }
  teardown { NewSite.for_visitors = true }

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
    "movement" => "1. Movement",
    "on-screen" => "2. Keep it on screen",
    "bounce" => "3. Bounce off the edges",
    "animations" => "4. Animations",
    "break" => "5. Let it take a break",
    "drag" => "6. Pick it up and drag it around",
    "your-own" => "7. Make it your own!",
    "publish" => "8. Export your pet and put it on itch.io"
  }.freeze
  SNIPPETS = Rails.root.join("app/views/guides/snippets")

  test "the guide shows every step, each in the overview, with its recordings, screenshots, and code" do
    get guide_path
    assert_response :ok
    assert_select "title", "Build a virtual pet in Godot · playground"
    assert_select "h1", "Build a virtual pet in Godot"
    STEPS.each do |id, title|
      assert_select "##{id}", title
      assert_select ".guide-contents a[href='##{id}']", 1, id unless id == "hackatime"
    end

    assert_select "video", GuideHelper::VIDEOS.size
    GuideHelper::VIDEOS.each do |slug, (width, height, av1)|
      assert_select "video[muted][loop][playsinline][preload=none][width='#{width / 2}'][height='#{height / 2}'][poster*='/guide/#{slug}-poster-']", 1, slug do |video|
        assert video.first["aria-label"].start_with?("Screen recording: "), slug
        types = css_select(video.first, "source").map { it["type"] }
        assert_equal [ ('video/webm; codecs="av01.0.08M.08"' if av1), "video/mp4" ].compact, types, "the smaller copy goes first, for #{slug}"
      end
    end
    assert_select ".guide-video button.video-toggle", GuideHelper::VIDEOS.size

    assert_select "img.guide-shot", GuideHelper::SHOTS.size
    GuideHelper::SHOTS.each do |name, (width, height)|
      assert_select "img.guide-shot[src*='/guide/#{name}-'][width='#{width / 2}'][height='#{height / 2}'][loading=lazy]", 1, name do |image|
        assert_operator image.first["alt"].length, :>, 10, name
      end
    end

    assert_select ".code-block", SNIPPETS.children.size
    assert_select ".code-block code.language-shell", 4
    assert_select ".code-block code.language-gdscript", SNIPPETS.glob("*.gd").size
    # Only the shell commands copy. The pet's GDScript is for typing out.
    assert_select ".code-block button.code-copy", SNIPPETS.glob("*.sh").size
    assert_select ".code-block.no-copy button", 0
    assert_select ".code-block.no-copy code.language-gdscript", SNIPPETS.glob("*.gd").size
  end

  test "every recording, poster, and screenshot the guide names is served, and small" do
    get guide_path
    files = css_select("source").map { it["src"] } + css_select("video").map { it["poster"] } + css_select("img.guide-shot").map { it["src"] }
    assert_equal GuideHelper::VIDEOS.size * 2 + GuideHelper::VIDEOS.values.count(&:last) + GuideHelper::SHOTS.size, files.uniq.size
    files.each do |path|
      get path
      assert_response :ok, path
      assert_includes %w[video/mp4 video/webm image/webp], response.media_type, path
      assert_operator response.body.bytesize, :<, 1.megabyte, path
    end
    # Each screenshot is its file's size, halved.
    GuideHelper::SHOTS.each do |name, size|
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
    get guide_path
    commits = css_select("code.language-shell").map(&:text)
    assert_includes commits, "git add .\ngit commit -m \"things-added\"\ngit push"
    commits.each { assert_no_match(/[“”‘’]/, it) }
  end

  test "without a script, every computer's version shows, each labelled" do
    get guide_path
    # The switch and the buttons do nothing without a script, so they hide.
    assert_select ".os-switch[hidden]"
    assert_select "button.code-copy[hidden]", SNIPPETS.glob("*.sh").size
    assert_select "button.video-toggle[hidden]", GuideHelper::VIDEOS.size
    assert_select ".os-step[data-os=macos] h3", "macOS"
    assert_select ".os-step[data-os=windows] h3", "Windows"
    assert_select ".os-step[data-os=linux] h3", "Linux"
    assert_select ".os-step[hidden]", 0
    # Each shortcut names both keys and whose they are.
    assert_select ".os-keys", 5 do |shortcuts|
      shortcuts.each do |shortcut|
        assert_equal %w[macos windows\ linux], css_select(shortcut, "[data-os]").map { it["data-os"] }
        assert_match(/on macOS or .* on Windows and Linux/, shortcut.text)
      end
    end
    assert_select ".os-keys", text: /⌘S.*on macOS or Ctrl\+S on Windows and Linux/, count: 2
    assert_select ".os-keys", text: /⌘B.*on macOS or F5 on Windows and Linux/, count: 3
  end

  test "a shared link to the guide unfurls as the guide, with its own picture" do
    host! "playground.hackclub.com"
    https!
    get guide_path
    tag = ->(name) { css_select("meta[property='#{name}'], meta[name='#{name}']").first&.[]("content") }
    assert_equal "Build a virtual pet in Godot", tag.("og:title")
    assert_equal "Build a virtual pet in Godot", tag.("twitter:title")
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
    get guide_path
    css_select(".guide a[href^='http']").each do |link|
      assert_equal "_blank", link["target"], link["href"]
      assert_equal "noopener", link["rel"], link["href"]
    end
    assert_select "a[href='https://hackclub.slack.com/archives/C0ASBTMS82H']", "#Playground"
    assert_select "a[href=?][target=_top]", "/?open=ship", text: "ship"
    # Shipping comes last, after the export and the itch.io upload.
    assert_select "section[aria-labelledby=publish] a[href=?][target=_top]", "/?open=ship", text: "ship"
    assert_select "section[aria-labelledby=drag] a[href=?]", "/?open=ship", 0
  end

  test "Make it your own lists every building block under its text, each GIF opening the block's page in a new tab" do
    get guide_path
    assert_select "section[aria-labelledby=your-own] > p", /\Ayour project will be rejected/
    assert_equal BuildingBlock.all.map(&:title), css_select("section[aria-labelledby=your-own] > h3").map(&:text)
    assert_select "section[aria-labelledby=your-own] > h3[id]", 0
    links = css_select("section[aria-labelledby=your-own] > h3 + a.block-card")
    assert_equal BuildingBlock.all.map { "/guide/blocks/#{it.slug}" }, links.map { it["href"] }
    links.each do |link|
      assert_equal [ "_blank", "noopener" ], [ link["target"], link["rel"] ]
      assert_select link, "img[loading=lazy][width='640'][height='480']"
    end
    # Its block pages open for a reader of this guide too, and lead back to it.
    get links.first["href"]
    assert_response :ok
    assert_select "p.block-back a[href='/guide']"
  end
end
