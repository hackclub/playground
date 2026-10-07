# A user with the new site on (NewSite) switches this browser to the old
# desktop, and back. The new site's footer and its landing's FAQ ask first in
# a small window, or without scripts on this page. A signed cookie keeps the
# browser on the old desktop. The user's flag stays as it is, and an icon on
# the old desktop switches back.
class ClassicController < ApplicationController
  layout "app"
  before_action :require_login

  # The question, as a page of its own. Already on the old desktop, there is
  # nothing to ask.
  def show
    redirect_to root_path unless new_site?
  end

  def create
    cookies.permanent.signed[:classic] = { value: "1", httponly: true, same_site: :lax }
    redirect_to root_path
  end

  def destroy
    cookies.delete(:classic)
    redirect_to root_path
  end
end
