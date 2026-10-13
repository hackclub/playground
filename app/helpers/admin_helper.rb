module AdminHelper
  # A ship's pet name as reviewers see it: an admin's correction, else the pet's.
  def ship_name(ship) = ShipSnapshot.name_of(ship)
end
