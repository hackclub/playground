# One set of numbers for the client and the server, so the checks mirror each
# other exactly. The client reads them from data attributes on the drop zone.
module ScreenshotLimits
  INPUT_TYPES = %w[image/png image/jpeg image/webp].freeze
  MAX_EDGE = 2560            # downscale above this long edge
  MIN_WIDTH = 640            # reject below 640 x 360 (either orientation)
  MIN_HEIGHT = 360
  MAX_BYTES = 5 * 1024 * 1024
  MAX_REQUEST_BYTES = 8 * 1024 * 1024
  MAX_PIXELS = 40_000_000    # refuse to decode anything larger
  PER_HOUR = 20
  PER_PET = 6                # the most screenshots a pet holds; the first is its cover
  QUALITY = 90

  module_function

  def too_small?(width, height)
    [ width, height ].max < MIN_WIDTH || [ width, height ].min < MIN_HEIGHT
  end

  def data_attributes
    { max_edge: MAX_EDGE, min_width: MIN_WIDTH, min_height: MIN_HEIGHT, max_bytes: MAX_BYTES,
      types: INPUT_TYPES.join(","), quality: QUALITY, per_pet: PER_PET }
  end
end
