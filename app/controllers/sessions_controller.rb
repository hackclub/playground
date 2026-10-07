# Login is Hack Club Auth, then Hackatime: a participant with no Hackatime
# token goes on to Hackatime's OAuth before the desktop. The login starts on
# its own page, which the desktop shows as login.exe. Tokens are stored
# encrypted. Read identity fields from extra.raw_info["identity"]: the OmniAuth
# info hash omits ysws_eligible, addresses, and birthday.
class SessionsController < ApplicationController
  layout "app"
  skip_forgery_protection only: :failure
  before_action :require_login, only: :hackatime_step

  # The login's first step. Signed in, the desktop opens on ship.exe instead.
  def new
    redirect_to root_path(open: "goal") if current_user
  end

  def create
    auth = request.env["omniauth.auth"]
    case auth&.provider
    when "hack_club" then hack_club(auth)
    when "hackatime" then hackatime(auth)
    else redirect_to login_path, alert: "login did not finish: unknown error"
    end
  end

  # OmniAuth calls this with the failed strategy in the env. The /auth/failure
  # route passes the same in params. A Hackatime failure or a declined consent
  # keeps the participant logged in, and the dashboard offers the link again.
  def failure
    provider = request.env["omniauth.error.strategy"]&.name || params[:strategy]
    # Only OmniAuth's error keys, such as access_denied, are shown.
    reason = (request.env["omniauth.error.type"] || params[:message]).to_s[/\A[a-z_]{1,40}\z/]
    if provider.to_s == "hackatime" && current_user
      redirect_to root_path(open: "goal"), alert: "Hackatime did not link#{" (#{reason})" if reason}. your coding time counts once it's linked."
    else
      redirect_to login_path, alert: "login did not finish: #{reason || "unknown error"}"
    end
  end

  # Log out ends the login on every device, including any copy of its cookie.
  def destroy
    current_user&.increment!(:session_version)
    reset_session
    redirect_to root_path
  end

  # The step between the two logins. Its form posts to Hackatime's OAuth, as
  # the request phase must be a POST with the CSRF token, and submits itself.
  # The session flag means it starts only straight after a login, never from
  # a link or a reload.
  def hackatime_step
    started = session.delete(:hackatime_step)
    redirect_to root_path(open: "goal") if !started || current_user.hackatime_connected?
  end

  # Development only: log in as a fake participant or admin, so the whole
  # flow can be driven without OAuth apps. Not routed in production. Like a
  # real login it goes on to (fake) Hackatime. deny=1 declines that step.
  # A newbie's fake Hackatime has no projects until the new site's guide
  # sends heartbeats for one.
  def dev
    raise ActionController::RoutingError, "not found" unless FakeServices.on?
    kind = params[:as].presence_in(%w[participant newbie unverified admin froppii red]) || "participant"
    user = User.find_or_create_by!(hca_id: "ident!dev-#{kind}") do |u|
      u.email = "#{kind}@example.com"
      u.first_name = kind.capitalize
      u.last_name = "Dev"
      u.verification_status = kind == "unverified" ? "needs_submission" : "verified"
      u.ysws_eligible = kind != "unverified"
      u.admin = kind.in?(%w[admin froppii])
    end
    sign_in(user)
    back = guide_return(params[:origin]) if NewSite.for?(user)
    redirect_to back || (params[:admin] ? admin_root_path : after_login_path(user, deny: params[:deny].presence))
  end

  private

  def hack_club(auth)
    identity = auth.extra.raw_info.fetch("identity")
    user = User.find_or_initialize_by(hca_id: identity.fetch("id"))
    user.assign_identity(identity)
    if user.new_record? && identity["verification_status"] == "ineligible"
      return redirect_to login_path, alert: "Hack Club says this account can't join programs like playground."
    end
    # Organizers are admins by email (ADMIN_EMAILS, comma separated), and stop
    # being admins when their email leaves the list.
    user.admin = user.admin_email? if User.admin_emails.any?
    DisplayName.assign(user)
    user.hca_access_token = auth.credentials.token
    user.hca_refresh_token = auth.credentials.refresh_token if auth.credentials.refresh_token
    user.save!
    SlackInviteJob.perform_later(user.id) if user.slack_id.present? && user.slack_invited_at.nil?
    # On the new site, a login begun at a guide step goes back to it. The
    # guide links Hackatime at its own step, so the login skips that one.
    back = guide_return(request.env["omniauth.origin"]) if NewSite.for?(user)
    reset_session
    sign_in(user)
    redirect_to back || after_login_path(user)
  end

  def hackatime(auth)
    return redirect_to login_path, alert: "log in first" unless current_user
    current_user.update!(hackatime_access_token: auth.credentials.token)
    back = guide_return(request.env["omniauth.origin"]) if new_site?
    redirect_to back || root_path(open: "goal")
  end

  # The desktop with ship.exe open, or first the Hackatime step when there
  # is no token yet.
  def after_login_path(user, **query)
    return root_path(open: "goal") if user.hackatime_connected?
    session[:hackatime_step] = true
    hackatime_step_path(query.compact)
  end
end
