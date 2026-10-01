require "vips"

# The server half of the upload checks. Nothing the
# browser sends is trusted: not the filename, not the Content-Type, not the
# client's own checks. The file is identified by its magic bytes, opened with
# that one format's loader only, measured from its header before any pixels
# are decoded, then decoded and re-encoded to a fresh WebP with no metadata.
# The re-encode is what goes to storage, never the uploaded bytes.
class ScreenshotProcessor
  class Rejected < StandardError; end

  Result = Data.define(:bytes, :width, :height)

  # libvips can load formats with a history of bugs (SVG, PDF, and others)
  # through its generic loader. Block them process-wide, and never use the
  # generic loader here anyway.
  Vips.block_untrusted(true) if Vips.respond_to?(:block_untrusted)

  LOADERS = { png: :pngload_buffer, jpeg: :jpegload_buffer, webp: :webpload_buffer }.freeze

  def self.call(bytes) = new(bytes).call

  def initialize(bytes)
    @bytes = bytes.to_s.b
  end

  def call
    reject "the file is empty" if @bytes.empty?
    reject "the file is over #{ScreenshotLimits::MAX_BYTES / 1024 / 1024} MB" if @bytes.bytesize > ScreenshotLimits::MAX_BYTES

    format = sniff or reject "only PNG, JPEG, or WebP images"
    image = open(format)
    width, height = image.width, image.height

    reject "the image is too large to process" if width * height > ScreenshotLimits::MAX_PIXELS
    reject "animated images are not allowed; use a still screenshot" if animated?(image)
    reject "the image is over #{ScreenshotLimits::MAX_EDGE} px on its long edge" if [ width, height ].max > ScreenshotLimits::MAX_EDGE
    if ScreenshotLimits.too_small?(width, height)
      reject "the image is #{width}×#{height}; screenshots must be at least #{ScreenshotLimits::MIN_WIDTH}×#{ScreenshotLimits::MIN_HEIGHT}"
    end

    Result.new(bytes: reencode(image), width:, height:)
  rescue Vips::Error => e
    Rails.logger.info("screenshot rejected by libvips: #{e.message.first(200)}")
    reject "the image could not be read"
  end

  private

  def reject(message) = raise(Rejected, message)

  def sniff
    return :png if @bytes.start_with?("\x89PNG\r\n\x1A\n".b)
    return :jpeg if @bytes.start_with?("\xFF\xD8\xFF".b)
    return :webp if @bytes.byteslice(0, 4) == "RIFF" && @bytes.byteslice(8, 4) == "WEBP"
    nil
  end

  # Reads the header only: width, height, and page count are known before any
  # pixels are decoded, so a decode bomb is refused without being expanded.
  def open(format)
    Vips::Image.public_send(LOADERS.fetch(format), @bytes, access: :sequential, fail: true)
  end

  # APNG has an acTL chunk before IDAT; animated WebP has the ANIM chunk.
  # libvips also reports n-pages for multi-frame images.
  def animated?(image)
    pages = image.get_typeof("n-pages").zero? ? 1 : image.get("n-pages")
    pages > 1 || @bytes.include?("acTL".b) || (@bytes.byteslice(0, 64).to_s.include?("ANIM".b))
  end

  def reencode(image)
    image = image.autorot
    image = image.colourspace(:srgb) unless image.interpretation == :srgb
    image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha? && image.bands > 4
    image.webpsave_buffer(Q: ScreenshotLimits::QUALITY, strip: true, keep: :none)
  rescue Vips::Error
    image.webpsave_buffer(Q: ScreenshotLimits::QUALITY, strip: true)
  end
end
