require "application_system_test_case"

# Where a browser came from, worked out in the browser (attribution.js), and
# a reader's journey through a guide as the browser keeps it (journey.js),
# run in a real browser: the touch an arrival makes, the first and last
# touch rules, engaged time with hidden tabs and idle readers left out, and
# the reports a journey sends. Then the login carrying the touches to count
# a new account.
class TrafficSourceTest < ApplicationSystemTestCase
  HOST = "playground.hackclub.com"

  setup { visit "/requirements" }

  test "a tagged link names its own source, trimmed, lowercased, spaced with dashes, and cut to 40 characters" do
    assert_equal({ "source" => "clubs", "medium" => "email", "campaign" => "fall-launch" },
                 touch("/?utm_source=%20Clubs%20&utm_medium=Email&utm_campaign=Fall%20Launch", "https://hackclub.slack.com/"))
    assert_equal({ "source" => "discord-server", "medium" => "", "campaign" => "" }, touch("/?ref=Discord-Server"))
    assert_equal "a" * 40, touch("/?utm_source=#{"A" * 60}")["source"]
    # A tag wins over the guide a first visit starts on.
    assert_equal "newsletter", touch("/clubs?utm_source=newsletter", "", first: true)["source"]
  end

  test "an untagged arrival comes from its referring site's host, named when it is a channel, and direct from nowhere or here" do
    {
      "https://hackclub.slack.com/archives/C0ASBTMS82H" => %w[slack referral], "https://app.slack.com/client" => %w[slack referral],
      "android-app://com.Slack/" => %w[slack referral], "https://www.google.com/" => %w[search organic],
      "https://www.google.co.uk/search?q=pet" => %w[search organic], "https://duckduckgo.com/" => %w[search organic],
      "https://mail.google.com/mail/u/0/" => %w[email email], "https://t.co/abc" => %w[x referral], "https://x.com/hackclub" => %w[x referral],
      "https://github.com/hackclub/playground" => %w[github referral], "https://discord.com/channels/1/2" => %w[discord referral],
      "https://www.youtube.com/watch?v=1" => %w[youtube referral], "https://youtu.be/1" => %w[youtube referral],
      "https://hackclub.com/" => [ "hack club site", "referral" ], "https://www.hackclub.com/clubs/" => [ "hack club site", "referral" ],
      "https://summer.hackclub.com/" => %w[summer.hackclub.com referral], "https://news.ycombinator.com/item?id=1" => %w[news.ycombinator.com referral],
      "https://docs.google.com/document/d/1" => %w[docs.google.com referral],
      "" => [ "direct", "" ], "https://#{HOST}/guide" => [ "direct", "" ], "https://www.#{HOST}/" => [ "direct", "" ], "not a url" => [ "direct", "" ]
    }.each do |referrer, (source, medium)|
      assert_equal({ "source" => source, "medium" => medium, "campaign" => "" }, touch("/guide", referrer), referrer)
    end
  end

  test "a first visit that starts on Stardance's or the clubs' guide comes from it, with the referring site as its medium" do
    assert_equal({ "source" => "clubs", "medium" => "direct", "campaign" => "" }, touch("/clubs/move", "", first: true))
    assert_equal({ "source" => "stardance", "medium" => "slack", "campaign" => "" }, touch("/stardance", "https://hackclub.slack.com/", first: true))
    assert_equal "direct", touch("/clubs", "", first: false)["source"], "only a first visit"
    assert_equal "direct", touch("/clubsy", "", first: true)["source"]
  end

  test "first touch is set once, and last touch moves on to each arrival that is not direct" do
    slack, github, direct = %w[slack github direct].map { { "source" => it, "medium" => "", "campaign" => "" } }
    unknown = { "source" => "unknown", "medium" => "", "campaign" => "" }
    assert_equal({ "first" => slack, "last" => slack }, apply(nil, slack))
    assert_equal({ "first" => direct, "last" => direct }, apply(nil, direct))
    assert_equal({ "first" => slack, "last" => slack }, apply({ first: slack, last: slack }, direct))
    assert_equal({ "first" => slack, "last" => github }, apply({ first: slack, last: slack }, github))
    assert_equal({ "first" => direct, "last" => github }, apply({ first: direct, last: direct }, github))
    # A browser that used the site before counting began came from somewhere unknown.
    assert_equal({ "first" => unknown, "last" => unknown }, apply(nil, direct, before: true))
    assert_equal({ "first" => unknown, "last" => slack }, apply(nil, slack, before: true))
  end

  test "each page is an arrival: first touch stays, last moves on, the admin is none, and earlier use makes it unknown" do
    clear_storage
    capture("/clubs?utm_source=clubs&utm_medium=email&utm_campaign=launch")
    capture("/guide", "https://#{HOST}/clubs")
    capture("/", "https://hackclub.slack.com/")
    capture("/admin/stats?utm_source=nope")
    capture("/guide")
    kept = page.evaluate_script("JSON.parse(localStorage.getItem('playground-traffic-source'))")
    assert_equal({ "source" => "clubs", "medium" => "email", "campaign" => "launch" }, kept["first"])
    assert_equal({ "source" => "slack", "medium" => "referral", "campaign" => "" }, kept["last"])

    clear_storage
    page.execute_script("localStorage.setItem('playground-guide-os', 'mac')")
    capture("/", "https://github.com/")
    kept = page.evaluate_script("JSON.parse(localStorage.getItem('playground-traffic-source'))")
    assert_equal [ "unknown", "github" ], [ kept["first"]["source"], kept["last"]["source"] ]
  end

  test "every source the browser names is one the server keeps" do
    channels = module_call("attribution", "m.CHANNELS")
    assert_equal channels.uniq, channels
    assert_empty channels - TrafficSource::CHANNELS
  end

  test "engaged time counts while the tab shows and the reader did something in the last 30 seconds" do
    times = module_call("guide_journey", <<~JS)
      (() => {
        const clock = new m.EngagementClock({ idle: 30000, now: 0 })
        const frame = new m.EngagementClock({ idle: 30000, now: 0, active: false })
        const asleep = new m.EngagementClock({ idle: 30000, now: 0 })
        return [
          clock.advance(10000), clock.advance(40000), clock.advance(50000),
          clock.activity(60000), clock.advance(70000),
          clock.hide(75000), clock.advance(100000), clock.activity(101000), clock.show(110000), clock.advance(115000),
          frame.advance(5000), frame.activity(6000), frame.advance(9000),
          frame.hide(10000), frame.show(60000), frame.advance(65000), frame.activity(66000), frame.advance(67000),
          asleep.advance(3600000)
        ]
      })()
    JS
    # Idle after 30s, nothing while hidden, even with activity, from
    # showing again on, nothing in a desktop window until the reader acts
    # there, even when the tab comes back, and a laptop asleep for an hour
    # adds 30s at most.
    assert_equal [ 10000, 20000, 0, 0, 10000, 5000, 0, 0, 0, 5000, 0, 0, 3000, 1000, 0, 0, 0, 1000, 30000 ], times
  end

  test "time falls into buckets of minutes" do
    assert_equal [ 0, 0, 2, 2, 5, 60, 60, 5 ], module_call("guide_journey", "[0, 119, 120, 299, 300, 3600, 99999].map(s => m.bucket(s)).concat(m.bucket(5, 1))")
  end

  test "a journey reports where it was and where it is, once each, never back, with the touches it started with" do
    reports = module_call("guide_journey", <<~JS)
      (() => {
        const store = new Map()
        const storage = { getItem: key => store.get(key) ?? null, setItem: (key, value) => store.set(key, value) }
        const journey = new m.Journey("clubs", { stages: ["opened", "a", "b", "c"], reach: 2, minute: 60, storage })
        const clubs = { first: { source: "clubs", medium: "", campaign: "" }, last: { source: "clubs", medium: "", campaign: "" } }
        const slack = { first: { source: "slack", medium: "", campaign: "" }, last: { source: "slack", medium: "", campaign: "" } }
        const out = []
        out.push(journey.next({ furthest: -1, touches: clubs, day: "2026-10-08" }))
        journey.addSeconds(1.5)
        out.push(journey.next({ furthest: -1, touches: clubs, day: "2026-10-08" }))
        journey.addSeconds(1)
        out.push(journey.next({ furthest: -1, touches: clubs, day: "2026-10-08" }))
        out.push(journey.next({ furthest: -1, touches: clubs, day: "2026-10-08" }))
        const moved = journey.next({ furthest: 0, touches: slack, day: "2026-10-09" })
        out.push(moved)
        journey.undo(moved)
        out.push(journey.next({ furthest: 0, touches: slack, day: "2026-10-09" }))
        journey.addSeconds(200)
        out.push(journey.next({ furthest: -1, touches: slack, day: "2026-10-09" }))
        out.push(m.reportParams("clubs", out[6]))
        store.set("playground-guide-journey:clubs", JSON.stringify({ day: "2026-10-08", seconds: 900, sent: { stage: "gone", minutes: 0 } }))
        out.push(journey.next({ furthest: 2, touches: clubs }))
        out.push(new m.Journey("clubs", { stages: ["opened"], reach: 2, minute: 60, storage: null }).next({ furthest: 0, touches: clubs }))
        return out
      })()
    JS
    clubs = { "first" => { "source" => "clubs", "medium" => "", "campaign" => "" }, "last" => { "source" => "clubs", "medium" => "", "campaign" => "" } }
    assert_nil reports[0], "not opened yet"
    assert_nil reports[1], "1.5 seconds is not 2"
    assert_equal({ "day" => "2026-10-08", **clubs, "from" => nil, "to" => { "stage" => "opened", "minutes" => 0 } }, reports[2])
    assert_nil reports[3], "nothing new"
    assert_equal({ "day" => "2026-10-08", **clubs, "from" => { "stage" => "opened", "minutes" => 0 }, "to" => { "stage" => "a", "minutes" => 0 } }, reports[4])
    assert_equal reports[4], reports[5], "an undone report goes again"
    assert_equal({ "stage" => "a", "minutes" => 2 }, reports[6]["to"], "a furthest further back keeps the stage")
    assert_equal({ "guide" => "clubs", "day" => "2026-10-08", "to_stage" => "a", "to_minutes" => "2", "from_stage" => "a", "from_minutes" => "0",
                   "first_source" => "clubs", "first_medium" => "", "first_campaign" => "", "last_source" => "clubs", "last_medium" => "", "last_campaign" => "" },
                 reports[7])
    assert_nil reports[8], "a stage the guide no longer has stops the journey"
    assert_nil reports[9], "no storage, no journey"
  end

  test "the login carries the touches, and a new account counts where it came from" do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: "ident!fresh", credentials: { token: "hca-fresh" },
      extra: { raw_info: { identity: { id: "ident!fresh", primary_email: "fresh@example.com", first_name: "Fresh", last_name: "Dev",
                                       verification_status: "verified", ysws_eligible: true } } }
    )
    Rails.application.credentials.define_singleton_method(:dig) { |*keys| keys == %i[hack_club client_id] ? "test-client" : options.dig(*keys) }
    clear_storage
    visit "/login?utm_source=Clubs&utm_medium=poster&utm_campaign=fall"
    click_on "log in with Hack Club"
    deadline = Time.current + 10
    sleep 0.2 until SignupSourceDay.exists? || Time.current > deadline
    assert_equal [ [ "clubs", "poster", "fall", "clubs", "poster", "fall", 1 ] ],
                 SignupSourceDay.pluck(:first_source, :first_medium, :first_campaign, :last_source, :last_medium, :last_campaign, :signups)
    assert User.exists?(hca_id: "ident!fresh")
  ensure
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:hack_club)
  end

  private

  # A page whose own arrival is already counted, then nothing kept: the
  # next capture is this browser's first.
  def clear_storage
    visit "/requirements"
    page.execute_script("localStorage.clear()")
  end

  # Calls a module from the import map: m is the module, and the code's value comes back.
  def module_call(name, code)
    result = page.evaluate_async_script(<<~JS, name)
      const done = arguments[arguments.length - 1]
      import(arguments[0]).then(m => done({ value: #{code} })).catch(error => done({ error: String(error) }))
    JS
    raise result["error"] if result["error"]
    result["value"]
  end

  def touch(path, referrer = "", first: false)
    module_call("attribution", "m.parseTouch({ href: 'https://#{HOST}#{path}', referrer: #{referrer.to_json}, host: '#{HOST}', first: #{first} })")
  end

  def apply(saved, touch, before: false)
    module_call("attribution", "m.applyTouch(#{saved.to_json}, #{touch.to_json}, { before: #{before} })")
  end

  # The page as an arrival at path from referrer, on this site's host.
  def capture(path, referrer = "")
    module_call("attribution", "m.capture(new URL('https://#{HOST}#{path}'), #{referrer.to_json})")
  end
end
