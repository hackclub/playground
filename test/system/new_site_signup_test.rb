require "application_system_test_case"

# A signup in a real browser, through Hack Club Auth and Hackatime in
# OmniAuth's test mode: a new account ends on the new site's guide, and an
# account from before the new site ends on the desktop.
class NewSiteSignupSystemTest < ApplicationSystemTestCase
  setup do
    OmniAuth.config.test_mode = true
    ENV["REAL_SERVICES"] = "1"
    OmniAuth.config.mock_auth[:hackatime] = OmniAuth::AuthHash.new(provider: "hackatime", credentials: { token: "hka-new" })
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:hack_club)
    OmniAuth.config.mock_auth.delete(:hackatime)
    ENV.delete("REAL_SERVICES")
  end

  test "a new account goes through Hackatime to the new site's guide" do
    sign_up("ident!brand-new")
    assert_selector "body.new-site #guide h1", text: "Build a desktop pet in Godot"
    assert_no_selector "#welcome"
    assert User.find_by!(hca_id: "ident!brand-new").new_site?
  end

  test "an account from before the new site goes through Hackatime to the desktop" do
    User.create!(hca_id: "ident!before")
    sign_up("ident!before")
    assert_selector "#welcome"
    assert_no_selector "body.new-site"
    assert_not User.find_by!(hca_id: "ident!before").new_site?
  end

  private

  # The login's button needs a Hack Club Auth app, which the tests may not
  # have, so the page posts the same request itself.
  def sign_up(id)
    OmniAuth.config.mock_auth[:hack_club] = OmniAuth::AuthHash.new(
      provider: "hack_club", uid: id, credentials: { token: "hca-#{id}" },
      extra: { raw_info: { identity: { id:, primary_email: "#{id.delete_prefix("ident!")}@example.com", first_name: "Sam",
                                       last_name: "Dev", verification_status: "verified", ysws_eligible: true } } }
    )
    visit login_path
    page.execute_script(<<~JS)
      const form = Object.assign(document.createElement("form"), { method: "post", action: "/auth/hack_club" })
      document.body.append(form)
      form.submit()
    JS
  end
end
