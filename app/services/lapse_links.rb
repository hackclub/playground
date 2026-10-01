# Finds the Lapses behind a ship's hours. Lapse syncs
# each timelapse to Hackatime as heartbeats with language "Lapse" and entity
# "<title> (<timelapse id>)" (hackclub/lapse, apps/server/src/routers/
# timelapse.ts). The Hackatime admin API lists those heartbeats per project;
# the public Lapse API describes each timelapse. With no admin key this
# returns unavailable, never a guess.
class LapseLinks
  HACKATIME = "https://hackatime.hackclub.com/api/admin/v1"
  LAPSE_API = "https://api.lapse.hackclub.com/api"
  PAGE = 5000
  ID_IN_ENTITY = /\(([A-Za-z0-9_-]{6,64})\)\s*\z/

  Lapse = Data.define(:id, :title, :duration, :project, :url)
  Result = Data.define(:lapses, :error) do
    def seconds = lapses.sum(&:duration)
    def urls = lapses.map(&:url)
    def to_h = { "lapses" => lapses.map(&:to_h).map { it.transform_keys(&:to_s) }, "lapse_seconds" => seconds, "lapse_error" => error }.compact
  end

  def self.key = Rails.application.credentials.dig(:hackatime, :admin_api_key)
  def self.configured? = key.present?

  def self.for(user, projects)
    return Result.new(lapses: [], error: "no Hackatime admin key") unless configured?
    return Result.new(lapses: [], error: "no Hackatime user id") if user.hackatime_user_id.blank?

    ids = projects.flat_map { |project| lapse_ids(user.hackatime_user_id, project).map { [ it, project ] } }.uniq(&:first)
    lapses = ids.filter_map { |id, project| describe(id, project) }
    Result.new(lapses:, error: nil)
  rescue HttpJson::Error, SocketError, Timeout::Error, OpenSSL::SSL::SSLError => e
    Result.new(lapses: [], error: "could not read Lapses: #{e.message.first(120)}")
  end

  # Distinct timelapse ids in the entities of one project's Lapse heartbeats
  # inside the program window. The admin API takes epoch seconds for both
  # ends and includes both.
  def self.lapse_ids(hackatime_user_id, project, window = ProgramWindow.current)
    ids = []
    offset = 0
    loop do
      query = { user_id: hackatime_user_id, project:, language: "Lapse", limit: PAGE, offset:,
                start_date: window.starts_at.to_i, end_date: window.ends_at.to_i }.to_query
      body = HttpJson.get("#{HACKATIME}/user/heartbeats?#{query}", headers: { "Authorization" => "Bearer #{key}" }, timeout: 20)
      ids.concat(Array(body["heartbeats"]).filter_map { it["entity"].to_s[ID_IN_ENTITY, 1] })
      break unless body["has_more"]
      offset += PAGE
    end
    ids.uniq
  end

  # The public view of one timelapse. A timelapse that failed processing
  # has no video to review, so it is left out.
  def self.describe(id, project)
    body = HttpJson.get("#{LAPSE_API}/timelapse/query?#{{ id: }.to_query}")
    t = body.dig("data", "timelapse") or return
    return if t["visibility"] == "FAILED_PROCESSING"
    Lapse.new(id:, title: t["name"].to_s, duration: t["duration"].to_i, project:, url: "https://lapse.hackclub.com/timelapse/#{id}")
  rescue HttpJson::Error => e
    raise unless e.status == 404
    nil
  end
end
