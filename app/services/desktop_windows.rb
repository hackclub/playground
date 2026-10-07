# Which desktop window each page of the site belongs to. Each window has one
# job: ship.exe shows the dashboard and the steps that start there, login.exe
# the login's first step, guide.txt the guide, requirements.txt the
# submission requirements, a pet's window shows that
# pet's page and its edit page, a ship window shows that pet's checks, and a
# redeem window a goal's shipping form.
# landing.js reads this table, and a link, a redirect, or
# a save that would load a page in another window's frame opens that window
# on the page instead. A page that never shows in a window is listed apart,
# and a test fails for a page on neither list.
module DesktopWindows
  # Each page by its controller and action, and the kind of window it
  # belongs to. Each kind has an entry in landing.js's windowKinds.
  PAGES = {
    "dashboard#show" => "goal",
    "sessions#new" => "login",
    "guides#show" => "guide",
    "requirements#show" => "requirements",
    # A pet has no window until it exists, so it is made from ship.exe.
    "projects#new" => "goal",
    "redemptions#new" => "redeem",
    "nps_responses#show" => "nps",
    "projects#show" => "pet",
    "projects#edit" => "pet",
    "projects#checks" => "ship"
  }.freeze

  # Pages no desktop window shows. The desktop itself and the login's later
  # steps load in the top window. The trash's delete popups have a frame of
  # their own. The pet list is JSON for the desktop, not a page. The new
  # site (NewSite) has no desktop: its guide's frames and its delete page
  # show in no window. Nor do Stardance's and the clubs' guides (SideGuide),
  # which have no desktop.
  ELSEWHERE = %w[landing#show sessions#create sessions#failure sessions#hackatime_step sessions#dev
                 projects#trash projects#index guide_steps#check guide_steps#side guide_steps#ship projects#delete
                 side_guides#show].freeze

  # Each page's path for landing.js, as the router writes it: /projects/:id/edit.
  def self.pages
    PAGES.map { |page, kind| { kind:, path: path_of(page) } }
  end

  def self.path_of(page)
    controller, action = page.split("#")
    route = Rails.application.routes.routes.find do
      it.verb == "GET" && it.defaults[:controller] == controller && it.defaults[:action] == action
    end
    route.path.spec.to_s.delete_suffix("(.:format)")
  end
end
