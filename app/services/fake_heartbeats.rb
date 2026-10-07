# Development only. The heartbeats fake Hackatime has seen, as Godot's
# plugin would send them: each project name with the time its first
# heartbeat came. A project codes from then until now, so its time grows
# while the guide watches. Kept in a file per participant under tmp/, so it
# lasts across requests and server restarts. Each environment has its own
# folder, so a test's participant never sees a development one's, and each
# test process too, as parallel test databases reuse the same ids.
module FakeHeartbeats
  def self.dir = Rails.root.join("tmp/fake_heartbeats", Rails.env, Rails.env.test? ? Process.pid.to_s : "")

  def self.start(user, name)
    name = name.to_s.strip.first(200)
    return if name.empty? || name.include?(",")
    seen = started(user)
    return if seen.key?(name)
    FileUtils.mkdir_p(dir)
    # As if Godot had sent a minute of heartbeats already: Hackatime lists no
    # project with no time.
    File.write(file(user), JSON.generate(seen.merge(name => 1.minute.ago.to_i)))
  end

  # Each project as Hackatime lists it, its latest heartbeat now.
  def self.projects(user)
    now = Time.current
    started(user).map do |name, at|
      Hackatime::Project.new(name:, total_seconds: (now.to_i - at).clamp(0..), most_recent_heartbeat: now)
    end
  end

  def self.started(user) = File.exist?(file(user)) ? JSON.parse(File.read(file(user))) : {}
  def self.file(user) = dir.join("#{user.id}.json")
end
