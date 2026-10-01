# The name playground calls someone: their Slack display name from Cachet, Hack Club's public Slack profile service. With no Slack
# name, a generated two-part name like "curious cat", kept once assigned.
# Never the person's real name, and never built from their email.
module DisplayName
  CACHET = "https://cachet.hackclub.com/users"

  ADJECTIVES = %w[
    curious playful sleepy bouncy cozy sneaky fluffy tiny brave gentle zippy wiggly
    cheerful quiet sparkly dizzy nimble jolly snug fuzzy chirpy mellow peppy plucky
    shy speedy wobbly dreamy giddy lucky merry perky silly sunny toasty witty
  ].freeze

  CRITTERS = %w[
    cat critter frog goose fox otter hamster bunny duck owl pup ferret gecko hedgehog
    axolotl capybara penguin panda raccoon squirrel turtle koala moth bee newt quokka
    lemur mole seal crab snail badger yak llama
  ].freeze

  module_function

  def generate = "#{ADJECTIVES.sample} #{CRITTERS.sample}"

  # Sets display_name and display_name_source on the user, without saving.
  def assign(user)
    slack = slack_name(user.slack_id)
    if slack
      user.display_name = slack
      user.display_name_source = "slack"
    elsif user.read_attribute(:display_name).blank? || user.display_name_source == "slack"
      user.display_name = generate
      user.display_name_source = "generated"
    end
    user
  end

  def slack_name(slack_id)
    return if slack_id.blank? || FakeServices.on?
    name = HttpJson.get("#{CACHET}/#{CGI.escape(slack_id)}", timeout: 5)["displayName"].to_s.strip
    name.presence unless name.casecmp?("unknown")
  rescue HttpJson::Error, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, JSON::ParserError
    nil
  end
end
