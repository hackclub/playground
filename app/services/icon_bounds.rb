require "digest"
require "vips"

# The smallest box around each desktop icon's drawn pixels, as fractions of
# its image: left, top, right, bottom. A drag across the desktop selects an
# icon only when it touches that box, so an empty corner or the label does
# not count. The boxes are measured here, ahead of time, never in the
# browser: `bin/rails icons:bounds` bakes them into config/icon_bounds.yml,
# with each image's digest, and a test fails when an image changes without a
# rebake.
module IconBounds
  FILE = Rails.root.join("config/icon_bounds.yml")
  DIR = Rails.root.join("app/assets/images/landing")

  # The pictures landing.js puts on desktop icons. The shortcut arrow lies
  # over some of them, and is not part of any icon's picture.
  ICONS = %w[
    file.png iconplaceholder.png hackclub.webp privacy-and-terms.webp bounty.webp security.webp
    sponsor.webp trash-empty.png trash-full.png banana-peel.png
  ].freeze

  # A pixel counts as drawn from 10% opacity up, so the faint edge of an
  # antialiased shape, or a soft shadow's tail, does not stretch the box.
  ALPHA = 0.1

  HEADER = <<~YAML
    # The box around each desktop icon's drawn pixels, as fractions of its
    # image: left, top, right, bottom. Baked by `bin/rails icons:bounds` from
    # app/services/icon_bounds.rb, with each image's SHA-256. Do not edit.
  YAML

  module_function

  # The baked boxes, by image name.
  def all = YAML.load_file(FILE).transform_values { it.fetch("box") }

  def bake
    boxes = ICONS.to_h { |name| [ name, { "box" => measure(DIR.join(name)), "sha256" => digest(DIR.join(name)) } ] }
    File.write(FILE, HEADER + boxes.to_yaml.delete_prefix("---\n"))
  end

  # A picture with no transparency is drawn edge to edge.
  def measure(path)
    image = Vips::Image.new_from_file(path.to_s)
    return [ 0.0, 0.0, 1.0, 1.0 ] unless image.has_alpha?
    full = image.format == :ushort ? 65_535 : 255
    drawn = image.extract_band(image.bands - 1) >= ALPHA * full
    # Each column's and each row's sum of drawn pixels.
    columns, rows = drawn.project
    xs = columns.to_a.flatten.each_with_index.filter_map { |sum, x| x if sum.positive? }
    ys = rows.to_a.flatten.each_with_index.filter_map { |sum, y| y if sum.positive? }
    raise ArgumentError, "#{path} has no drawn pixels" if xs.empty? || ys.empty?
    [ xs.first.to_f / image.width, ys.first.to_f / image.height, (xs.last + 1.0) / image.width, (ys.last + 1.0) / image.height ]
      .map { it.round(4) }
  end

  def digest(path) = Digest::SHA256.file(path).hexdigest
end
