module AdminHelper
  STAGE_BADGES = { "awaiting_review" => "pending", "awaiting_fraud" => "on_hold" }.freeze

  def stage_badge(ship)
    label = Ship::STAGES.fetch(ship.stage)
    label += " (banned)" if ship.stage == "rejected" && ship.fraud_status == "banned"
    tag.span(label, class: "badge badge-#{STAGE_BADGES.fetch(ship.stage, ship.stage)}")
  end

  # A ship's pet name as reviewers see it: an admin's correction, else the pet's.
  def ship_name(ship) = ShipSnapshot.name_of(ship)
end
