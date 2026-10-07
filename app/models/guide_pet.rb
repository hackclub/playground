# The pet the guide is about, its active pet: the one the participant set
# active, while it is still theirs. With none set, the newest pet that never
# shipped. A participant who shipped every pet starts a new one from the
# guide's Hackatime step. The set pet's id comes from the controller
# (ApplicationController#active_pet_id).
module GuidePet
  def self.for(user, active_id = nil) = active(user, active_id) || user.projects.where.missing(:ships).order(:created_at).last

  # The pet the guide's ship step and next step card are about: the guide's
  # pet, or with none, the pet that shipped last, which may wait on its
  # review or have new hours to ship again.
  def self.to_ship(user, active_id = nil) = self.for(user, active_id) || shipped_last(user)

  def self.shipped_last(user) = user.projects.joins(:ships).order("ships.created_at DESC").first

  def self.active(user, id) = id && user.projects.find_by(id:)
end
