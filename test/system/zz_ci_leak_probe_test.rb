require "application_system_test_case"
require_relative "desktop_icons_test"

# Diagnostic only, removed before merge. Each pair runs the selected-icon
# test, which opens guide.txt as a visitor and ends, and then reads the
# site's storage as the next test starts. Odd pairs stop the old page from
# writing storage before the reset leaves it. Nothing here fails.
class ZzCiLeakProbeTest < DesktopIconsTest
  i_suck_and_my_tests_are_order_dependent!

  PAIRS = 40
  SELECTED = :"test_a_selected_icon_shows_as_on_XP,_a_blue_fill_behind_its_label_and_a_tint_on_its_picture,_and_every_label_is_outlined"

  def self.runnable_methods = (1..PAIRS).flat_map { |i| [ format("test_%02d_a", i), format("test_%02d_b", i) ] }

  (1..PAIRS).each do |i|
    define_method(format("test_%02d_a", i)) do
      send(SELECTED)
      @guard = i.odd?
    end

    define_method(format("test_%02d_b", i)) do
      browser = page.driver.browser
      browser.navigate.to("#{Capybara.current_session.server.base_url}/up")
      keys = browser.execute_script("return Object.keys(localStorage).sort()")
      state = browser.execute_script("return localStorage.getItem('playground-window-state:visitor')")
      browser.navigate.to("about:blank")
      puts "\nLEAKPROBE pair=#{i} guard=#{i.odd?} keys=#{keys.inspect} state=#{state.to_s[0, 200]}"
      assert true
    end
  end

  def before_teardown
    super
  ensure
    if @guard
      page.execute_script(<<~JS)
        (function silence(view) {
          try { view.Storage.prototype.setItem = function () {} } catch (error) {}
          for (let i = 0; i < view.frames.length; i++) silence(view.frames[i])
        })(window)
      JS
    end
  end
end
