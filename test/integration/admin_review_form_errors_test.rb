require "test_helper"

# A refused review verdict names the box by its label and keeps what the
# admin typed.
class AdminReviewFormErrorsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = log_in("admin")
    @user = User.create!(hca_id: "ident!rf", first_name: "Sam")
    @ship = @user.projects.create!(name: "pet").ships.create!(user: @user, claimed_seconds: 7200)
  end

  test "reject without the box names it and keeps the typed values" do
    post review_admin_ship_path(@ship), params: { verdict: "reject", judgement: "", feedback: "no tray menu yet", deflation_reason: "afk", notes: "n", approved_hours: "1.5" }
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /"specific technical features"/
    assert_select "textarea[name=feedback]", text: "no tray menu yet"
    assert_select "textarea[name=deflation_reason]", text: "afk"
    assert_select "textarea[name=notes]", text: "n"
    assert_select "input[name=approved_hours][value=?]", "1.5"
    assert_equal "pending", @ship.reload.review_status
  end

  test "approve without the box names it" do
    post review_admin_ship_path(@ship), params: { verdict: "approve", judgement: "", feedback: "great", approved_hours: "1" }
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /"specific technical features"/
    assert_select "textarea[name=feedback]", text: "great"
  end

  test "changes without a note names the box and keeps the judgement" do
    post review_admin_ship_path(@ship), params: { verdict: "changes", judgement: "a save file", feedback: "" }
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /"note to the participant"/
    assert_select "textarea[name=judgement]", text: "a save file"
  end

  test "a fraud deduction without notes names the box and keeps the hours" do
    @ship.approve_review!(by: @admin, seconds: 3600, art_seconds: 0, judgement: "fine", feedback: nil, deflation_reason: "afk")
    post fraud_admin_ship_path(@ship), params: { verdict: "deduct", deduct_hours: "0.5", notes: "" }
    assert_response :unprocessable_entity
    assert_select ".flash.alert", text: /"notes"/
    assert_select "input[name=deduct_hours][value=?]", "0.5"
  end
end
