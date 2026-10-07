require "application_system_test_case"

# The guide keeps the reader's place in this browser: its bare address opens
# at the step read last, a link to a step or to a part of one opens where it
# says, and each guide, the new site's, Stardance's, and the clubs', keeps
# its own. The next step card never sends the reader back behind the
# furthest step they read, unless the account needs something there, and
# then it says why.
class NewSiteGuidePlaceSystemTest < ApplicationSystemTestCase
  include NewSiteTests

  test "the bare address opens at the step read last, and a link to a step or a part of one opens where it says" do
    visit guide_page_path("move")
    assert_selector ".outline-step > a[aria-current=page]", text: "Make it move"
    visit guide_path
    assert_current_path "/guide/move"
    assert_selector ".outline-step > a[aria-current=page]", text: "Make it move"

    # A link to a step wins, and makes it the step read last. The first
    # step is the bare address's own.
    visit guide_page_path("setup")
    assert_current_path "/guide/setup"
    visit guide_path
    assert_current_path "/guide"
    assert_selector ".outline-step > a[aria-current=page]", text: "Set up"

    # So does a link to a part of a step, old or new.
    visit guide_page_path("art")
    visit "/guide#movement"
    assert_current_path "/guide/move"
    visit guide_page_path("animate", anchor: "drag")
    assert_current_path "/guide/animate"
    assert_selector ".outline-step > a[aria-current=page]", text: "Animate and drag"
  end

  test "each guide keeps its own place" do
    visit "/stardance/art"
    visit "/clubs"
    assert_current_path "/clubs"
    visit "/stardance"
    assert_current_path "/stardance/art"
    visit guide_page_path("animate")
    visit "/clubs/move"
    visit guide_path
    assert_current_path "/guide/animate"
    visit "/clubs"
    assert_current_path "/clubs/move"
  end

  test "before Hackatime, the card goes on with the guide, and once past the pick it goes back to it, saying why" do
    visit dev_login_path(as: "newbie")
    assert_selector "#guide"
    # The development login links fake Hackatime: unlink it.
    User.find_by!(hca_id: "ident!dev-newbie").update!(hackatime_access_token: nil)
    visit guide_page_path("setup")
    # The card hides while its part of the guide is on screen.
    card "start the guide", "go to: Set up Godot", "/guide/setup#setup-godot", visible: :all

    # Read on to Build the scene: the card goes on, and there it has nowhere to go.
    visit guide_page_path("scene")
    assert_selector "#hub-next #next-title", visible: :all, text: "continue the guide"
    assert_selector "#hub-next a.btn", visible: :all, count: 0
    visit guide_page_path("setup")
    card "continue the guide", "continue: Build the scene", "/guide/scene"

    # Past the pick without connecting Hackatime, the card goes back to it.
    visit guide_page_path("animate")
    card "connect Hackatime", "go to: Pick your pet's project", "/guide/scene#pick-project"
  end

  test "a pet that counts hours keeps building from the furthest step read, and a pet that does not goes back to the pick" do
    user = User.find_by!(hca_id: "ident!dev-participant")
    user.update!(hackatime_access_token: "fake")
    visit dev_login_path(as: "participant")
    pet = user.projects.create!(name: "rock", hackatime_projects: [ "rock-pet-art" ])

    visit guide_page_path("scene")
    card "keep building rock", "continue: Art and script", "/guide/art"
    visit guide_page_path("animate")
    assert_selector "#hub-next #next-title", text: "keep building rock"
    assert_selector "#hub-next a.btn", count: 0
    visit guide_page_path("scene")
    card "keep building rock", "continue: Animate and drag", "/guide/animate"
    assert_no_text "back to the guide"

    # Its Hackatime project unlinked, the pet counts no hours: back to the pick.
    pet.update!(hackatime_projects: [])
    visit guide_page_path("move")
    card "link rock to Hackatime", "go to: Pick your pet's project", "/guide/scene#pick-project"
  end

  private

  def card(title, action, href, visible: true)
    assert_selector "#hub-next #next-title", visible:, text: title
    assert_selector "#hub-next a.btn[href='#{href}']", visible:, exact_text: action
  end
end
