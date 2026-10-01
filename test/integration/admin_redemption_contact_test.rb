require "test_helper"

# The fulfillment page's "ship to": the parcel's address first, whose "copy
# all" copies only the address, then the ways to reach the participant, each
# with a copy button and a key of its own. Both stay hidden until the
# address is revealed, and each reveal is logged.
class AdminRedemptionContactTest < ActionDispatch::IntegrationTest
  ADDRESS = { "first_name" => "Sam", "last_name" => "Rock", "line_1" => "15 Falls Road", "line_2" => "Flat 2", "city" => "Burlington",
              "state" => "VT", "postal_code" => "05401", "country" => "US", "phone_number" => "+1 802 555 0100" }.freeze

  setup do
    @user = User.create!(hca_id: "ident!contact", email: "sam@example.com", slack_id: "U0SAMROCK", verification_status: "verified", ysws_eligible: true)
    @admin = log_in("admin")
  end

  test "before the reveal, neither the address nor the contact details show, and the reveal is logged" do
    r = @user.redemptions.create!(goal_key: "stickers", address: ADDRESS)
    get admin_redemption_path(r)
    assert_select "table.address, table.contact", 0
    assert_no_match "+1 802 555 0100", response.body
    assert_no_match "U0SAMROCK", response.body
    assert_select "[data-shortcut=e], [data-shortcut=m], [data-shortcut=k]", 0
    assert_select "aside", /sam@example.com/, "the participant panel still shows the email"

    post reveal_admin_redemption_path(r)
    assert AuditEvent.exists?(actor: @admin, subject: r, action: "address.reveal")
    assert_select "table.address"
    assert_select "table.contact"
  end

  test "copy all copies the address alone, and each contact detail has its own copy button and key" do
    r = @user.redemptions.create!(goal_key: "stickers", address: ADDRESS)
    post reveal_admin_redemption_path(r)

    assert_equal [ "name", "line 1", "line 2", "city", "state", "postal code", "country" ], css_select("table.address td.muted").map(&:text)
    all = css_select("button[data-shortcut=y]").sole
    assert_equal "Sam Rock\n15 Falls Road\nFlat 2\nBurlington\nVT\n05401\nUS", all["data-copy"]
    [ "sam@example.com", "+1 802 555 0100", "U0SAMROCK" ].each { refute_includes all["data-copy"], it }

    contact = css_select("table.contact tr").map do |row|
      button = row.at_css("button")
      [ row.at_css("td.muted").text, button["data-copy"], button["data-shortcut"], row.at_css("kbd").text ]
    end
    assert_equal [ [ "email", "sam@example.com", "e", "e" ], [ "phone", "+1 802 555 0100", "m", "m" ], [ "Slack ID", "U0SAMROCK", "k", "k" ] ], contact
    assert_select "table.address [data-shortcut]", 0, "the address lines have buttons only"

    keys = css_select("[data-shortcut]").map { it["data-shortcut"] }
    assert_equal keys.uniq, keys, "no key does two things on the page"
  end

  test "without a phone, a second line, or a Slack ID, their rows are left out" do
    @user.update!(slack_id: nil)
    r = @user.redemptions.create!(goal_key: "stickers", address: ADDRESS.except("line_2", "phone_number"))
    post reveal_admin_redemption_path(r)
    assert_equal [ "name", "line 1", "city", "state", "postal code", "country" ], css_select("table.address td.muted").map(&:text)
    assert_equal "Sam Rock\n15 Falls Road\nBurlington\nVT\n05401\nUS", css_select("button[data-shortcut=y]").sole["data-copy"]
    assert_equal [ "email" ], css_select("table.contact td.muted").map(&:text)
    assert_select "[data-shortcut=m], [data-shortcut=k]", 0
  end

  test "the contact keys mean nothing else on any admin page" do
    views = Dir[Rails.root.join("app/views/{admin/**/*,layouts/admin}.html.erb")]
    assert_operator views.size, :>, 5
    %w[e m k].each do |key|
      using = views.select { File.read(it).match?(/shortcut(?:="|: ")#{key}"/) }
      assert_empty using, "#{key} is taken on #{using.map { File.basename(it) }.join(", ")}"
    end
  end
end
