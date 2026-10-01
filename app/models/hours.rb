# A participant's hours, in three stages:
#
#   unshipped  tracked on linked Hackatime projects, not yet submitted
#   pending    submitted, waiting for review and fraud
#   approved   reviewed, deflated, and passed fraud
#
# Deflated and rejected hours are counted as claimed by their ship, so they
# never return to unshipped. A ship returned with changes needed gives its
# hours back, so they appear as unshipped again.
class Hours
  # The admin stats load everyone's ships and projects at once and pass them in.
  def initialize(user, ships: user.ships, projects: user.projects)
    @user = user
    @ships = ships.to_a
    @projects = projects.to_a
  end

  def approved_seconds = @ships.select(&:approved?).sum { it.approved_seconds.to_i }
  def pending_seconds = @ships.select(&:pending?).sum(&:claimed_seconds)

  def unshipped_seconds
    @projects.sum { |project| project.unshipped_seconds(@ships.select { it.project_id == project.id }) }
  end

  def total_seconds = approved_seconds + pending_seconds + unshipped_seconds

  # The meter always ends at the last goal, so the goal marks stay readable.
  # Time past it is shown as text, not squeezed into the bar.
  def scale_seconds = Goal.all.last.seconds
  def beyond_scale_seconds = [ total_seconds - scale_seconds, 0 ].max

  # Where a participant stands on one goal. Progress counts every tracked
  # hour; only approved hours redeem.
  def goal_state(goal)
    return :redeemable if approved_seconds >= goal.seconds
    return :in_review if approved_seconds + pending_seconds >= goal.seconds
    return :ship_to_redeem if total_seconds >= goal.seconds
    :in_progress
  end

  def self.format(seconds)
    h, m = seconds.to_i.divmod(3600)
    m /= 60
    h.zero? ? "#{m}m" : "#{h}h #{m}m"
  end
end
