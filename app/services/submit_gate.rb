# The checks that run before a human sees a ship.
# A blocker stops the submit button. A warning goes to the reviewer. The rule
# for which is which: certain and fixable by the participant is a blocker, a
# judgement call is a warning.
class SubmitGate
  Check = Data.define(:key, :label, :level, :ok, :detail) do
    def blocker? = level == :blocker
    def failed? = ok == false
  end

  def initialize(project, stats: nil)
    @project = project
    @user = project.user
    @stats = stats
  end

  MIN_DESCRIPTION = 20
  # How a check that could not run starts its detail.
  UNCHECKED = "could not check".freeze

  # Each label says what must be true, and the ship list shows only that. A
  # failed check's detail says what is wrong.
  #
  # The code may live anywhere that loads publicly. A GitHub repository also
  # gets its README and its commits checked. Code anywhere else skips those
  # two, and a reviewer looks at it by hand.
  def checks
    @checks ||= [
      check(:eligible, "your identity needs to be verified, and your account eligible", :blocker,
            fix: "verify your identity at auth.hackclub.com, then reload this page") { owner_eligible? },
      check(:not_banned, "your account needs to be unbanned", :blocker, fix: "ask in #playground") { !@user.banned? },
      check(:hackatime, "Hackatime needs to be linked", :blocker, fix: "link it on your dashboard") { @user.hackatime_connected? },
      check(:hackatime_link, "your Hackatime link needs to work", :blocker, fix: Hackatime::UNLINKED) { !@user.hackatime_unlinked },
      check(:trust, "your Hackatime account needs to be in good standing", :blocker,
            fix: "Hackatime has banned this account, so its hours can't count") { !@user.hackatime_red? },
      check(:name, "your pet needs a name", :blocker, fix: "add one with edit") { @project.name.present? },
      check(:description, "your pet needs a description", :blocker, fix: "add one with edit") { described? },
      check(:description_length, "the description needs at least #{MIN_DESCRIPTION} characters", :blocker,
            fix: "yours is #{description.length}. say a bit more about what your pet does") { long_enough? },
      check(:hackatime_projects, "your pet needs a Hackatime project", :blocker,
            fix: "pick this pet's Hackatime projects with edit") { hackatime_projects? },
      check(:new_hours, "your pet needs new hours to ship", :blocker, fix: new_hours_fix) { @project.unshipped_seconds.positive? },
      check(:not_pending, "your last ship needs its review first", :blocker) { !@project.pending_ship? },
      check(:repo, "your pet needs a link to its code", :blocker, fix: repo_fix) { code_ok? },
      check(:readme, "the repository needs a README", :blocker) { !github? || repo&.readme },
      check(:playable, "the shipped link needs to work", :blocker, fix: playable_fix) { playable_ok? },
      check(:playable_host, "the shipped link needs to go to a page where someone can experience your pet", :warning) { itch_or_blank? },
      check(:screenshot, "your pet needs a screenshot", :blocker, fix: "add one with edit") { screenshot? },
      check(:ship_message, "you need to link your ship message in #playground-ships", :blocker,
            fix: ship_message_fix) { ship_message? },
      check(:commits, "the repository should have more than one commit", :warning) { !github? || (repo && repo.commits > 1) }
    ]
  end

  def blockers = checks.select { it.blocker? && !it.ok }
  def warnings = checks.select { !it.blocker? && it.failed? }
  def passed? = blockers.empty?

  # The checks above that can be judged from the stored account and pet
  # alone, each with its rule. For the code and playable links that is only
  # that they are filled in, since whether they load takes the network. The
  # admin stats count unshipped pets by these.
  OFFLINE = { eligible: :owner_eligible?, description: :described?, description_length: :long_enough?,
              hackatime_projects: :hackatime_projects?, repo: :code_link?, playable: :playable_link?,
              screenshot: :screenshot? }.freeze

  # The keys of the offline checks this pet fails. Makes no network call.
  def unmet_offline = OFFLINE.filter_map { |key, rule| key unless send(rule) }

  def repo
    return @repo if defined?(@repo)
    @repo = @project.github_repo && Github.repo(@project.github_repo)
  end

  def release
    return @release if defined?(@release)
    @release = Github.release_for(@project.playable_url)
  end

  private

  def check(key, label, level, fix: nil)
    ok = yield
    Check.new(key:, label:, level:, ok: ok ? true : false, detail: ok ? nil : (detail_for(key) || fix))
  rescue HttpJson::Error, SocketError, Timeout::Error, SystemCallError, IOError, Net::HTTPBadResponse, Net::ProtocolError,
         OpenSSL::SSL::SSLError => e
    Check.new(key:, label:, level:, ok: false, detail: "#{UNCHECKED}: #{e.message.first(80)}")
  end

  def description = @project.description.to_s.strip

  def owner_eligible? = @user.eligible?
  def described? = description.present?
  # Only judged once there is a description, so a missing one fails once.
  def long_enough? = description.blank? || description.length >= MIN_DESCRIPTION
  def hackatime_projects? = @project.hackatime_projects.any?
  def code_link? = @project.code_url.present?
  def playable_link? = @project.playable_url.present?
  def screenshot? = @project.screenshots.any?

  # itch.io is where the requirements ask for the pet. Another link may still
  # be a page where someone can try it, so this only warns. An empty link
  # passes, since the shipped link check already asks for one.
  def itch_or_blank?
    return true unless playable_link?
    host = URI(@project.playable_url).host.to_s.downcase
    host == "itch.io" || host.end_with?(".itch.io")
  rescue URI::InvalidURIError
    false
  end
  def ship_message? = @project.ship_message_url.to_s.match?(Project::SHIP_MESSAGE_LINK)

  def ship_message_fix
    return "post about your pet in #playground-ships, then add the link to your message" if @project.ship_message_url.blank?
    "that isn't a link to a message in #playground-ships"
  end

  def new_hours_fix
    return "link a Hackatime project first" if @project.hackatime_projects.empty?
    "no new Hackatime time on the linked projects since your last ship"
  end

  def repo_fix
    return "add a link to your pet's code with edit" if @project.code_url.blank?
    return "the link didn't load publicly" unless github?
    return "that isn't a link to a GitHub repository" unless @project.github_repo
    "the repository is private or doesn't exist"
  end

  # Any link on github.com is judged as GitHub, so it must be a repository.
  def github?
    URI(@project.code_url.to_s).host.to_s.downcase.in?(%w[github.com www.github.com])
  rescue URI::InvalidURIError
    false
  end

  def code_ok?
    return false unless code_link?
    return repo && !repo.private if github?
    status_ok?(@project.code_url)
  end

  def playable_fix
    return "add the link people use to get your pet, with edit" if @project.playable_url.blank?
    "the link didn't load publicly"
  end

  def detail_for(key)
    case key
    when :playable
      if release then release.assets.empty? ? "the release has no installer or executable, only source code" : "#{release.assets.size} file(s) in #{release.tag}"
      end
    end
  end

  # A GitHub release must carry an installer or executable; source-only
  # releases do not count (handbook, what makes a project shipped). Any other
  # link must load publicly.
  def playable_ok?
    return false unless playable_link?
    return release.assets.any? if release
    status_ok?(@project.playable_url)
  end


  # The participant chose the URL, so it may only reach public addresses.
  def status_ok?(url)
    HttpJson.request(:head, url, public_only: true)
    true
  rescue HttpJson::Error => e
    e.status.in?([ 403, 405 ]) ? HttpJson.request(:get, url, public_only: true).present? : false
  end
end
