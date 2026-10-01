require "test_helper"

# Every page of the site belongs to one desktop window, or shows in no
# window on purpose. A new page on neither list fails here, so it gets a
# window before it ships.
class DesktopWindowsTest < ActiveSupport::TestCase
  test "every page the site serves belongs to a desktop window or is listed as shown in none" do
    pages = Rails.application.routes.routes.select { it.verb == "GET" && it.defaults[:controller] }
                 .map { "#{it.defaults[:controller]}##{it.defaults[:action]}" }.uniq
    # Rails' own pages and the admin open in a tab of their own.
    own = pages.reject { it.start_with?("rails/", "active_storage/", "turbo/", "admin/") }
    listed = DesktopWindows::PAGES.keys + DesktopWindows::ELSEWHERE
    assert_empty own - listed, "each page needs a window in DesktopWindows::PAGES, or a place in ELSEWHERE"
    assert_empty listed - own, "a listed page the site no longer serves"
    assert_empty DesktopWindows::PAGES.keys & DesktopWindows::ELSEWHERE
  end

  test "each kind of window a page belongs to is one the desktop knows how to open" do
    source = Rails.root.join("app/javascript/landing.js").read
    kinds = source[/^const windowKinds = \{\n(.*?)^\};/m, 1].scan(/^    (\w+): \{/).flatten
    assert_equal %w[goal login pet ship guide requirements redeem], kinds
    assert_empty DesktopWindows::PAGES.values.uniq - kinds, "each kind needs an entry in landing.js's windowKinds"
  end

  test "the desktop gets each page's path as the router writes it" do
    assert_equal [
      { kind: "goal", path: "/dashboard" },
      { kind: "login", path: "/login" },
      { kind: "guide", path: "/guide" },
      { kind: "requirements", path: "/requirements" },
      { kind: "goal", path: "/projects/new" },
      { kind: "redeem", path: "/redemptions/new" },
      { kind: "pet", path: "/projects/:id" },
      { kind: "pet", path: "/projects/:id/edit" },
      { kind: "ship", path: "/projects/:id/checks" }
    ], DesktopWindows.pages
  end
end
