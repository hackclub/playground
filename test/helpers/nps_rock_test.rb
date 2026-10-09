require "test_helper"

# Who the new site's rock asks: the same people, at the same times, as
# nps.exe opens for by itself on the old desktop. That is a participant with
# a minute of Hackatime time and no answer in the last 12 hours. A page
# that asks already shows no rock, and the rock is placed once a page.
class NpsRockTest < ActionView::TestCase
  helper NpsHelper
  include NpsHelper

  def current_user = @viewer
  helper_method :current_user

  setup do
    NpsResponse.asking = true
    @viewer = User.create!(hca_id: "ident!ann", email: "ann@example.com", display_name: "ann", display_name_source: "generated")
    CodingHour.create!(user: @viewer, hour: 1.day.ago.beginning_of_hour, seconds: 60)
  end

  test "a participant with a minute of Hackatime time and no answer in 12 hours sees the rock" do
    assert nps_rock?
    NpsResponse.create!(user: @viewer, score: 8, doing_well: "the guide", improve: "more pets", source: "daily", created_at: 11.hours.ago)
    assert_not nps_rock?, "answered in the last 12 hours"
    NpsResponse.update_all(created_at: 13.hours.ago)
    assert nps_rock?, "answered 13 hours ago"
  end

  test "a newcomer with no time, an admin, a banned person, and nobody never see it" do
    CodingHour.where(user: @viewer).update_all(seconds: 59)
    assert_not nps_rock?, "59 seconds"
    CodingHour.where(user: @viewer).update_all(seconds: 3600)
    @viewer.update!(admin: true)
    assert_not nps_rock?, "an admin"
    @viewer.update!(admin: false, banned_at: Time.current)
    assert_not nps_rock?, "banned"
    @viewer = nil
    assert_not nps_rock?, "signed out"
  end

  test "a page that asks already shows no rock" do
    content_for :no_nps_rock, true
    assert_not nps_rock?
  end

  test "the rock is placed once a page, with the questions under ids of their own" do
    html = nps_rock
    assert_includes html, "nps-rock"
    assert_includes html, %(id="nps_rock_score_0")
    assert_includes html, %(for="nps_rock_doing_well")
    assert_not_includes html, %(id="nps_response_)
    assert_includes html, %(data-nps-rock-store-value="playground-nps-asked:#{@viewer.id}")
    assert_nil nps_rock
  end
end
