require "test_helper"

# The submission requirements: a page for anyone, listing what a pet needs.
class RequirementsTest < ActionDispatch::IntegrationTest
  test "anyone can read the requirements, with the link to #playground-ships" do
    get requirements_path
    assert_response :ok
    assert_select "h1", "submission requirements"
    assert_select ".requirements-list li", 9
    assert_select "a[href='https://hackclub.slack.com/archives/C0C51NCK1DG']", "#playground-ships"
    assert_match "no AI art please", response.body
    assert_match "up to 30% of your approved time", response.body
  end
end
