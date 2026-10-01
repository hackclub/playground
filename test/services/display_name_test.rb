require "test_helper"

# Display names: Slack display name, else a generated two-part name. Never the real
# name, never the email.
class DisplayNameTest < ActiveSupport::TestCase
  test "no Slack gives a generated two-part name that stays put" do
    user = User.create!(hca_id: "ident!dn1", first_name: "Realname", email: "real.person@example.com")
    name = user.display_name
    adjective, critter = name.split(" ")
    assert_includes DisplayName::ADJECTIVES, adjective
    assert_includes DisplayName::CRITTERS, critter
    refute_match(/realname|real\.person/i, name)
    assert_equal name, user.reload.display_name
    assert_equal "generated", user.display_name_source
  end

  test "a Slack display name wins, and an 'Unknown' one from Cachet is ignored" do
    user = User.new(hca_id: "ident!dn2", slack_id: "U123")
    DisplayName.singleton_class.alias_method(:real_slack_name, :slack_name)
    DisplayName.define_singleton_method(:slack_name) { |_id| "froppii" }
    DisplayName.assign(user)
    assert_equal [ "froppii", "slack" ], [ user.display_name, user.display_name_source ]
  ensure
    DisplayName.singleton_class.alias_method(:slack_name, :real_slack_name)
  end
end
