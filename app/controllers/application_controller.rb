class ApplicationController < ActionController::Base
  # Safari 16.4 is the first Safari with import maps, and every script on the
  # site loads through one. The other minimums are Rails' :modern set.
  SAFARI_MINIMUM = "16.4"
  CHROME_MINIMUM = 120
  allow_browser versions: { safari: SAFARI_MINIMUM, chrome: CHROME_MINIMUM, firefox: 121, opera: 106, ie: false },
                unless: %i[chrome_on_ios? chrome_engine_opera? link_preview?]
  before_action :refuse_old_chrome_on_ios, if: :chrome_on_ios?
  before_action :refuse_old_chrome_engine_opera, if: :chrome_engine_opera?

  helper_method :current_user
  include NewSite

  private

  # Every iOS browser runs Safari's engine. The others report a Safari or iOS
  # version, but Chrome on iOS reports Chrome's, so its iOS version decides.
  def chrome_on_ios? = request.user_agent.to_s.include?(" CriOS/")

  # A link preview reads the page's tags and runs none of its scripts. Apple's
  # Messages app fetches one as Safari 9 with the Facebook crawler's name on
  # the end, so that name passes the gate.
  def link_preview? = request.user_agent.to_s.include?("facebookexternalhit")

  # Opera on Chrome's engine adds "OPR/" to Chrome's user agent. Opera for
  # Android numbers its versions apart from desktop Opera, so its Opera 102
  # runs Chrome 152. The Chrome version decides, as it does for Chrome.
  def chrome_engine_opera? = request.user_agent.to_s.include?(" OPR/")

  def refuse_old_chrome_on_ios
    ios = request.user_agent[/ OS (\d+(?:_\d+)*) like Mac OS X/, 1]
    return if ios.nil? || Gem::Version.new(ios.tr("_", ".")) >= Gem::Version.new(SAFARI_MINIMUM)
    refuse_browser
  end

  def refuse_old_chrome_engine_opera
    chrome = request.user_agent[%r{ Chrome/(\d+)\.}, 1]
    refuse_browser unless chrome && chrome.to_i >= CHROME_MINIMUM
  end

  def refuse_browser
    render file: Rails.root.join("public/406-unsupported-browser.html"), layout: false, status: :not_acceptable
  end

  # A login counts while its session carries the account's session version.
  # Every response sets the session cookie again, so one still on its way at
  # log out brings the old cookie back. Log out moves the version on, and the
  # old cookie then signs no one in.
  def current_user
    return @current_user if defined?(@current_user)
    user = session[:user_id] && User.find_by(id: session[:user_id])
    @current_user = (user if user && session[:session_version].to_i == user.session_version)
  end

  def sign_in(user)
    session[:user_id] = user.id
    session[:session_version] = user.session_version
  end

  # A page goes to the login, which says why. A request for data, such as the
  # desktop's pet list after the login ended, gets a 401 and no message: it
  # shows no page, so the message would wait for the next page, unasked for.
  def require_login
    return if current_user
    return head(:unauthorized) unless request.formats.include?(Mime[:html])
    redirect_to login_path, alert: "log in first"
  end

  def require_admin
    head :not_found unless current_user&.acts_as_admin?
  end
end
