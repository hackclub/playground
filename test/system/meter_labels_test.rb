require "application_system_test_case"

# The meter labels each goal with its hours, as "2h stickers". At any width
# ship.exe can take, the labels keep their hours, stay apart, stay inside the
# bar's ends, and clear the legend below, reached goals' wider labels too. In
# the legend, each square stays on its label's line, just left of it, however
# the legend wraps.
class MeterLabelsTest < ApplicationSystemTestCase
  test "each goal's label shows its hours, in ship.exe and on its own" do
    log_in_as "participant"
    within_frame(find(".ship-frame")) { assert_goal_labels }

    resize_browser_to(390, 844) do
      visit dashboard_path
      assert_goal_labels
    end
  end

  test "the labels never collide, down to the narrowest ship.exe" do
    log_in_as "participant"
    assert_no_collisions [ 330, 260, 200 ]
  end

  test "a reached goal's tick and label turn green, with a check and a paper edge" do
    approve log_in_as("participant"), Goal.find("stickers").hours + 1
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) do
      assert_selector ".goal-mark.reached", count: 1, exact_text: "2h stickers"
      reached, unreached = %w[stickers keychain].map do |key|
        page.evaluate_script(<<~JS, key)
          (mark => {
            const style = getComputedStyle(mark), check = getComputedStyle(mark.querySelector(".goal-hours"), "::before")
            return [style.color, style.borderLeftColor, style.filter.includes("drop-shadow"), check.content, check.width, check.backgroundColor]
          })([...document.querySelectorAll(".goal-mark")].find(mark => mark.querySelector(".goal-name").textContent === arguments[0]))
        JS
      end
      green = "rgb(47, 125, 58)"
      assert_equal [ green, green, true, '""', "9.59375px", green ], reached
      assert_equal [ "rgb(43, 58, 77)", "rgb(43, 58, 77)", false, "none", "auto" ], unreached.first(5)
      assert_match(/Reached: 2h stickers\z/, find(".meter")["aria-label"])
    end
  end

  test "reached labels never collide either, down to the narrowest ship.exe" do
    approve log_in_as("participant"), Goal.all.last.hours
    visit root_path(open: "goal")
    within_frame(find(".ship-frame")) { assert_selector ".goal-mark.reached", count: Goal.all.size }
    assert_no_collisions [ 400, 340, 330, 300, 260, 230, 200 ]
  end

  private
    # Approves this many hours for a new pet of the user's. The tracked time
    # counts as fresh, so the dashboard does not ask Hackatime again.
    def approve(user, hours)
      admin = User.create!(hca_id: "ident!meter-labels-admin", admin: true)
      project = user.projects.create!(name: "labels pet", tracked_seconds: hours * 3600, tracked_at: Time.current)
      ship = project.ships.create!(user:, claimed_seconds: hours * 3600)
      ship.approve_review!(by: admin, seconds: hours * 3600, judgement: "ok", feedback: nil)
      ship.pass_fraud!(by: admin)
    end

    # Narrows ship.exe to each width in turn and checks the labels there.
    def assert_no_collisions(widths)
      widths.each do |width|
        page.execute_script("document.getElementById('window-goal.exe').style.width = arguments[0]", "#{width}px")
        within_frame(find(".ship-frame")) do
          problems = nil
          page.document.synchronize do
            problems = label_problems
            raise Capybara::ExpectationNotMet if problems.any?
          end
        rescue Capybara::ExpectationNotMet
          flunk "at a #{width}px ship.exe: #{problems.join(", ")}"
        end
      end
    end

    def assert_goal_labels
      Goal.all.each { |goal| assert_selector ".goal-mark", exact_text: "#{goal.hours}h #{goal.key}" }
      assert_empty label_problems
    end

    # What is wrong with the labels as drawn: a label without its hours, two
    # labels that touch, one past an end of the bar, one over the legend, or a
    # legend square away from its own label.
    def label_problems
      page.evaluate_script(<<~JS, Goal.all.map(&:hours))
        (hours => {
          const meter = document.querySelector(".meter"), bar = meter.getBoundingClientRect()
          const legend = meter.nextElementSibling.getBoundingClientRect()
          const labels = [...meter.querySelectorAll(".goal-mark")].map(mark => {
            const range = document.createRange()
            range.selectNodeContents(mark)
            // The hours' own box holds a reached goal's check, which the range skips.
            const boxes = [...range.getClientRects(), mark.querySelector(".goal-hours").getBoundingClientRect()].filter(box => box.width > 0)
            return { text: mark.innerText.trim(), left: Math.min(...boxes.map(b => b.left)),
                     right: Math.max(...boxes.map(b => b.right)), bottom: Math.max(...boxes.map(b => b.bottom)) }
          })
          const problems = []
          labels.forEach((label, i) => {
            if (!label.text.startsWith(`${hours[i]}h`)) problems.push(`"${label.text}" lacks ${hours[i]}h`)
            if (i > 0 && label.left < labels[i - 1].right + 4) problems.push(`"${labels[i - 1].text}" touches "${label.text}"`)
            if (label.bottom > legend.top) problems.push(`"${label.text}" covers the legend`)
          })
          if (labels[0].left < bar.left) problems.push("the first label passes the bar's left end")
          if (labels.at(-1).right > bar.right) problems.push("the last label passes the bar's right end")
          const keys = [...document.querySelectorAll(".legend .key")]
          keys.forEach((key, i) => {
            const range = document.createRange(), end = keys[i + 1]
            range.setStartAfter(key)
            end ? range.setEndBefore(end) : range.setEnd(key.parentNode, key.parentNode.childNodes.length)
            const text = range.toString().trim(), line = [...range.getClientRects()].find(box => box.width > 1)
            const square = key.getBoundingClientRect(), middle = (square.top + square.bottom) / 2
            if (middle < line.top || middle > line.bottom) problems.push(`the square for "${text}" is not on its line`)
            if (square.right > line.left || line.left - square.right > 10) problems.push(`the square for "${text}" is not just left of it`)
          })
          if (document.documentElement.scrollWidth > document.documentElement.clientWidth) problems.push("the page scrolls sideways")
          return problems
        })(arguments[0])
      JS
    end
end
