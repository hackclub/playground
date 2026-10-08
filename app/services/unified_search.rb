# The double-dip check: is this code URL already in the Unified YSWS Projects
# DB under another program? Read-only token, one filtered search, cached ten
# minutes on the normalized URL. Never raises: a failure is a result.
module UnifiedSearch
  BASE = "app3A5kJwYqxMLOgh"
  TABLE = "Approved Projects"
  FIELDS = [ "Code URL", "YSWS–Name", "Approved At", "Override Hours Spent", "Playable URL" ].freeze
  CACHE_FOR = 10.minutes
  MIN_LENGTH = 8
  REPO_HOSTS = %w[github.com gitlab.com codeberg.org bitbucket.org].freeze
  # Playground's own rows get their program name from the Unified DB, and
  # nothing in the sync code sets or reads it. This is a guess at that name,
  # so such matches are shown apart, never counted as a double dip.
  OWN_PROGRAM = /playground/i

  Match = Struct.new(:program, :approved_at, :hours, :url, :own, keyword_init: true)
  # status: :ok, :warn, :own_only, :unknown. reason: why it is unknown.
  Result = Struct.new(:status, :matches, :reason, keyword_init: true)

  module_function

  def token = ENV["AIRTABLE_UNIFIED_TOKEN"].presence || Rails.application.credentials.dig(:airtable, :unified_token).presence

  def normalize(url)
    value = url.to_s.strip.downcase.sub(%r{\A[a-z][a-z0-9+.-]*://}, "").sub(/\Awww\./, "").sub(/[?#].*\z/, "")
    value = value.sub(%r{/+\z}, "").delete_suffix(".git")
    host, owner, repo = value.split("/")
    value = [ host, owner, repo.to_s.delete_suffix(".git") ].compact_blank.join("/") if REPO_HOSTS.include?(host) && repo.present?
    value.sub(%r{/+\z}, "")
  end

  def check(code_url, client: nil)
    key = normalize(code_url)
    return Result.new(status: :unknown, matches: [], reason: "no code URL to search for") if key.length < MIN_LENGTH
    return Result.new(status: :unknown, matches: [], reason: "no read token") if client.nil? && token.blank?
    Rails.cache.fetch("unified-search/#{key}", expires_in: CACHE_FOR, skip_nil: true) { search(key, client) }
  rescue => e
    Rails.logger.error("UnifiedSearch #{e.class}: #{e.message.to_s.gsub(token.to_s, "[token]").first(300)}")
    Result.new(status: :unknown, matches: [], reason: "Unified DB search failed")
  end

  def search(key, client)
    client ||= AirtableClient.new(token:, base: BASE)
    escaped = key.gsub("\\") { "\\\\" }.gsub("'") { "\\'" }
    formula = "FIND(LOWER('#{escaped}'), LOWER({Code URL}))"
    matches = client.search(TABLE, formula:, fields: FIELDS).filter_map { match(it, key) }
    status = if matches.empty? then :ok elsif matches.all?(&:own) then :own_only else :warn end
    Result.new(status:, matches:)
  end

  def match(record, key)
    fields = record["fields"]
    return unless normalize(fields["Code URL"]) == key
    program = Array(fields["YSWS–Name"]).join(", ").presence || "unknown program"
    Match.new(program:, approved_at: fields["Approved At"], hours: fields["Override Hours Spent"], url: fields["Code URL"], own: program.match?(OWN_PROGRAM))
  end
end
