require "test_helper"
require "vips"

# The site's icon shows in the browser tab and on a phone's home screen. Each
# page the site renders links it, and each link points at a file in public/
# of the size it claims.
class SiteIconTest < ActionDispatch::IntegrationTest
  test "the desktop, the participant pages, and the admin link the icon, and each link points at a real file" do
    pages = [ root_path, dashboard_path ]
    log_in("admin")
    pages += [ root_path, dashboard_path, admin_root_path ]
    pages.each do |path|
      get path
      assert_response :success
      links = css_select("head link[rel=icon], head link[rel=apple-touch-icon]")
      assert_equal [ [ "icon", "/favicon-32.png" ], [ "icon", "/icon.png" ], [ "apple-touch-icon", "/apple-touch-icon.png" ] ],
                   links.map { [ it["rel"], it["href"] ] }, path
      links.each do |link|
        file = Rails.root.join("public", link["href"].delete_prefix("/"))
        assert file.exist?, "#{link["href"]} on #{path}"
        next unless link["sizes"]
        image = Vips::Image.new_from_file(file.to_s)
        assert_equal link["sizes"], "#{image.width}x#{image.height}", link["href"]
      end
    end
  end

  test "the icons keep their transparency, and favicon.ico answers the browsers that ask for it" do
    { "icon.png" => 512, "apple-touch-icon.png" => 180, "favicon-32.png" => 32 }.each do |name, size|
      image = Vips::Image.new_from_file(Rails.root.join("public", name).to_s)
      assert_equal [ size, size ], [ image.width, image.height ], name
      assert image.has_alpha?, "#{name} keeps its transparency"
      assert_equal 0, image.getpoint(0, 0).last, "#{name}'s corner is clear"
    end
    ico = Rails.root.join("public/favicon.ico").binread
    assert_equal [ 0, 1, 2 ], ico.unpack("v3"), "an icon file holding two pictures"
    refute Rails.root.join("public/icon.svg").exist?, "the stock Rails icon is gone"
  end
end
