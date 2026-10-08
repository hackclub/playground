require "test_helper"

# A building block's page (BuildingBlock), which a card in the guide's "Make
# it your own" step opens: open to everyone, in the guide's look, with its
# words as its guide.md has them, every picture it names served, and a small
# link back to the guide the reader came from.
class BuildingBlocksTest < ActionDispatch::IntegrationTest
  include NewSiteTests

  test "every block's page shows signed out, with its title, pictures, and code, each picture served" do
    BuildingBlock.all.each do |block|
      get "/guide/blocks/#{block.slug}"
      assert_response :ok, block.slug
      assert_select "title", "#{block.title} · Build a desktop pet in Godot · playground"
      assert_select "article.guide h1", block.page.title
      # The guide's own top bar, with its tabs, the guide's open, and sign in.
      assert_select ".topbar .topbar-tabs a.topbar-tab[aria-current]", "guide"
      assert_select ".topbar .topbar-links a[href='/login']", "sign in"
      assert_select "article.guide a[href='/login']", 0
      # The demo GIF first, full width, then the screenshots at half their size.
      result = css_select("article.guide img.block-result").sole
      assert_match %r{/blocks/#{block.slug}/images/result-\w+\.gif\z}, result["src"]
      assert_equal block.page.alt_for("images/result.gif"), result["alt"]
      css_select("article.guide img").each do |image|
        assert_operator image["alt"].to_s.length, :>, 10, image["src"]
        get image["src"]
        assert_response :ok, image["src"]
        assert_includes %w[image/gif image/png], response.media_type
      end
    end
  end

  test "a block's page keeps the words of its guide.md, and draws its code as the guide's code blocks" do
    BuildingBlock.all.each do |block|
      get "/guide/blocks/#{block.slug}"
      text = css_select("article.guide").text.squish
      block.page.parts.select { it.kind.in?(%i[p h2 h3]) }.each do |part|
        words = part.text.gsub(/\*\*|`/, "").gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')
        assert_includes text, words.squish, block.slug
      end
      assert_equal block.page.parts.count { it.kind == :code }, css_select(".code-block").size, block.slug
    end
    get "/guide/blocks/save-and-load"
    assert_select "h2#make-a-configfile", "Make a ConfigFile"
    assert_select "p code", "user://"
    assert_select "p strong", "Project > Open User Data Folder"
    codes = css_select(".code-block.no-copy code.language-gdscript")
    assert_equal 2, codes.size
    assert_equal "var config = ConfigFile.new()\nconfig.set_value(\"pet\", \"name\", \"Bob\")\nconfig.save(\"user://pet.cfg\")", codes.first.text
    assert_includes codes.last.text, "\tvar pet_name = config.get_value(\"pet\", \"name\")"
    assert_select ".code-block .code-lang", "GDScript"
    assert_select ".code-block button", 0
    # Links out open in a new tab, as the guide's do.
    links = css_select("article.guide a[href^='http']")
    assert_equal [ "https://docs.godotengine.org/en/stable/classes/class_configfile.html",
                   "https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html" ], links.map { it["href"] }
    links.each { assert_equal [ "_blank", "noopener" ], [ it["target"], it["rel"] ] }
    assert_select "a[href$='data_paths.html'] code", "user://"
  end

  test "the shader's code, which its page says to paste in, copies, and the pet's GDScript does not" do
    get "/guide/blocks/shader"
    assert_select ".code-block[data-controller=code-block] code.language-glsl", 1
    assert_select ".code-block[data-controller=code-block] .code-lang", "GLSL"
    assert_select "button.code-copy[aria-label='copy the GLSL']"
    assert_select ".code-block.no-copy code.language-gdscript"
  end

  test "the sound block links its recording with sound, which is served" do
    get "/guide/blocks/sound-effect"
    link = css_select("article.guide a").find { it.text == "listen here" }
    assert_equal "_blank", link["target"]
    get link["href"]
    assert_response :ok
    assert_equal "video/mp4", response.media_type
  end

  test "its link back goes to the step with the cards, on the guide the reader came from" do
    get "/guide/blocks/particles"
    assert_select "p.block-back a[href='/guide/own#your-own']", "← back to the guide"
    assert_select ".topbar-home[href='/']"
    SideGuide.all.each do |guide|
      get "/#{guide.slug}/blocks/particles"
      assert_response :ok
      assert_select "p.block-back a[href=?]", "/#{guide.slug}/own#your-own"
      # A side guide's page wears that guide's top bar: its logo goes back to it.
      assert_select "a.topbar-home[href=?]", "/#{guide.slug}"
      assert_select ".topbar-tabs", 0
    end
    # Someone on the old desktop has no guide in steps, so it goes to /guide.
    user = log_in("participant")
    user.update!(new_site: false)
    get "/guide/blocks/particles"
    assert_response :ok
    assert_select "p.block-back a[href='/guide']"
    assert_select ".topbar .topbar-tabs a.topbar-tab[aria-current]", "guide"
  end

  test "a block or a guide that does not exist is not found" do
    get "/guide/blocks/nope"
    assert_response :not_found
    get "/elsewhere/blocks/particles"
    assert_response :not_found
  end

  test "every block in the list has its page and its card's GIF in its folder" do
    assert_equal BuildingBlock.all.map(&:slug).uniq, BuildingBlock.all.map(&:slug)
    assert_equal BuildingBlock.all.map(&:slug).sort, BuildingBlock::ROOT.children.select(&:directory?).map { it.basename.to_s }.sort,
                 "every block folder is in the list"
    BuildingBlock.all.each do |block|
      assert block.folder.join("guide.md").file?, block.slug
      assert_equal [ 640, 480 ], block.gif_size, block.slug
      assert block.page.title.present?, block.slug
      # Every file the page names is in its folder.
      block.folder.join("guide.md").read.scan(/\]\((images\/[^)]+)\)/).flatten.each do |path|
        assert block.folder.join(path).file?, "#{block.slug}: #{path}"
      end
    end
  end
end
