# Stardance's database, read through its MCP server, as Stardance has no
# API. The server takes read-only SQL through its query tool and records the
# plain-English question asked with each query. The token is credentials
# stardance.mcp_token, a Hack Club Auth sign-in with no refresh: when it
# expires the server answers 401, and someone signs in again for a new one.
# Without a token nothing is asked.
#
# The transport is MCP's Streamable HTTP
# (https://modelcontextprotocol.io/specification/2025-06-18/basic/transports):
# JSON-RPC 2.0 messages POSTed to one endpoint, each answered as JSON or as a
# server-sent event stream. initialize opens a session, and its
# Mcp-Session-Id header, if the server sends one, goes on every later request.
class StardanceMcp
  ENDPOINT = "https://stardance-mcp.cooked.selfhosted.hackclub.com/mcp"
  PROTOCOL = "2025-06-18"

  # The server's answer was not what this client reads.
  class Error < HttpJson::Error; end
  # The server no longer takes the token.
  class Rejected < Error; end
  REJECTED = "Stardance MCP token rejected; sign in again".freeze

  # A query's columns and every row, each row its cells as strings.
  Result = Data.define(:columns, :rows) do
    def hashes = rows.map { columns.zip(it).to_h }
  end

  # How many rows each get_rows call reads. The server caches 10,000 rows of
  # a query.
  PAGE = 500

  def self.token = Rails.application.credentials.dig(:stardance, :mcp_token)
  def self.configured? = token.present?

  def initialize(token = self.class.token)
    @token = token
    @next_id = 0
  end

  # Runs the SQL and reads every row. The query tool's preview cuts long
  # cells short, and get_rows does not, so every row comes from get_rows.
  def query(sql, question:)
    first = Table.parse(call_tool("query", sql:, question:, preview_rows: 1))
    rows = []
    while rows.size < first.total
      page = Table.parse(call_tool("get_rows", query_id: first.query_id, offset: rows.size, limit: PAGE))
      raise Error, "get_rows answered no rows at #{rows.size} of #{first.total}" if page.rows.empty?
      rows.concat(page.rows)
    end
    Result.new(columns: first.columns, rows:)
  end

  # The text a tool answers, as in its first text content block. A tool
  # that fails says why in the same place, with isError.
  def call_tool(name, **arguments)
    open_session unless @opened
    result = rpc("tools/call", name:, arguments:)
    text = Array(result["content"]).select { it["type"] == "text" }.map { it["text"] }.join("\n")
    raise Error, "#{name} failed: #{text.first(200)}" if result["isError"]
    text
  end

  private

  def open_session
    init = rpc("initialize", protocolVersion: PROTOCOL, capabilities: {}, clientInfo: { name: "playground", version: "1" })
    @protocol = init["protocolVersion"] || PROTOCOL
    @opened = true
    post({ jsonrpc: "2.0", method: "notifications/initialized" })
  end

  # One request and the result of its answer.
  def rpc(method, **params)
    id = (@next_id += 1)
    res, body = post({ jsonrpc: "2.0", id:, method:, params: })
    @session ||= res["mcp-session-id"].presence
    message = self.class.answer(body, id)
    raise Error, "#{method}: #{message.dig("error", "message")}" if message["error"]
    message.fetch("result")
  end

  def post(message)
    headers = { "Authorization" => "Bearer #{@token}", "Accept" => "application/json, text/event-stream" }
    headers["Mcp-Session-Id"] = @session if @session
    headers["MCP-Protocol-Version"] = @protocol if @protocol
    HttpJson.request(:post, ENDPOINT, headers:, json: message, timeout: 60)
  rescue HttpJson::Error => e
    raise Rejected.new(REJECTED, status: e.status) if e.status == 401
    raise
  end

  # The JSON-RPC answer with this id, from a JSON body or from the events of
  # a stream. A stream may carry other messages before it.
  def self.answer(body, id)
    messages = body.is_a?(String) ? events(body) : Array.wrap(body)
    messages.find { it.is_a?(Hash) && it["id"] == id && (it.key?("result") || it.key?("error")) } or
      raise Error, "no answer to request #{id}"
  end

  # The JSON in each event of a server-sent event stream. An event's data
  # lines join with newlines, and a blank line ends the event.
  def self.events(stream)
    stream.split(/\r?\n\r?\n/).filter_map do |event|
      data = event.lines.map(&:chomp).select { it.start_with?("data:") }.map { it.delete_prefix("data:").delete_prefix(" ") }
      JSON.parse(data.join("\n")) if data.any?
    end
  end

  # The query and get_rows tools answer a text table:
  #
  #   Query ID: 01f63ae1          (query only)
  #   Total rows: 1               (query; get_rows says "Rows 1-3 of 28:")
  #   Columns: projects, users    (query only)
  #
  #   projects | users
  #   ----------------
  #   74       | 72
  #
  # Cells are padded and joined by " | ". A cell holding a pipe or a newline
  # can't be told apart, so the SQL sends only plain cells: ids and hex.
  Table = Data.define(:query_id, :total, :columns, :rows) do
    def self.parse(text)
      lines = text.lines.map(&:rstrip)
      total = text[/^Total rows: (\d+)/, 1] || text[/^Rows \d+-\d+ of (\d+)/, 1] or raise Error, "no row count in: #{text.first(200)}"
      rule = lines.index { it.match?(/\A-+\z/) }
      header = rule ? cells(lines[rule - 1]) : text[/^Columns: (.*)$/, 1].to_s.split(", ")
      rows = rule ? lines.drop(rule + 1).take_while(&:present?).map { cells(it) } : []
      raise Error, "a row has #{rows.find { it.size != header.size }.size} cells, not #{header.size}" if rows.any? { it.size != header.size }
      new(query_id: text[/^Query ID: (\S+)/, 1], total: total.to_i, columns: header, rows:)
    end

    def self.cells(line) = line.split("|", -1).map(&:strip)
  end
end
