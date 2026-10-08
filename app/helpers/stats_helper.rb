# Counts and charts for the admin stats page, drawn on the server in the
# meter's colours.
module StatsHelper
  PIE_RADIUS = 90

  # A count of people, linked to the people page listing exactly them.
  def people_count(group)
    return tag.span("0", class: "muted") if group.count.zero?
    link_to group.count, admin_people_path(filter: group.key), title: group.label
  end

  def share(fraction) = fraction ? number_to_percentage(fraction * 100, precision: 0) : "—"

  # A wait in minutes, hours, or days.
  def wait(seconds)
    return "—" unless seconds
    return "#{(seconds / 60).floor}m" if seconds < 1.hour
    return Hours.format(seconds) if seconds < 2.days
    "#{(seconds / 1.day).floor}d #{(seconds % 1.day / 1.hour).floor}h"
  end

  # A heat grid cell's shade: 0 for no time, then 1 to 4 by quarters of the
  # busiest cell.
  def heat(seconds, busiest) = seconds.to_f.positive? && busiest.to_f.positive? ? (4.0 * seconds / busiest).ceil.clamp(1, 4) : 0

  # "12am", "9am", "12pm", "9pm".
  def hour_name(hour) = "#{(hour % 12).zero? ? 12 : hour % 12}#{hour < 12 ? "am" : "pm"}"

  # How one week's hours compare with the week before's.
  def weekly_change(now, before)
    return "none in the 7 days before" if before.zero?
    change = (now - before).fdiv(before)
    return "the same as the 7 days before" if change.abs < 0.005
    "#{change.positive? ? "up" : "down"} #{share(change.abs)} on the 7 days before (#{hours(before)})"
  end

  # Why a person counts as active on a day, as "coded 20m", one phrase for
  # each kind of activity they did that day.
  ACTIVE_BECAUSE = { coded: "coded" }.freeze
  def active_because(person) = person.reasons.map { |kind, seconds| "#{ACTIVE_BECAUSE.fetch(kind)} #{hours(seconds)}" }.join(", ")

  # A Stardance person in a day's list: their name to their Stardance
  # profile, a link to them on Slack, and a tag that says where they are from.
  def stardance_person(person)
    name = person.stardance_url ? link_to(person.name, person.stardance_url) : person.name
    safe_join([ name, tag.span("Stardance", class: "badge badge-stardance"), link_to("Slack", person.slack_url, class: "muted") ], " ")
  end

  # A day's people from Stardance and the clubs, as "12 Stardance coders, 3
  # Clubs readers", or nil on a day with none. A coder counted by Hackatime
  # time (ProgramStats::ActiveDay), a reader by time in the guide. why: each
  # with what made it count, and without the coders the day's table lists.
  def guide_readers(day, why: false)
    SideGuide.all.filter_map do |guide|
      next unless (count = day.readers[guide.slug].to_i).positive?
      coded = coded_side?(guide, day)
      next if why && coded && day.stardance.listed
      text = pluralize(count, "#{guide.name} #{coded ? "coder" : "reader"}")
      next text unless why
      "#{text} (#{coded ? "#{ProgramStats::ACTIVE_CODING_SECONDS / 60}+ min in Hackatime on their playground project" : "#{SideGuide.reading_seconds / 60}+ min in the guide"})"
    end.join(", ").presence
  end

  # The chart legend's name for a guide's people.
  def side_legend(guide, days) = "#{guide.name} #{days.any? { coded_side?(guide, it) } ? "coders" : "readers"}"

  # Stardance's count on the day is by Hackatime time.
  def coded_side?(guide, day) = guide.slug == "stardance" && day.stardance.present?

  # A bar in the meter's approved fill and ink outline.
  def bar(fraction, kind = nil) = tag.div(tag.span(style: "width: #{(100 * fraction.to_f).round(1)}%"), class: [ "bar", kind ])

  # A source as the admin stats name it (TrafficSource), and a time bucket,
  # as "2–5m" (GuideJourneyStats).
  def source_name(source) = TrafficSource.name(source)
  def minutes_name(minutes) = GuideJourneyStats.minutes_name(minutes) || "—"

  # A share of a count, or "—" when there is nothing to share.
  def share_of(count, total) = share((count.fdiv(total) if total.to_i.positive?))

  # One bar for a group of readers, split into their time buckets, lightest
  # for the shortest. Each part names its bucket and share on hover, and the
  # table under it gives the numbers.
  def time_stack(cohort)
    parts = GuideJourneyDay::MINUTES.each_index.filter_map do |j|
      count = cohort.in_bucket(j)
      [ j, count, "#{minutes_name(GuideJourneyDay::MINUTES[j])}: #{pluralize(count, "reader")}, #{share_of(count, cohort.readers)}" ] if count.positive?
    end
    spans = parts.map { |j, count, about| tag.span(class: "time-#{j}", style: "flex-grow: #{count}", title: about) }
    tag.div(safe_join(spans), class: "time-stack", role: "img", aria: { label: "time spent: #{parts.map(&:last).join("; ")}" })
  end

  # Hidden fields that keep another form's choices when this one is sent.
  def kept_params(*names) = safe_join(names.filter_map { |name| hidden_field_tag(name, params[name], id: nil) if params[name].present? })

  # The hour stages as a pie, drawn as the meter draws them. Each stage is a
  # layer from twelve o'clock round to where it ends, later stages under
  # earlier ones, inside the meter's ink outline. Pending hours wear the
  # meter's own hatching tile.
  def hours_pie(stages)
    total = stages.values.sum.to_f
    reached = 0
    layers = stages.filter_map do |stage, seconds|
      [ stage, (reached += seconds) / total, "#{stage} #{hours(seconds)}, #{share(seconds / total)}" ] if seconds.positive?
    end
    label = layers.map(&:last).join("; ")
    tag.svg(class: "pie", viewBox: "0 0 200 200", width: 200, height: 200, role: "img", aria: { label: }) do
      hatching = tag.pattern(id: "pie-pending", patternUnits: "userSpaceOnUse", width: 594, height: 18) do
        tag.rect(width: 594, height: 18, fill: "#9bb8e0") + tag.image(href: image_path("meter/pending.svg"), width: 594, height: 18)
      end
      safe_join([ tag.defs(hatching), *layers.reverse.map { |stage, upto, title| wedge(stage, upto, title) },
                  tag.circle(class: "outline", cx: 100, cy: 100, r: PIE_RADIUS) ])
    end
  end

  private

  def wedge(stage, fraction, title)
    return tag.circle(tag.title(title), class: stage, cx: 100, cy: 100, r: PIE_RADIUS) if fraction >= 0.9999
    angle = 2 * Math::PI * fraction
    x = (100 + PIE_RADIUS * Math.sin(angle)).round(2)
    y = (100 - PIE_RADIUS * Math.cos(angle)).round(2)
    tag.path(tag.title(title), class: stage, d: "M100 100V#{100 - PIE_RADIUS}A#{PIE_RADIUS} #{PIE_RADIUS} 0 #{fraction > 0.5 ? 1 : 0} 1 #{x} #{y}Z")
  end
end
