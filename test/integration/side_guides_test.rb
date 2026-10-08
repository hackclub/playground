require "test_helper"

# Stardance's and the clubs' guides (SideGuide): the guide in steps for
# everyone, signed out or in, with the new site or without, with nothing
# that needs an account. Their top bar is the logo, back to the guide, and
# help. A cookie remembers which one a browser opened, and / sends a
# signed-out browser back to it.
class SideGuidesTest < ActionDispatch::IntegrationTest
  # The parts of the new site's guide that need an account or act on the
  # site: the steps that sign in, link Hackatime, pick the pet's project,
  # and ship, the next step card, the active pet switch, the hours and
  # prizes beside the guide, and the top bar's tabs and account links.
  INTERACTIVE = [ "turbo-frame", "form", ".guide-do", "#hub-next", ".hub-right", ".side-card", ".side-hours", ".vmeter", ".pet-switch",
                  "#sign-in-title", "#connect-hackatime", "#hackatime-step", "#pick-project", "#pick-step", "#ship", "#ship-step",
                  ".topbar-tabs", ".topbar-admin", "a[href='/login']", "a[href='/requirements']", "a[href^='/guide']", "a[href='/']" ].freeze
  # Words about playground's account, shipping, hours, and prizes.
  PLAYGROUND_ONLY = /\bship|shipping|prize|redeem|\bmeter\b|reviewer|approved|sign out|sign in to|your hours/i

  test "every step of both guides shows signed out, with none of the parts that need an account" do
    SideGuide.all.each do |guide|
      texts = GuidePage.all.map do |step|
        get side_guide_path(guide, step)
        assert_response :ok
        assert_select "body.new-site.side-guide"
        INTERACTIVE.each { assert_select it, 0, "#{guide.slug}/#{step.slug}: #{it}" }
        # The top bar is the logo, back to this guide, and help.
        assert_select ".topbar a", 2
        assert_select ".topbar a.topbar-home[href=?]", side_guide_path(guide)
        assert_select ".topbar a[href='https://hackclub.slack.com/archives/C0ASBTMS82H']", "help in #playground"
        # The outline, the list of steps, and the buttons stay on this guide.
        assert_select ".outline-step > a", 7
        assert_equal GuidePage.all.map { side_guide_path(guide, it) }, css_select(".outline-step > a").map { it["href"] }
        assert_select ".guide-contents a", 7
        assert_select ".guide-pager a[href^=?]", "/#{guide.slug}/", count: [ step.previous, step.following ].compact.size
        assert_select "footer.footbar"
        css_select("#guide").text
      end
      assert_no_match PLAYGROUND_ONLY, texts.join(" "), guide.slug
      get side_guide_path(guide)
      assert_select "title", "Build a desktop pet in Godot · playground"
      assert_select ".outline-step > a[aria-current=page]", /Set up/
      get side_guide_path(guide, "own")
      assert_select "#your-own", "Make it your own!"
      assert_select "section[aria-labelledby=your-own] > p", /\ADon't just follow this guide/
      # The building blocks' cards open their pages from this guide.
      assert_equal BuildingBlock.all.map { "/#{guide.slug}/blocks/#{it.slug}" }, css_select("a.block-card[target=_blank]").map { it["href"] }
      get side_guide_path(guide, "publish")
      assert_select "title", "Publish · Build a desktop pet in Godot · playground"
      assert_select "#it-s-time-to-upload-your-project-to-itch"
      assert_select ".outline-step > a", text: /Publish and ship/, count: 0
    end
  end

  test "Stardance's guide sets up Hackatime in Godot, and the clubs' has no Hackatime at all" do
    get side_guide_path("stardance")
    assert_select "h3#hackatime", "Install Godot Hackatime, and set up Hackatime on your machine"
    assert_select "a[href='https://hackatime.hackclub.com/docs/getting-started/quick-start']"
    assert_select "#connect-hackatime", 0
    GuidePage.all.each do |step|
      get side_guide_path("clubs", step)
      assert_no_match(/hackatime|wakatime/i, response.body, step.slug)
    end
  end

  test "both have the guide's own edits: no GitHub sign up line, and the Window tab's settings together after the Advanced Settings toggle" do
    SideGuide.all.each do |guide|
      get side_guide_path(guide, "setup")
      assert_select "section[aria-labelledby=github] p", text: /sign up if you don/, count: 0
      get side_guide_path(guide, "scene")
      steps = css_select("section[aria-labelledby=transparent] > p").map { it.text.strip }
      order = [ "Click Project", "make sure the Advanced Settings toggle", "under the Window tab", "Then search for Per Pixel",
                "once you’ve done that search for Rendering" ].map { |start| steps.index { it.start_with?(start) } }
      assert order.all?, "#{guide.slug}: every step is there"
      assert_equal order.sort, order, "#{guide.slug}: in this order"
    end
  end

  test "the guide is the same for a visitor, a participant, and a participant with the new site" do
    pages = [ nil, false, true ].map do |flag|
      unless flag.nil?
        user = log_in("participant")
        user.update!(new_site: flag)
      end
      get side_guide_path("stardance", "move")
      assert_response :ok
      INTERACTIVE.each { assert_select it, 0, "#{flag.inspect}: #{it}" }
      without_tokens(response.body)
    end
    assert_equal 1, pages.uniq.size
  end

  test "a guide is remembered, the other one switches it, and / sends a signed-out browser back to it" do
    get root_path
    assert_response :ok
    assert_select "body.new-site .home-window", 4

    get side_guide_path("clubs", "art")
    assert_equal "clubs", cookies[SideGuide::COOKIE.to_s]
    get root_path
    assert_redirected_to side_guide_path("clubs")
    get root_path(open: "goal")
    assert_redirected_to side_guide_path("clubs")

    get side_guide_path("stardance")
    assert_equal "stardance", cookies[SideGuide::COOKIE.to_s]
    get root_path
    assert_redirected_to side_guide_path("stardance")

    # A cookie naming no guide sends nowhere.
    cookies[SideGuide::COOKIE.to_s] = "elsewhere"
    get root_path
    assert_response :ok

    # A signed-in participant has an account, so / is their landing.
    cookies[SideGuide::COOKIE.to_s] = "stardance"
    log_in("participant")
    get root_path
    assert_response :ok
    assert_select "#welcome"
  end

  test "a step no guide has is not found, and the new site's guide is public but unavailable to an unflagged account" do
    get "/stardance/nope"
    assert_response :not_found
    get "/clubs/Move"
    assert_response :not_found
    get "/guide/move"
    assert_response :ok
    assert_select "body.new-site"

    log_in("participant")
    get "/guide/move"
    assert_response :not_found
  end

  private

  def without_tokens(body)
    body.gsub(/(name="csrf-token" content=")[^"]+/, '\1').gsub(/(name="authenticity_token" value=")[^"]+/, '\1')
  end
end
