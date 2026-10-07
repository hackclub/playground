require "test_helper"

# The NPS section of the admin stats page, on a few answers worked out by
# hand. Times are UTC, and Eastern time is UTC-4. It is noon Eastern on
# Wednesday October 7.
class AdminNpsTest < ActionDispatch::IntegrationTest
  NOW = Time.utc(2026, 10, 7, 16)

  setup do
    travel_to NOW
    @admin = log_in("admin")
  end

  test "NPS for the last 7 days, its groups, each day's NPS with its n, and the latest answers" do
    ann, ben, cat = %w[ann ben cat].map { person(it) }
    pet = cat.projects.create!(name: "pebble")
    # Monday October 5: ann a detractor. Tuesday: ben a passive. Today: ann
    # changes her mind, and cat answers at ship.
    answer(ann, 4, at: Time.utc(2026, 10, 5, 14), doing_well: "the stickers", improve: "the guide is long")
    answer(ben, 7, at: Time.utc(2026, 10, 6, 14), doing_well: "the guide", improve: "faster reviews")
    answer(ann, 9, at: Time.utc(2026, 10, 7, 13), doing_well: "the new videos", improve: "nothing", anything_else: "thanks!")
    answer(cat, 10, at: Time.utc(2026, 10, 7, 15), doing_well: "reviews", improve: "more merch", source: "ship", project: pet)
    answer(@admin, 0, at: Time.utc(2026, 10, 7, 15), doing_well: "x", improve: "y")

    get admin_stats_path
    assert_response :ok
    assert_select "section#nps" do
      assert_select "h2", "how likely are people to recommend playground?"
      # Promoters ann and cat, passive ben: 67% minus 0%.
      assert_select ".nps-headline .big", "+67"
      assert_select ".nps-groups tr", 4
      assert_equal [ "promoters, 9 or 10", "2", "67%" ], texts(".nps-groups tr:nth-child(1) td")
      assert_equal [ "passives, 7 or 8", "1", "33%" ], texts(".nps-groups tr:nth-child(2) td")
      assert_equal [ "detractors, 0 to 6", "0", "0%" ], texts(".nps-groups tr:nth-child(3) td")
      assert_equal [ "people who answered", "3", "" ], texts(".nps-groups tr.total td")

      # From the first answer's day to today: October 5, 6, and 7.
      assert_equal %w[5 6 7], texts(".nps-chart .labels td")
      assert_equal %w[-100 -50 +67], texts(".nps-chart .values td")
      assert_equal %w[n=1 n=2 n=3], texts(".nps-chart .ns td")
      assert_select ".nps-chart .down .fill", 2
      assert_select ".nps-chart .up .fill[style='--h: 0.67']", 1

      # Newest first, admins left out, each with its score, person, and source.
      assert_equal [ "score", "person", "when", "from", "doing well", "improve", "anything else" ], texts(".nps-answers th")
      rows = css_select(".nps-answers tr").drop(1).map { |row| row.css("td").map { it.text.squish } }
      assert_equal [
        [ "10", "cat", "Wed Oct 7, 11:00am", "ship (pebble)", "reviews", "more merch", "" ],
        [ "9", "ann", "Wed Oct 7, 9:00am", "nps.exe", "the new videos", "nothing", "thanks!" ],
        [ "7", "ben", "Tue Oct 6, 10:00am", "nps.exe", "the guide", "faster reviews", "" ],
        [ "4", "ann", "Mon Oct 5, 10:00am", "nps.exe", "the stickers", "the guide is long", "" ]
      ], rows
      assert_select ".nps-answers tr:nth-child(2) a[href='#{admin_person_path(cat)}']", "cat"
      assert_select ".nps-answers tr:nth-child(2) .nps-pill.promoter", "10"
      assert_select ".nps-answers tr:nth-child(4) .nps-pill.passive", "7"
      assert_select ".nps-answers tr:last-child .nps-pill.detractor", "4"
    end
  end

  test "with no answers the section says so in a line" do
    get admin_stats_path
    assert_select "section#nps .nps-chart", 0
    assert_select "section#nps p.muted", /nobody has answered yet/
  end

  test "answers older than the 7 days leave the last 7 days without an NPS" do
    answer(person("ann"), 10, at: NOW - 9.days, doing_well: "a", improve: "b")
    get admin_stats_path
    assert_select ".nps-headline .big", "—"
    assert_select "section#nps", /nobody answered in the last 7 days/
    assert_select ".nps-chart .labels td", 10
  end

  test "the section follows the people active each day, before where people drop out" do
    get admin_stats_path
    headings = css_select("section.panel > h2").map(&:text)
    assert_equal [ "how many hours, in which stage?", "how many people are active each day?", "how likely are people to recommend playground?",
                   "where do people drop out?" ], headings.first(4)
  end

  private

  # Each element's text, squished, in the section.
  def texts(selector) = css_select("section#nps #{selector}").map { it.text.squish }

  def person(name)
    User.create!(hca_id: "ident!#{name}", email: "#{name}@example.com", display_name: name, display_name_source: "generated")
  end

  def answer(user, score, at:, doing_well:, improve:, anything_else: nil, source: "daily", project: nil)
    NpsResponse.create!(user:, score:, doing_well:, improve:, anything_else:, source:, project:, created_at: at)
  end
end
