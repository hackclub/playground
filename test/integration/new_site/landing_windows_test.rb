require "test_helper"

# Each box on the landing is a window in the old desktop's chrome: a title
# bar with its file name and an X over the content. The bar is a picture
# only, so screen readers skip it and its X is no button.
class NewSiteLandingWindowsTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  WINDOWS = { "home-pets" => "examples", "home-prizes" => "prizes.txt", "home-now" => "start.exe", "home-faq" => "faq.txt" }.freeze

  test "the example pets, the prizes, what to do now, and the FAQ are windows, in that order" do
    get root_path
    assert_equal WINDOWS.keys, css_select(".home-window").map { |window| (window["class"].split & WINDOWS.keys).first }
    WINDOWS.each do |box, title|
      assert_select ".home-window.#{box}" do
        assert_select "> .home-titlebar[aria-hidden=true] .home-title", title
        assert_select "> .home-titlebar .home-x", "X"
        assert_select "> .home-pane", 1
      end
    end
    assert_select ".home-titlebar button, .home-titlebar a", 0
  end

  test "the windows keep their content and links" do
    get root_path
    assert_select ".home-say", 2
    assert_select ".home-pets[aria-labelledby=pets-title]"
    assert_select "#pets-title.home-say", "Make a cool desktop pet like these"
    assert_select ".home-prizes[aria-labelledby=merch-title]"
    assert_select "#merch-title.home-say", "Get cool merch like this"
    assert_select ".home-pets .home-examples a[target=_blank][href^='https://']", 4
    assert_select ".home-prizes .home-requirements a[href=?][target=_blank]", requirements_path
    assert_select ".home-now .home-pane a.btn[href=?]", guide_path
    assert_select ".home-faq .home-pane details", 4
    assert_select ".home-faq a[href^='https://hackclub.slack.com'][target=_blank]", 1
  end

  test "start.exe's button starts the guide for a visitor and continues it once signed in" do
    get root_path
    assert_select ".home-now a.btn[href=?]", guide_path, text: "start the guide →"

    get dev_login_path(as: "participant")
    get root_path
    assert_select ".home-now a.btn[href=?]", guide_path, text: "continue the guide →"
  end
end
