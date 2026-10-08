require "test_helper"

# Where a browser came from, as the server takes it: cleaned the way the
# browser cleans it, then only the channels the browser names, the media it
# uses, and short plain values pass. Anything else is "other", and so is a
# new value once a column holds DAILY_CAP of its own on a day.
class TrafficSourceTest < ActiveSupport::TestCase
  DAY = Date.new(2026, 10, 8)
  T = TrafficSource::Touch

  test "a value is trimmed, lowercased, and its spaces become dashes, and only plain short values pass" do
    assert_equal "clubs", TrafficSource.clean("  Clubs ")
    assert_equal "fall-workshop", TrafficSource.clean("Fall  Workshop")
    assert_equal "news.ycombinator.com", TrafficSource.clean("news.ycombinator.com")
    assert_equal "hcb_2026", TrafficSource.clean("HCB_2026")
    # The browser's own names pass as they are, spaces and all.
    assert_equal "hack club site", TrafficSource.clean("hack club site")
    assert_equal "a" * 40, TrafficSource.clean("a" * 40)
    [ "a" * 41, "launch!", "<script>", "ünïcode", "-dash-first", "100%", "a/b", "x?y=z" ].each do |junk|
      assert_equal "other", TrafficSource.clean(junk), junk
    end
    assert_equal "", TrafficSource.clean(nil)
    assert_equal "", TrafficSource.clean([ "clubs" ])
    assert_equal "other", TrafficSource.clean("", source: true)
  end

  test "touches come from the six parameters, and a touch with no source is unknown" do
    touches = TrafficSource.touches("first_source" => "Clubs", "first_medium" => "Email", "first_campaign" => "Launch",
                                    "last_source" => "slack", "last_medium" => "referral", "last_campaign" => "")
    assert_equal T.new(source: "clubs", medium: "email", campaign: "launch"), touches[:first]
    assert_equal T.new(source: "slack", medium: "referral", campaign: ""), touches[:last]
    assert_equal({ first: TrafficSource::UNKNOWN, last: TrafficSource::UNKNOWN }, TrafficSource.touches({}))
    assert_equal T.new(source: "other", medium: "", campaign: ""), TrafficSource.touches("first_source" => [ "a" ])[:first]
  end

  test "past the daily cap a new value is other, while values seen that day, known ones, and other days still pass" do
    direct = T.new(source: "direct", medium: "", campaign: "")
    TrafficSource::DAILY_CAP.times { SignupSourceDay.count!(day: DAY, first: T.new(source: "site#{it}.example", medium: "referral", campaign: ""), last: direct) }
    assert_equal TrafficSource::DAILY_CAP, SignupSourceDay.where(day: DAY).distinct.count(:first_source)

    columns = ->(source, day: DAY) { TrafficSource.columns(SignupSourceDay, day:, first: T.new(source:, medium: "", campaign: ""), last: direct) }
    assert_equal "other", columns["one-too-many.example"][:first_source]
    assert_equal "site3.example", columns["site3.example"][:first_source]
    assert_equal "slack", columns["slack"][:first_source]
    assert_equal "one-too-many.example", columns["one-too-many.example", day: DAY + 1][:first_source]
    # The cap counts each column on its own.
    assert_equal "site99.example", TrafficSource.columns(SignupSourceDay, day: DAY, first: direct, last: T.new(source: "site99.example", medium: "", campaign: ""))[:last_source]
  end

  test "every name the browser gives a source is one the server keeps" do
    assert_includes TrafficSource::CHANNELS, "hack club site"
    assert TrafficSource::CHANNELS.all? { TrafficSource.clean(it, source: true) == it }
    assert_equal "Clubs", TrafficSource.name("clubs")
    assert_equal "news.ycombinator.com", TrafficSource.name("news.ycombinator.com")
  end
end
