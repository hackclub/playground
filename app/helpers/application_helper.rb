module ApplicationHelper
  # The sponsor's Slack profile. His name links here wherever it shows on the desktop.
  SPONSOR_URL = "https://hackclub.enterprise.slack.com/team/U07ABEP916X".freeze

  def hours(seconds) = Hours.format(seconds)

  def state_badge(state)
    label = { "draft" => "not shipped", "pending" => "pending", "approved" => "approved",
              "changes_needed" => "changes needed", "rejected" => "rejected" }.fetch(state, state)
    tag.span(label, class: "badge badge-#{state}")
  end

  # The hours meter: approved solid, pending hatched,
  # unshipped faint, with a mark at each goal labelled with its hours, such
  # as "2h stickers". A goal the approved hours have reached is marked
  # "reached", and the label read out for the meter names it. The goals never
  # move: the bar ends at the last goal and is simply full past it. The legend
  # has totals.
  #
  # Each stage is a layer from the bar's left end to where the stage ends, so
  # its drawn end can overlap the stage after it. A stage with no hours has no
  # layer. Later layers paint over earlier ones, so they go in reverse.
  def meter(hours)
    scale = hours.scale_seconds.to_f
    reached = 0
    layers = { approved: hours.approved_seconds, pending: hours.pending_seconds,
               unshipped: hours.unshipped_seconds }.filter_map do |stage, seconds|
      next if seconds <= 0 || reached >= scale
      reached = [ reached + seconds, scale ].min
      tag.span(class: token_list("seg", stage, full: reached >= scale), style: "--end: #{(100 * reached / scale).round(2)}%")
    end
    goals_reached = Goal.all.select { hours.approved_seconds >= it.seconds }
    label = "#{hours(hours.approved_seconds)} approved, #{hours(hours.pending_seconds)} pending, #{hours(hours.unshipped_seconds)} unshipped"
    label += ". Reached: #{goals_reached.map { "#{it.hours}h #{it.key}" }.to_sentence}" if goals_reached.any?
    tag.div(class: "meter", role: "img", aria: { label: }) do
      safe_join([
        tag.div(safe_join(layers.reverse), class: "meter-bar"),
        *Goal.all.map do |g|
          at = (100 * g.seconds / scale).round(2)
          tag.span(class: token_list("goal-mark", end: at > 90, reached: goals_reached.include?(g)), style: "left: #{at}%") do
            safe_join([ tag.span("#{g.hours}h", class: "goal-hours"), " ", tag.span(g.key, class: "goal-name") ])
          end
        end
      ].compact)
    end
  end

  # "1.3/2 h": progress toward a goal from every tracked hour.
  def goal_progress(hours, goal)
    done = [ hours.total_seconds, goal.seconds ].min / 3600.0
    "#{number_with_precision(done, precision: 1, strip_insignificant_zeros: true)}/#{goal.hours} h"
  end

  # A date in the viewer's own format and time zone. The server knows neither,
  # so it writes the ISO date, and the local-date controller rewrites it.
  def local_date(time)
    time_tag(time, time.to_date.iso8601, data: { controller: "local-date" })
  end

  # "5pm Eastern time on September 25, 2026". The program's times are set in
  # US Eastern time, so they are shown in it too.
  def program_time(time)
    t = time.in_time_zone(ProgramWindow::ZONE)
    "#{t.strftime(t.min.zero? ? "%-l%P" : "%-l:%M%P")} Eastern time on #{t.strftime("%B %-d, %Y")}"
  end

  def check_icon(check)
    return "✓" if check.ok
    check.blocker? ? "✗" : "!"
  end

  # Where Hackatime's OAuth starts: its request phase, or the fake in
  # development. Forms that post here target the top window, as OAuth pages
  # don't load inside a desktop window.
  def hackatime_oauth_path(deny: nil) = FakeServices.on? ? dev_hackatime_path(deny:) : "/auth/hackatime"

  def hackatime_button(label, form: {}, deny: nil, **)
    button_to FakeServices.on? ? "#{label} (dev)" : label, hackatime_oauth_path(deny:),
              data: { turbo: false }, form: { target: "_top", **form }, **
  end
end
