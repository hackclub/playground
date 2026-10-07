# Hackatime, through the participant's own OAuth token.
# Docs: https://docs.hackclub.com/handbook/public-infrastructure/hackatime/integrating-hackatime-with-your-ysws. Never add
# project times together: Hackatime counts overlap once only when asked for
# several projects in one request through filter_by_project.
class Hackatime
  SITE = "https://hackatime.hackclub.com"
  Project = Data.define(:name, :total_seconds, :most_recent_heartbeat)
  Stats = Data.define(:total_seconds, :projects, :trust_level, :user_id)
  Span = Data.define(:start_time, :end_time)

  # Hackatime answers 401 or 404 when it no longer takes the participant's
  # token: they revoked it, or their account's API access is restricted.
  # Linking again gets a new token. The stored one is kept.
  class Unlinked < HttpJson::Error; end
  UNLINKED = "Hackatime can't see your account through this link.".freeze

  # Hackatime's placeholder for the last project a participant worked on. It
  # is not a project of theirs, so the site never lists, links or counts it.
  IGNORED_PROJECTS = [ "<<LAST_PROJECT>>" ].freeze

  def self.ignored?(name) = IGNORED_PROJECTS.any? { it.casecmp?(name.to_s.strip) }

  # The names with the ignored ones left out.
  def self.keep(names) = Array(names).reject { ignored?(it) }

  def self.for(user) = FakeServices.on? ? Fake.new(user) : new(user.hackatime_access_token)

  # Both endpoints take start_date and end_date as ISO 8601 times with an
  # offset. Stats count heartbeats from start_date to just before end_date;
  # the project list also takes one exactly at end_date.
  def self.range(window) = { start_date: window.starts_at.iso8601, end_date: window.ends_at.iso8601 }

  def initialize(token)
    @token = token
  end

  # Every project with time inside the window, most recent heartbeat first.
  # The totals count only that time.
  def projects(window = ProgramWindow.current)
    body = get("#{SITE}/api/v1/authenticated/projects?#{self.class.range(window).to_query}")
    body.fetch("projects").reject { it["archived"] || self.class.ignored?(it["name"]) }.map do |p|
      Project.new(name: p["name"], total_seconds: p["total_seconds"].to_i,
                  most_recent_heartbeat: p["most_recent_heartbeat"] && Time.zone.parse(p["most_recent_heartbeat"].to_s))
    end.sort_by { -(it.most_recent_heartbeat&.to_i || 0) }
  end

  # Totals for the given projects, inside the window only.
  def stats(names, window = ProgramWindow.current)
    names = self.class.keep(names)
    query = { features: "projects", **self.class.range(window) }
    query[:filter_by_project] = names.join(",") if names.any?
    body = get("#{SITE}/api/v1/users/my/stats?#{query.to_query}")
    data = body.fetch("data")
    Stats.new(total_seconds: names.empty? ? 0 : data["total_seconds"].to_i,
              projects: Array(data["projects"]).reject { self.class.ignored?(it["name"]) }.to_h { [ it["name"], it["total_seconds"].to_i ] },
              trust_level: body.dig("trust_factor", "trust_level"),
              user_id: data["user_id"].to_s)
  end

  # Stretches of coding on the given projects from `from` to `to`, oldest
  # first. Hackatime runs the projects' heartbeats through one time-ordered
  # pass, so the spans never overlap and add up to what stats counts for the
  # same range. It answers every span in the range and scans every heartbeat
  # in it, so ask for short ranges. With no names it would answer the whole
  # account, so none are asked for.
  def spans(names, from:, to:)
    names = self.class.keep(names)
    return [] if names.empty?
    zone = ProgramWindow::ZONE
    query = { start_date: from.in_time_zone(zone).iso8601, end_date: to.in_time_zone(zone).iso8601, filter_by_project: names.join(",") }
    body = get("#{SITE}/api/v1/users/my/heartbeats/spans?#{query.to_query}")
    body.fetch("spans").map { Span.new(start_time: Time.zone.at(it["start_time"]), end_time: Time.zone.at(it["end_time"])) }
  end

  private

  def get(url)
    HttpJson.get(url, headers: { "Authorization" => "Bearer #{@token}" })
  rescue HttpJson::Error => e
    raise unless e.status.in?([ 401, 404 ])
    raise Unlinked.new(e.message, status: e.status)
  end

  class Fake
    def initialize(user)
      @user = user
    end

    # Each project is one stretch of coding, total_seconds long, that ends at
    # its most recent heartbeat. Only the part inside the window counts. On
    # the new site (NewSite), a participant also gets the projects its guide
    # sent fake heartbeats for, and a newbie gets only those.
    def catalog
      seed = @user.id.to_i % 10 # keeps fake totals stable as database ids grow
      sent = NewSite.for?(@user) ? FakeHeartbeats.projects(@user) : []
      return sent if @user.hca_id == "ident!dev-newbie"
      sent + [
        Project.new(name: "rock-pet", total_seconds: 3 * 3600 + 20 * 60 + seed * 60, most_recent_heartbeat: 5.minutes.ago),
        Project.new(name: "rock-pet-art", total_seconds: 50 * 60, most_recent_heartbeat: 2.hours.ago),
        Project.new(name: "frog-widget", total_seconds: 7 * 3600 + 5 * 60, most_recent_heartbeat: 3.days.ago),
        Project.new(name: "dotfiles", total_seconds: 12 * 3600, most_recent_heartbeat: 40.days.ago),
        Project.new(name: IGNORED_PROJECTS.first, total_seconds: 30 * 60, most_recent_heartbeat: 1.minute.ago)
      ]
    end

    # A token of "revoked" acts out Hackatime refusing it.
    def projects(window = ProgramWindow.current)
      refuse_revoked
      within(window)
    end

    def stats(names, window = ProgramWindow.current)
      refuse_revoked
      names = Hackatime.keep(names)
      picked = within(window).select { names.include?(it.name) }
      Stats.new(total_seconds: picked.sum(&:total_seconds), projects: picked.to_h { [ it.name, it.total_seconds ] },
                trust_level: @user.email.to_s.include?("red") ? "red" : "blue", user_id: "fake-#{@user.id}")
    end

    # Each project's stretch is one span, cut to the range. Unlike
    # Hackatime's, two projects' spans can overlap, so over the window they
    # add up to what stats gives.
    def spans(names, from:, to:)
      refuse_revoked
      names = Hackatime.keep(names)
      catalog.select { names.include?(it.name) }.filter_map do |p|
        start = [ p.most_recent_heartbeat - p.total_seconds, from ].max
        stop = [ p.most_recent_heartbeat, to ].min
        Span.new(start_time: start, end_time: stop) if stop > start
      end.sort_by(&:start_time)
    end

    private

    def within(window)
      catalog.reject { Hackatime.ignored?(it.name) }.filter_map do |p|
        from = [ p.most_recent_heartbeat - p.total_seconds, window.starts_at ].max
        to = [ p.most_recent_heartbeat, window.ends_at ].min
        p.with(total_seconds: (to - from).round, most_recent_heartbeat: to) if to > from
      end
    end

    def refuse_revoked
      raise Unlinked.new("fake Hackatime -> 401", status: 401) if @user.hackatime_access_token == "revoked"
    end
  end
end
