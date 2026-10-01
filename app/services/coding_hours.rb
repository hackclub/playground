# Refreshes one participant's coding hours (CodingHour) from Hackatime's
# heartbeat spans, and each pet's tracked total. One spans request covers
# every Hackatime project that counts for the participant, so time on two
# pets at once counts once.
class CodingHours
  # Spans are fetched from an hour before the range, so one running across
  # its start is whole. Only the part inside the range is written.
  LEAD = 1.hour

  # Returns true when the refresh went through, false when Hackatime refused
  # or failed, or the program hasn't started. On a failure the rows stay as
  # they were and coding_hours_synced_at is not moved, so the next run tries
  # again.
  def self.refresh(user, window: ProgramWindow.current, now: Time.current)
    return false unless user.hackatime_connected? && window.started?(now)
    synced_was = User.where(id: user.id).pick(:coding_hours_synced_at)
    from, to = range(synced_was, window, now)
    if from < to
      names = hackatime_names(user)
      spans = names.any? ? Hackatime.for(user).spans(names, from: [ from - LEAD, window.starts_at ].max, to:) : []
      write(user, bucket(spans, from:, to:), from:, to:, synced_was:, now:)
    end
    user.projects.each { TrackedTime.refresh(it, force: true) }
    true
  rescue HttpJson::Error => e
    Rails.logger.warn("coding hours refresh failed for user #{user.id}: #{e.message}")
    false
  end

  # The whole window on a first sync. After that, from the start of the
  # Eastern day before the last sync, so a span cut at the last fetch's end,
  # and heartbeats Hackatime received late, are counted again. Never before
  # the window opens, and never past its end or now.
  def self.range(synced_at, window, now)
    to = [ now, window.ends_at ].min
    from = synced_at ? synced_at.in_time_zone(ProgramWindow::ZONE).yesterday.beginning_of_day : window.starts_at
    [ [ from, window.starts_at ].max, to ]
  end

  # Every Hackatime project name that counts for the participant: those
  # their pets link now, and those their ships claimed time from.
  def self.hackatime_names(user)
    user.projects.includes(:ships).flat_map { it.hackatime_projects + it.shipped_hackatime_projects }.uniq
  end

  # Seconds per hour, { UTC hour start => Integer }, for the time the spans
  # cover from `from` up to `to`. A span that crosses hours goes into each by
  # its share. Overlapping spans count their shared time once. Hours with no
  # time are left out.
  def self.bucket(spans, from:, to:)
    hours = Hash.new(0.0)
    joined(spans, from, to).each do |start, stop|
      while start < stop
        hour = start.utc.beginning_of_hour
        cut = [ hour + 1.hour, stop ].min
        hours[hour] += cut - start
        start = cut
      end
    end
    hours.transform_values(&:round).select { |_, seconds| seconds.positive? }
  end

  # Each span cut to from...to, oldest first, with overlaps joined into one.
  def self.joined(spans, from, to)
    cut = spans.map { [ [ it.start_time, from ].max, [ it.end_time, to ].min ] }.select { |start, stop| stop > start }
    cut.sort.each_with_object([]) do |(start, stop), joined|
      if joined.any? && start <= joined.last[1]
        joined.last[1] = [ joined.last[1], stop ].max
      else
        joined << [ start, stop ]
      end
    end
  end

  # Replaces the participant's rows in the fetched range in one transaction,
  # since a span can shrink or vanish between fetches. The sync time moves
  # only if nothing reset it meanwhile (see Project).
  def self.write(user, hours, from:, to:, synced_was:, now:)
    CodingHour.transaction do
      user.coding_hours.where(hour: from.utc.beginning_of_hour...to).delete_all
      CodingHour.insert_all(hours.map { |hour, seconds| { user_id: user.id, hour:, seconds: } }) if hours.any?
      User.where(id: user.id, coding_hours_synced_at: synced_was).update_all(coding_hours_synced_at: now)
    end
  end

  private_class_method :range, :joined, :write
end
