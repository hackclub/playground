# Where a browser came from, as its own script works it out and keeps it, in
# localStorage and nowhere else (attribution.js): a source, a medium, and a
# campaign. First touch is the first arrival this browser made, and last
# touch the latest arrival that was not direct. The server only ever sees
# them as part of an anonymous count, guide reading (GuideJourneyDay) or a
# new account (SignupSourceDay), and keeps them only as columns of a count.
#
# The values come from a browser, so anyone can send anything. Each one is
# cleaned the way the browser cleans it, then checked: the channels the
# browser names (CHANNELS) and the media it uses pass, as does a short value
# of lowercase letters, digits, dots, dashes and underscores, as a UTM tag
# or a referring site gives. Anything else is "other". So a flood of junk
# cannot grow the tables either: past DAILY_CAP distinct values a column
# already holds that day, a value the column has not seen that day is
# "other" too.
module TrafficSource
  Touch = Data.define(:source, :medium, :campaign)

  # The sources the browser names itself, and what each is called on the
  # admin stats. A referring site that is none of these is its own name,
  # such as news.ycombinator.com.
  NAMES = {
    "direct" => "direct", "slack" => "Slack", "search" => "search engines", "x" => "X", "github" => "GitHub",
    "discord" => "Discord", "youtube" => "YouTube", "email" => "email", "hack club site" => "the Hack Club site",
    "stardance" => "Stardance", "clubs" => "Clubs", "unknown" => "unknown, came before counting",
    "other" => "other"
  }.freeze
  CHANNELS = NAMES.keys.freeze
  MEDIA = %w[referral organic email].freeze
  KNOWN = (CHANNELS + MEDIA + [ "" ]).freeze

  OTHER = "other"
  UNKNOWN = Touch.new(source: "unknown", medium: "", campaign: "")
  MAX_LENGTH = 40
  PATTERN = /\A[a-z0-9][a-z0-9._-]{0,#{MAX_LENGTH - 1}}\z/
  DAILY_CAP = 40
  COLUMNS = %i[first_source first_medium first_campaign last_source last_medium last_campaign].freeze

  # Admin views show a source on its own only when at least this many
  # readers or signups came from it in the days shown. Fewer are folded into
  # "other", so a link made for one person does not show that person.
  mattr_accessor :min_shown, default: 3

  # One value as the browser cleans it: trimmed, lowercased, spaces as
  # dashes. Then one the server keeps, or "other". A source is never blank.
  def self.clean(value, source: false)
    text = value.is_a?(String) ? value.strip.downcase : ""
    return (source ? OTHER : "") if text.empty?
    return text if KNOWN.include?(text)
    text = text.gsub(/\s+/, "-")
    PATTERN.match?(text) ? text : OTHER
  end

  # A touch from the parameters prefix_source, prefix_medium and
  # prefix_campaign, or unknown with no source.
  def self.touch(params, prefix)
    params = params.to_h.stringify_keys
    return UNKNOWN if params["#{prefix}_source"].blank?
    Touch.new(source: clean(params["#{prefix}_source"], source: true), medium: clean(params["#{prefix}_medium"]),
              campaign: clean(params["#{prefix}_campaign"]))
  end

  # The first and last touch from a browser's parameters.
  def self.touches(params) = { first: touch(params, "first"), last: touch(params, "last") }

  # The columns for a count in model on day, past the daily cap: a value the
  # column has not seen that day is "other" once the column holds DAILY_CAP
  # values of its own that day.
  def self.columns(model, day:, first:, last:)
    values = { first_source: first.source, first_medium: first.medium, first_campaign: first.campaign,
               last_source: last.source, last_medium: last.medium, last_campaign: last.campaign }
    scope = model.where(day:)
    values.to_h do |column, value|
      next [ column, value ] if KNOWN.include?(value) || scope.exists?(column => value)
      [ column, scope.where.not(column => KNOWN).distinct.count(column) < DAILY_CAP ? value : OTHER ]
    end
  end

  def self.name(source) = NAMES.fetch(source, source)
end
