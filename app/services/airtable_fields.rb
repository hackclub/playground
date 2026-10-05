# The field hash each Postgres row becomes in Airtable. Field names are the
# handbook's; Loops fields follow https://docs.hackclub.com/handbook/loops/loops-airtable-integration:
# timestamp fields named "Loops - playground<Event>At", camelCase, program prefix.
module AirtableFields
  module_function

  def user(u)
    first_ship = u.ships.minimum(:created_at)
    {
      "playground_id" => "user-#{u.id}",
      "Email" => u.email,
      "First Name" => u.first_name,
      "Last Name" => u.last_name,
      "Slack ID" => u.slack_id,
      "Hack Club Auth ID" => u.hca_id,
      "Verification Status" => u.verification_status,
      "YSWS Eligible" => u.ysws_eligible,
      "Banned" => u.banned?,
      # The welcome email in Loops fires when this goes from empty to set, so a
      # signup after the program ends leaves it empty and gets no welcome.
      "Loops - playgroundSignupAt" => (u.created_at.iso8601 if u.created_at < ProgramWindow.current.ends_at),
      "Loops - playgroundFirstShipAt" => first_ship&.iso8601,
      "Loops - playgroundFirstPetCreatedAt" => u.first_pet_created_at&.iso8601,
      # Text, not a time: see NoTimeNudge.
      "Loops - playgroundNoTimeNudge" => (NoTimeNudge::VALUE if u.no_time_nudge_at)
      # "Loops List - Playground" is a formula in the base that gives every row
      # the list id, and Airtable refuses a value for a computed field.
    }.compact
  end

  # Field names are the YSWS Project Submissions component's, read from the
  # base on 2026-09-23. The address and birthday come from Hack Club Auth at
  # sync time, so the app never stores them outside a redemption.
  def ship(s)
    identity = (HackClubAuth.for(s.user).identity rescue {})
    snap = s.snapshot
    just = Justification.new(s)
    {
      "playground_id" => "ship-#{s.id}",
      "Code URL" => snap["code_url"],
      "Playable URL" => snap["playable_url"],
      # Added to the base on 2026-09-29, not part of the component's fields.
      "Ship Message URL" => snap["ship_message_url"],
      "First Name" => s.user.first_name,
      "Last Name" => s.user.last_name,
      "Email" => s.user.email,
      # The cover only, until the Unified DB field is known to take several.
      "Screenshot" => snap["screenshot_url"].present? ? [ { "url" => snap["screenshot_url"] } ] : nil,
      "Description" => snap["description"],
      "GitHub Username" => snap["code_url"].to_s[%r{\Ahttps://github\.com/([\w-]+)/}, 1],
      **address(identity),
      "Birthday" => (identity["birthday"] || s.user.birthday)&.to_s,
      "Optional - Override Hours Spent" => (s.approved_seconds.to_i / 3600.0).round(2),
      "Optional - Override Hours Spent Justification" => just.to_s,
      "Justification - Hackatime Project Name(s) + Date Range(s)" => just.hackatime_projects,
      "Justification - Submitter Hackatime ID" => snap["hackatime_user_id"],
      "Justification - Specific Technical Features" => s.review_judgement,
      "Justification - Deflation Justification" => just.deflation,
      "Justification - Lapse Links, comma-separated" => Array(snap["lapses"]).map { it["url"] }.join(", ").presence
    }.compact
  end

  # The primary address in a Hack Club Auth identity, in the submission
  # table's field names, which the Users table shares.
  def address(identity)
    address = Array(identity["addresses"]).find { it["primary"] } || Array(identity["addresses"]).first || {}
    {
      "Address (Line 1)" => address["line_1"],
      "Address (Line 2)" => address["line_2"],
      "City" => address["city"],
      "State / Province" => address["state"],
      "Country" => address["country"],
      "ZIP / Postal Code" => address["postal_code"]
    }
  end

  # A user's address, read from Hack Club Auth with their token, or nil if
  # the read fails. A missing address clears the fields, so none goes stale.
  def user_address(u)
    address(HackClubAuth.for(u).identity).transform_values(&:to_s)
  rescue StandardError
    nil
  end

  def redemption(r)
    {
      "playground_id" => "redemption-#{r.id}",
      "Email" => r.user.email,
      "Goal" => r.goal&.name,
      "Status" => r.status,
      "Redeemed At" => r.created_at.iso8601,
      "Fulfilled At" => r.fulfilled_at&.iso8601,
      "Tracking" => r.tracking,
      "Loops - playgroundRedeemedAt" => r.created_at.iso8601,
      "Loops - playgroundFulfilledAt" => r.fulfilled_at&.iso8601
    }.compact
  end
end
