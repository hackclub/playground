require "test_helper"

# Shipping addresses, phones, the admin people search, and OAuth codes stay
# out of the log. Other fields that only share a word stay readable.
class LogFilterTest < ActiveSupport::TestCase
  test "personal details and OAuth codes are filtered, and a pet's code link is not" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    logged = filter.filter("shipping" => { "line_1" => "15 Falls Road", "phone_number" => "+1 802 555 0100" },
                           "q" => "sam@example.com", "code" => "oauth-code", "state" => "oauth-state",
                           "project" => { "code_url" => "https://github.com/pet/rock", "name" => "rock" })
    assert_equal "[FILTERED]", logged["shipping"]
    assert_equal %w[[FILTERED]] * 3, logged.values_at("q", "code", "state")
    assert_equal({ "code_url" => "https://github.com/pet/rock", "name" => "rock" }, logged["project"])
  end
end
