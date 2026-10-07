# The new site, without the desktop: the landing, the guide in steps with the
# next step and the hours beside it, and my pets. It is behind a flag on each
# user, users.new_site. An account made at signup from LAUNCHED_ON on starts
# with it on (SessionsController). For an older account only an admin turns
# it on, and an admin can turn it off for anyone, from the admin's page for
# that user (Admin::PeopleController#new_site). Older accounts without the
# flag get the desktop site, unchanged. Signed-out visitors get the new site.
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
#
# A user with the flag can switch one browser back to the old desktop, from
# the new site's footer (ClassicController). A signed cookie, classic, keeps
# that browser on the old desktop, and new_site? is false there. The flag
# stays as it is, and a desktop icon switches back.
module NewSite
  extend ActiveSupport::Concern

  # Signed-out visitors get the new site. Tests of the old desktop can turn
  # this off; nothing in a request can set it.
  mattr_accessor :for_visitors, default: true

  # The day, in Eastern time, from which a new account starts on the new
  # site. Accounts made before it knew the old desktop, so the new landing's
  # FAQ tells them where it went.
  LAUNCHED_ON = Date.new(2026, 10, 7)

  def self.for?(user) = user ? user.new_site? : for_visitors

  # This browser switched back to the old desktop. Only a signed-in user's
  # requests honor the preference; signed-out visitors still get the new site.
  def self.classic?(cookies) = cookies.signed[:classic] == "1"

  # For the routes' constraints, before any controller runs: the same
  # signed-in user that ApplicationController#current_user finds.
  def self.request?(request)
    user = signed_in(request)
    for?(user) && (!user || !classic?(request.cookie_jar))
  end

  # A user with the flag, whichever site this browser shows them.
  def self.flagged?(request) = signed_in(request)&.new_site? || false

  def self.signed_in(request)
    session = request.session
    user = session[:user_id] && User.find_by(id: session[:user_id])
    user if user && session[:session_version].to_i == user.session_version
  end

  included do
    helper_method :new_site?, :active_pet_id, :active_pet, :back_to_new_site?, :knew_the_desktop?
    before_action { request.variant = :new_site if new_site? }
  end

  private

  def new_site? = NewSite.for?(current_user) && (!current_user || !NewSite.classic?(cookies))

  # The old desktop shows a way back to the new site only to a user with the
  # flag who switched this browser to the old desktop.
  def back_to_new_site? = current_user&.new_site? && NewSite.classic?(cookies)

  # The new landing's FAQ says where the desktop went to an account made
  # before the new site was the default, by the day in Eastern time.
  def knew_the_desktop? = current_user.present? && current_user.created_at.in_time_zone(ProgramWindow::ZONE).to_date < NewSite::LAUNCHED_ON

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
