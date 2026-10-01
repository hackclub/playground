# Refreshes a project's all-time Hackatime total for its linked projects.
# One request per pet: Hackatime removes overlap itself when asked for
# several projects together.
class TrackedTime
  def self.refresh(project, force: false)
    return project if !force && project.tracked_at&.after?(5.minutes.ago)
    user = project.user
    return project unless user.hackatime_connected?

    stats = Hackatime.for(user).stats(project.hackatime_projects)
    project.update_columns(tracked_seconds: stats.total_seconds, tracked_at: Time.current)
    user.update_columns(hackatime_trust_level: stats.trust_level, hackatime_user_id: stats.user_id.presence || user.hackatime_user_id)
    project.instance_variable_set(:@stats, stats)
    project
  rescue HttpJson::Error => e
    user.hackatime_unlinked = true if e.is_a?(Hackatime::Unlinked)
    Rails.logger.warn("hackatime refresh failed for project #{project.id}: #{e.message}")
    project
  end

  def self.refresh_all(user)
    user.projects.each { refresh(it) }
  end
end
