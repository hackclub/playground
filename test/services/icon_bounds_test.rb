require "test_helper"

# The boxes around the desktop icons' drawn pixels, baked into
# config/icon_bounds.yml ahead of time.
class IconBoundsTest < ActiveSupport::TestCase
  test "each icon's baked box is its image's as the image is now" do
    baked = YAML.load_file(IconBounds::FILE)
    assert_equal IconBounds::ICONS.sort, baked.keys.sort
    IconBounds::ICONS.each do |name|
      path = IconBounds::DIR.join(name)
      assert_equal IconBounds.digest(path), baked[name]["sha256"], "#{name} changed since the bake: run bin/rails icons:bounds"
      assert_equal IconBounds.measure(path), baked[name]["box"], "#{name}'s box: run bin/rails icons:bounds"
    end
    # welcome.txt's page has clear margins, and a drag through them passes it by.
    assert_equal [ 0.1754, 0.1015, 0.8369, 0.9138 ], IconBounds.all["file.png"]
    # So do the trash's two drawings. The full can's paper reaches higher.
    assert_equal [ 0.1563, 0.1641, 0.8281, 0.9297 ], IconBounds.all["trash-empty.png"]
    assert_equal [ 0.1563, 0.0234, 0.8281, 0.9688 ], IconBounds.all["trash-full.png"]
  end

  test "every picture the desktop gives an icon has a baked box, and the shortcut arrow has none" do
    view = Rails.root.join("app/views/landing/show.html.erb").read
    pictures = view.scan(/data-[\w-]+-icon="<%= image_path\("landing\/([^"]+)"\) %>"/).flatten.uniq
    assert_includes pictures, "shortcut.webp"
    assert_equal (pictures - [ "shortcut.webp" ]).sort, IconBounds::ICONS.sort
  end

  test "a box holds the drawn pixels only, from 10% opacity up" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "icon.png")
      # A clear 100x50 picture, with a faint mark in one corner and a drawn
      # 30x20 block, and a block at the threshold beside it.
      image = Vips::Image.black(100, 50, bands: 4)
      image = image.draw_rect([ 0, 0, 0, 20 ], 0, 0, 5, 5, fill: true)
      image = image.draw_rect([ 255, 0, 0, 255 ], 20, 10, 30, 20, fill: true)
      image = image.draw_rect([ 0, 0, 255, 26 ], 50, 12, 10, 4, fill: true)
      image.pngsave(path)
      assert_equal [ 0.2, 0.2, 0.6, 0.6 ], IconBounds.measure(path)
    end
  end

  test "a picture with no transparency counts whole" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "icon.png")
      Vips::Image.black(40, 40, bands: 3).pngsave(path)
      assert_equal [ 0.0, 0.0, 1.0, 1.0 ], IconBounds.measure(path)
    end
  end
end
