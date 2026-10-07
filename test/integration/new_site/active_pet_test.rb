require "test_helper"

# A participant with two pets or more sets the active pet, the one the
# guide's pick step, its Ship it step, and the next step card act on, from a
# switch in each. With none set, or a set pet since deleted, the guide picks
# the newest pet that never shipped. A new pet becomes the active pet, and a
# ship keeps it.
class NewSiteActivePetTest < ActionDispatch::IntegrationTest
  include NewSiteTests
  READY = { description: "a rock that walks along your taskbar", code_url: "https://github.com/pet/rock",
            ship_message_url: "https://hackclub.slack.com/archives/C0C51NCK1DG/p1759012345678901", playable_url: "https://pet.itch.io/rock",
            screenshots: [ { "id" => "shot", "key" => "shot.webp", "url" => "https://playground.hackclub-assets.com/shot.webp" } ] }.freeze

  setup do
    @user = log_in("participant")
    post dev_hackatime_path
    @rock = @user.projects.create!(name: "rock", hackatime_projects: [ "rock-pet" ])
  end

  test "with one pet, no part of the guide offers to switch pets" do
    get guide_check_path(frame: "pick-step")
    assert_select "#pick-step .guide-do-title", /\AHackatime counts rock/
    assert_select ".pet-switch", 0
    get guide_ship_path
    assert_select ".pet-switch", 0
    get guide_side_path(part: "next")
    assert_select "#hub-next #next-title", /rock/
    assert_select ".pet-switch", 0
    get "/guide/move"
    assert_select ".pet-switch", 0
  end

  test "with two pets, the pick step, the Ship it step, and the next step card name the active pet and switch it in place" do
    pebble = @user.projects.create!(name: "pebble")
    # Unset, the guide is about the newest pet that never shipped.
    assert_equal %w[pebble pebble pebble], switch_names
    assert_select "#hub-next #next-title", "link pebble to Hackatime"
    get guide_check_path(frame: "pick-step")
    assert_select ".pet-switch .pet-switch-current[aria-current=true]", /\Apebble/
    assert_select ".pet-switch form[action=?][data-turbo-frame=pick-step] button", active_pet_path, "rock"
    assert_select ".pet-switch form input[name=pet_id][value=?]", @rock.id.to_s
    assert_select ".pet-switch form input[name=origin][value=?]", "/guide/scene#pick-step"

    # From the pick step: it draws its frame again, which tells the others.
    patch active_pet_path, params: { pet_id: @rock.id }, headers: { "Turbo-Frame" => "pick-step" }
    assert_redirected_to guide_check_path(frame: "pick-step")
    follow_redirect!
    assert_select "turbo-frame#pick-step .pet-switch[data-active-pet-just-set-value=true] summary strong", "rock"
    assert_select "#pick-step .guide-do-title", /\AHackatime counts rock/
    assert_equal %w[rock rock rock], switch_names
    assert_select "#hub-next #next-title", "ship rock"
    assert_select ".pet-switch[data-active-pet-just-set-value=true]", 0

    # From the Ship it step, and from the next step card.
    patch active_pet_path, params: { pet_id: pebble.id }, headers: { "Turbo-Frame" => "ship-step" }
    assert_redirected_to guide_ship_path
    follow_redirect!
    assert_select "turbo-frame#ship-step .pet-switch[data-active-pet-just-set-value=true] summary strong", "pebble"
    assert_select "#ship-step a[href=?]", "/guide/scene#pick-project"
    patch active_pet_path, params: { pet_id: @rock.id }, headers: { "Turbo-Frame" => "hub-next" }
    assert_redirected_to guide_side_path(part: "next")
    follow_redirect!
    assert_select "turbo-frame#hub-next .pet-switch[data-active-pet-just-set-value=true] summary strong", "rock"
    assert_equal %w[rock rock rock], switch_names
  end

  test "without scripts, a switch goes back to its part of the guide, and only to the guide" do
    @user.projects.create!(name: "pebble")
    patch active_pet_path, params: { pet_id: @rock.id, origin: "/guide/scene#pick-step" }
    assert_redirected_to "/guide/scene#pick-step"
    assert_nil flash[:active_pet_set]
    patch active_pet_path, params: { pet_id: @rock.id, origin: "https://example.com/#pick-step" }
    assert_redirected_to guide_path
    get "/guide/move"
    assert_select "#hub-next .pet-switch form input[name=origin][value=?]", "/guide/move#hub-next"
  end

  test "the pick step links a Hackatime project to the active pet" do
    pebble = @user.projects.create!(name: "pebble")
    patch active_pet_path, params: { pet_id: @rock.id }
    post guide_link_path, params: { name: "rock-pet-art", frame: "pick-step" }
    assert_equal %w[rock-pet rock-pet-art], @rock.reload.hackatime_projects
    assert_empty pebble.reload.hackatime_projects
  end

  test "a deleted active pet, or one another login set in this browser, falls back to the newest pet that never shipped" do
    @user.projects.create!(name: "pebble")
    patch active_pet_path, params: { pet_id: @rock.id }
    assert_equal %w[rock rock rock], switch_names
    @rock.destroy!
    @user.projects.create!(name: "twig")
    assert_equal %w[twig twig twig], switch_names

    # Another participant in the same browser keeps their own guide, and
    # cannot set a pet that is not theirs.
    twig_id = @user.projects.find_by!(name: "twig").id
    patch active_pet_path, params: { pet_id: twig_id }
    newbie = log_in("newbie")
    post dev_hackatime_path
    newbie.projects.create!(name: "older")
    newbie.projects.create!(name: "newer")
    get guide_check_path(frame: "pick-step")
    assert_select ".pet-switch summary strong", "newer"
    patch active_pet_path, params: { pet_id: twig_id }
    assert_response :not_found
  end

  test "a new pet becomes the active pet, and a ship keeps the pet that shipped" do
    pebble = @user.projects.create!(name: "pebble")
    patch active_pet_path, params: { pet_id: pebble.id }
    post projects_path, params: { project: { name: "twig" } }
    assert_equal %w[twig twig twig], switch_names

    # Unset, the newest pet that never shipped is rock. Once it ships, the
    # guide stays on it rather than moving on to pebble.
    cookies.delete(:active_pet)
    @user.projects.where.not(id: [ @rock.id, pebble.id ]).destroy_all
    @rock.update!(READY.merge(created_at: 1.minute.from_now))
    assert_equal %w[rock rock rock], switch_names
    post ship_project_path(@rock), params: { from: "guide" }
    assert @rock.ships.sole.pending?
    get guide_ship_path
    assert_select "#ship-step .guide-do-title", "rock is in review"
    assert_equal %w[rock rock rock], switch_names
    assert_select "#hub-next #next-title", "rock is in review"
  end

  private

  # The pet each part of the guide names: the pick step, the Ship it step,
  # and the next step card, in that order. The card's response is left for
  # the caller to check.
  def switch_names
    %w[pick ship next].map do |part|
      case part
      when "pick" then get guide_check_path(frame: "pick-step")
      when "ship" then get guide_ship_path
      when "next" then get guide_side_path(part: "next")
      end
      css_select(".pet-switch summary strong").first&.text
    end
  end
end
