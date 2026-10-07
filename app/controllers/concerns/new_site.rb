# The new site, without the desktop: the landing, the guide in steps with the
# next step and the hours beside it, and my pets. It is behind a flag on each
# user, users.new_site, which only an admin turns on, from the admin's page
# for that user (Admin::PeopleController#new_site). Everyone else, and every
# signed-out visitor, gets the desktop site, unchanged.
#
# The gate sits in three places:
# - routes: the new site's own addresses sit in a constraint (NewSite.request?),
#   so for anyone else they do not exist and answer 404.
# - views: a flagged request asks for the new_site variant, so the new
#   templates, such as projects/edit.html+new_site.erb and the layout
#   layouts/app.html+new_site.erb, render in place of the old ones. A request
#   without the flag never matches a +new_site template.
# - controllers: where a page does something else on the new site, it asks
#   new_site?.
module NewSite
  extend ActiveSupport::Concern

  # Tests only: signed-out visitors get the new site too, so its signed-out
  # pages can be tested before it opens to everyone. Nothing in a request
  # can set it.
  mattr_accessor :for_visitors, default: false

  def self.for?(user) = user ? user.new_site? : for_visitors

  # For the routes' constraint, before any controller runs: the same signed-in
  # user that ApplicationController#current_user finds.
  def self.request?(request)
    session = request.session
    user = session[:user_id] && User.find_by(id: session[:user_id])
    user = nil unless user && session[:session_version].to_i == user.session_version
    for?(user)
  end

  included do
    helper_method :new_site?, :active_pet_id, :active_pet
    before_action { request.variant = :new_site if new_site? }
  end

  private

  def new_site? = NewSite.for?(current_user)

  # A controller of the new site's own answers 404 to anyone else, as the
  # routes do. It guards a route left out of the constraint by mistake.
  def require_new_site
    raise ActionController::RoutingError, "not found" unless new_site?
  end

  # The pet the participant set active, which the guide's pet steps and the
  # next step card act on (GuidePet). A cookie keeps it with its owner's id,
  # so it outlasts a log out, and another login in the same browser ignores
  # it. A pet since deleted falls back to the guide's own choice.
  def active_pet_id
    user_id, pet_id = cookies.signed[:active_pet].to_s.split(":").map(&:to_i)
    pet_id if current_user && user_id == current_user.id && pet_id.to_i.positive?
  end

  # The pet the guide acts on now, set or not, for a page that marks it.
  def active_pet = current_user && GuidePet.to_ship(current_user, active_pet_id)

  def remember_active_pet(pet)
    cookies.permanent.signed[:active_pet] = { value: "#{pet.user_id}:#{pet.id}", httponly: true, same_site: :lax }
  end

  # Where a login or a Hackatime link begun at a guide step goes back to:
  # that step in the guide. Anything else gives nil, so no other address can
  # steer a login.
  def guide_return(value) = GuidePage.way_back(value)
end
