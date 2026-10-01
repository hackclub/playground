require "test_helper"

# Plausible counts visits when PLAUSIBLE_SRC holds the site's script URL, and
# the page loads nothing from plausible.io without it.
class PlausibleTest < ActionDispatch::IntegrationTest
  SRC = "https://plausible.io/js/pa-test.js".freeze

  teardown { ENV.delete("PLAUSIBLE_SRC") }

  test "with a script URL, the desktop, the guide, and the login load it and start it" do
    ENV["PLAUSIBLE_SRC"] = SRC
    [ root_path, guide_path, login_path ].each do |path|
      get path
      assert_response :success
      assert_equal [ SRC ], css_select("head script[src*='plausible']").map { it["src"] }, path
      assert_select "head script[src='#{SRC}'][async]", 1
      assert_match "plausible.init()", css_select("head script:not([src])").map(&:text).join, path
    end
  end

  test "without a script URL, no page loads Plausible" do
    ENV.delete("PLAUSIBLE_SRC")
    [ root_path, guide_path, login_path ].each do |path|
      get path
      assert_response :success
      assert_no_match "plausible", response.body, path
    end
  end
end
