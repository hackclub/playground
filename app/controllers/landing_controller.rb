# froppii's playground page, ported from github.com/froppii/playground at
# 01d6c09 (2026-04-13). Markup, CSS, and script are kept as close to the
# original as possible.
class LandingController < ApplicationController
  layout "landing"

  # A signed-in participant's pets are icons on the desktop.
  def show
    @pets = current_user&.projects&.order(:id)&.map(&:desktop_icon)
  end
end
