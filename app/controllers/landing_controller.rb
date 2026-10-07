# froppii's playground page, ported from github.com/froppii/playground at
# 01d6c09 (2026-04-13). Markup, CSS, and script are kept as close to the
# original as possible. On the new site (NewSite) the landing has no desktop.
class LandingController < ApplicationController
  layout -> { new_site? ? "app" : "landing" }

  # A signed-in participant's pets are icons on the desktop.
  def show
    return new_site_landing if new_site?
    @pets = current_user&.projects&.order(:id)&.map(&:desktop_icon)
  end

  private

  # The new site's landing. ship.exe's address, /?open=goal, which a login
  # and a Hackatime link return to, is the guide there.
  def new_site_landing
    return render("home/show") unless params[:open].in?(%w[goal ship])
    flash.keep
    redirect_to guide_path
  end
end
