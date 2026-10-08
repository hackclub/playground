require "application_system_test_case"

# The meter beside the guide in a real browser. The tag with the total rides
# the top of the fill, and its line takes the pixel row a goal's tick would
# take. The tag stays inside the bar's height at either end, and nothing in
# the meter makes the column beside the guide scroll sideways.
class NewSiteMeterSystemTest < ApplicationSystemTestCase
  include NewSiteTests

  setup do
    visit dev_login_path(as: "participant")
    assert_selector "#guide"
    @user = User.find_by!(hca_id: "ident!dev-participant")
    @admin = User.create!(hca_id: "ident!meter-admin", admin: true)
  end

  test "the tag sits at the top of the fill, on a goal's own row, and inside the bar at either end" do
    { 0 => "0m", 119 => "1h 59m", 120 => "2h", 600 => "10h", 840 => "14h" }.each do |minutes, total|
      give_hours(approved: minutes.minutes)
      visit guide_path
      assert_selector ".vmeter-now-tag", exact_text: total
      at = meter_layout
      message = "at #{total}"

      assert_in_delta at["bar"]["right"], at["line"]["left"], 0.01, "#{message}, the line starts at the bar"
      assert_operator at["tag"]["top"], :>=, at["bar"]["top"] - 0.01, message
      assert_operator at["tag"]["bottom"], :<=, at["bar"]["bottom"] + 0.01, message
      assert_operator at["tag"]["right"], :<=, at["meter"]["right"] + 0.01, "#{message}, the tag stays in its lane"
      assert_equal at["column"]["clientWidth"], at["column"]["scrollWidth"], "#{message}, the column never scrolls sideways"

      sticker, _, shirt = at["ticks"]
      case minutes
      when 0
        assert_in_delta at["bar"]["bottom"], at["line"]["bottom"], 0.01, "the line lies on the bar's bottom edge"
        assert_in_delta at["bar"]["bottom"], at["tag"]["bottom"], 0.01, "the tag stops at the bottom of the bar"
      when 119
        assert_in_delta sticker["top"] + 1, at["line"]["top"], 0.01, "a minute short, the line sits just under the 2h tick"
      when 120
        assert_in_delta sticker["top"], at["line"]["top"], 0.01, "on 2h, the line takes the tick's row"
      else
        assert_in_delta at["bar"]["top"], shirt["top"], 0.01, "the shirt's tick is the bar's top border"
        assert_in_delta at["bar"]["top"], at["line"]["top"], 0.01, "the line lies on the top border"
        assert_in_delta at["bar"]["top"], at["tag"]["top"], 0.01, "the tag stops at the top of the bar"
      end
    end
  end

  test "a reached prize turns dark green with a drawn check, and the hours it reached show only once" do
    give_hours(approved: 2.hours + 30.minutes, unshipped: 3.hours)
    visit guide_path
    assert_selector ".vmeter-now-tag", exact_text: "5h 30m"
    assert_selector ".vmeter-tick.reached", count: 1
    # The hidden word is for a screen reader, which hears the check that way.
    assert_selector ".vmeter-goals li.reached", count: 1, text: /stickersheet\s+reached,\s+2h · redeem/
    assert_selector ".vmeter-goals li:not(.reached)", text: /playground keychain\s+5h · ship to redeem/
    reached = page.evaluate_script(<<~JS)
      (() => {
        const li = document.querySelector(".vmeter-goals li.reached")
        const check = getComputedStyle(li.querySelector(".goal-hours"), "::before")
        return { name: getComputedStyle(li.querySelector("strong")).color, tick: getComputedStyle(document.querySelector(".vmeter-tick.reached")).backgroundColor,
                 check: check.content, mask: check.maskImage || check.webkitMaskImage }
      })()
    JS
    assert_equal "rgb(47, 125, 58)", reached["name"]
    assert_equal "rgb(47, 125, 58)", reached["tick"]
    assert_equal '""', reached["check"]
    assert_includes reached["mask"], "data:image/svg+xml"
  end

  test "the tag says how the total splits on hover" do
    give_hours(approved: 3.hours, pending: 1.hour, unshipped: 2.hours)
    visit guide_path
    find(".vmeter-now-tag", exact_text: "6h").hover
    tip = page.evaluate_script("getComputedStyle(document.querySelector('.vmeter-now-tag'), '::after').content")
    assert_equal '"3h approved\a 1h pending\a 2h unshipped"', tip
  end

  private
    # Gives the participant exactly these hours in each stage, each on a pet
    # of its own. The tracked time counts as fresh, so the hub does not ask
    # Hackatime again.
    def give_hours(approved: 0, pending: 0, unshipped: 0)
      @user.ships.destroy_all
      @user.projects.destroy_all
      if approved.positive?
        ship = pet("approved pet", approved).ships.create!(user: @user, claimed_seconds: approved)
        ship.approve_review!(by: @admin, seconds: approved, judgement: "ok", feedback: nil)
        ship.pass_fraud!(by: @admin)
      end
      pet("pending pet", pending).ships.create!(user: @user, claimed_seconds: pending) if pending.positive?
      pet("unshipped pet", unshipped) if unshipped.positive?
    end

    def pet(name, seconds) = @user.projects.create!(name:, tracked_seconds: seconds, tracked_at: Time.current)

    def meter_layout
      page.evaluate_script(<<~JS)
        (() => {
          const box = el => { const b = el.getBoundingClientRect(); return { top: b.top, bottom: b.bottom, left: b.left, right: b.right } }
          const column = document.querySelector(".hub-right")
          return { bar: box(document.querySelector(".vmeter-bar")), meter: box(document.querySelector(".vmeter")),
                   line: box(document.querySelector(".vmeter-now-line")), tag: box(document.querySelector(".vmeter-now-tag")),
                   ticks: [...document.querySelectorAll(".vmeter-tick")].map(box),
                   column: { scrollWidth: column.scrollWidth, clientWidth: column.clientWidth } }
        })()
      JS
    end
end
