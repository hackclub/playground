require "test_helper"
require "zlib"

# The server-side screenshot checks, against real and hostile files.
class ScreenshotProcessorTest < ActiveSupport::TestCase
  def png_chunk(type, data) = [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N")

  # A PNG whose header claims width x height, with almost no pixel data.
  def fake_png(width, height, extra_chunks: "")
    ihdr = png_chunk("IHDR", [ width, height, 8, 2, 0, 0, 0 ].pack("NNCCCCC"))
    idat = png_chunk("IDAT", Zlib::Deflate.deflate("\x00" * 64))
    "\x89PNG\r\n\x1A\n".b + ihdr + extra_chunks + idat + png_chunk("IEND", "")
  end

  def reencoded(result) = Vips::Image.webpload_buffer(result.bytes)

  test "a normal screenshot is re-encoded to WebP at the same size" do
    result = ScreenshotProcessor.call(image_bytes(1280, 720))
    assert_equal [ 1280, 720 ], [ result.width, result.height ]
    assert_equal "RIFF", result.bytes.byteslice(0, 4)
    assert_equal "WEBP", result.bytes.byteslice(8, 4)
  end

  test "JPEG and WebP input are accepted, and a portrait screenshot is fine" do
    assert ScreenshotProcessor.call(image_bytes(1920, 1080, format: :jpeg))
    assert ScreenshotProcessor.call(image_bytes(1080, 1920, format: :webp))
  end

  test "EXIF, including GPS location, is removed" do
    image = (Vips::Image.black(1280, 720, bands: 3) + 90).cast(:uchar).copy
    image.set_type(GObject::GSTR_TYPE, "exif-ifd3-GPSLatitude", "44 deg 23' 0\"")
    image.set_type(GObject::GSTR_TYPE, "exif-ifd0-Make", "SpyPhone")
    jpeg = image.jpegsave_buffer
    assert_includes jpeg.b, "SpyPhone".b, "the test JPEG carries EXIF"
    out = ScreenshotProcessor.call(jpeg).bytes
    refute_includes out.b, "SpyPhone".b
    refute_includes out.b, "Exif".b
    assert_equal 0, reencoded(ScreenshotProcessor.call(jpeg)).get_typeof("exif-data")
  end

  test "too small is refused" do
    error = assert_raises(ScreenshotProcessor::Rejected) { ScreenshotProcessor.call(image_bytes(600, 400)) }
    assert_match "640×360", error.message
    assert_raises(ScreenshotProcessor::Rejected) { ScreenshotProcessor.call(image_bytes(1280, 300)) }
  end

  test "too large, which the client should have shrunk, is refused" do
    assert_raises(ScreenshotProcessor::Rejected) { ScreenshotProcessor.call(image_bytes(3000, 1000)) }
  end

  test "a decode bomb is refused from its header, before its pixels are expanded" do
    error = assert_raises(ScreenshotProcessor::Rejected) { ScreenshotProcessor.call(fake_png(30_000, 30_000)) }
    assert_match "too large to process", error.message
  end

  test "an animated PNG is refused" do
    actl = png_chunk("acTL", [ 2, 0 ].pack("NN"))
    error = assert_raises(ScreenshotProcessor::Rejected) { ScreenshotProcessor.call(fake_png(1280, 720, extra_chunks: actl)) }
    assert_match "animated", error.message
  end

  test "formats other than PNG, JPEG, and WebP are refused whatever they claim to be" do
    gif = "GIF89a".b + "\x00" * 100
    svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="720"><script>alert(1)</script></svg>)
    html = "<!doctype html><script>alert(1)</script>"
    [ gif, svg, html, "" ].each do |bytes|
      assert_raises(ScreenshotProcessor::Rejected, bytes.first(10)) { ScreenshotProcessor.call(bytes) }
    end
  end

  test "a file with a PNG signature and garbage after it is refused" do
    assert_raises(ScreenshotProcessor::Rejected) { ScreenshotProcessor.call("\x89PNG\r\n\x1A\n".b + SecureRandom.bytes(5000)) }
  end

  test "over the byte limit is refused without decoding" do
    big = "\x89PNG\r\n\x1A\n".b + "\x00" * (ScreenshotLimits::MAX_BYTES + 1)
    error = assert_raises(ScreenshotProcessor::Rejected) { ScreenshotProcessor.call(big) }
    assert_match "5 MB", error.message
  end
end
