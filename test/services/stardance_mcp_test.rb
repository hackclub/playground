require "test_helper"

# The Stardance MCP client against canned server answers: HttpJson.request is
# swapped for the test, and nothing reaches the network. The tables are in
# the form the server's query and get_rows tools answer.
class StardanceMcpTest < ActiveSupport::TestCase
  FIRST = <<~TEXT.freeze
    Query ID: 2edc5653
    Total rows: 3
    Columns: slack_id, project

    Preview (1 of 3 rows):
    slack_id    | project
    -----------------------
    U0A         | 6f72626974

    Use get_rows(query_id='2edc5653', offset=1) for more rows.
  TEXT

  def page(from, rows)
    lines = rows.map { |id, hex| "#{id.ljust(11)} | #{hex}" }
    "Rows #{from + 1}-#{from + rows.size} of 3:\nslack_id    | project\n-----------------------\n#{lines.join("\n")}\n\n" \
      "#{"More rows available. Use offset=#{from + rows.size} to continue." if from + rows.size < 3}"
  end

  # A tool result as the server sends it.
  def result(id, text, error: false) = { "jsonrpc" => "2.0", "id" => id, "result" => { "content" => [ { "type" => "text", "text" => text } ], "isError" => error } }

  # The same message as one event of a stream, after a notification the
  # client does not wait for.
  def stream(message) = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\"}\n\nevent: message\ndata: #{message.to_json}\n\n"

  setup do
    @sent = sent = []
    @answers = answers = []
    HttpJson.singleton_class.alias_method(:real_request, :request)
    HttpJson.define_singleton_method(:request) do |method, url, headers: {}, json: nil, **|
      sent << { method:, url:, headers:, json: }
      answer = answers.shift
      raise HttpJson::Error.new("POST -> #{answer}", status: answer) if answer.is_a?(Integer)
      answer || [ {}, nil ]
    end
  end

  teardown { HttpJson.singleton_class.alias_method(:request, :real_request) }

  def initialize_answer(session: nil) = [ { "mcp-session-id" => session }.compact, { "jsonrpc" => "2.0", "id" => 1, "result" => { "protocolVersion" => "2025-06-18" } } ]

  test "opens a session, then reads every row through get_rows, not the cut preview" do
    @answers.push(initialize_answer(session: "s-1"), [ {}, nil ],
                  [ {}, stream(result(2, FIRST)) ],
                  [ {}, result(3, page(0, [ %w[U0A 6f72626974], %w[U0A 6f726269742d617274] ])) ],
                  [ {}, stream(result(4, page(2, [ %w[U0B 7374617273] ]))) ])
    found = StardanceMcp.new("sd_token").query("SELECT 1", question: "Which rows?")

    assert_equal %w[slack_id project], found.columns
    assert_equal [ %w[U0A 6f72626974], %w[U0A 6f726269742d617274], %w[U0B 7374617273] ], found.rows
    assert_equal %w[initialize notifications/initialized tools/call tools/call tools/call], @sent.map { it[:json][:method] }
    assert @sent.all? { it[:url] == StardanceMcp::ENDPOINT && it[:headers]["Authorization"] == "Bearer sd_token" }
    assert @sent.all? { it[:headers]["Accept"] == "application/json, text/event-stream" }
    assert_nil @sent.first[:headers]["Mcp-Session-Id"]
    assert @sent.drop(1).all? { it[:headers]["Mcp-Session-Id"] == "s-1" && it[:headers]["MCP-Protocol-Version"] == "2025-06-18" }

    query, *pages = @sent.drop(2).map { it[:json][:params] }
    assert_equal({ name: "query", arguments: { sql: "SELECT 1", question: "Which rows?", preview_rows: 1 } }, query)
    assert_equal [ { query_id: "2edc5653", offset: 0, limit: StardanceMcp::PAGE }, { query_id: "2edc5653", offset: 2, limit: StardanceMcp::PAGE } ],
                 pages.map { it[:arguments] }
  end

  test "a server with no session sends no session header, and an empty result asks for no rows" do
    empty = "Query ID: 86bad1da\nTotal rows: 0\nColumns: n\n\nPreview (0 of 0 rows):\n(no rows)"
    @answers.push(initialize_answer, [ {}, nil ], [ {}, stream(result(2, empty)) ])
    found = StardanceMcp.new("sd_token").query("SELECT 1 AS n WHERE false", question: "Nothing?")
    assert_equal [ "n" ], found.columns
    assert_empty found.rows
    assert @sent.none? { it[:headers].key?("Mcp-Session-Id") }
    assert_equal 3, @sent.size
  end

  test "a 401 is the token rejected, with one clear message" do
    @answers.push(401)
    error = assert_raises(StardanceMcp::Rejected) { StardanceMcp.new("sd_old").query("SELECT 1", question: "Which rows?") }
    assert_equal "Stardance MCP token rejected; sign in again", error.message
    assert_equal 401, error.status
  end

  test "a tool error and a JSON-RPC error raise with the server's words" do
    @answers.push(initialize_answer, [ {}, nil ], [ {}, stream(result(2, "Error: relation does not exist", error: true)) ])
    error = assert_raises(StardanceMcp::Error) { StardanceMcp.new("sd_token").call_tool("query", sql: "SELECT", question: "?") }
    assert_equal "query failed: Error: relation does not exist", error.message

    @answers.push(initialize_answer, [ {}, nil ], [ {}, { "jsonrpc" => "2.0", "id" => 2, "error" => { "code" => -32602, "message" => "Unknown tool" } } ])
    error = assert_raises(StardanceMcp::Error) { StardanceMcp.new("sd_token").call_tool("nope") }
    assert_equal "tools/call: Unknown tool", error.message
  end

  test "a table: padded cells, the count from either tool, and a row that doesn't fit refused" do
    table = StardanceMcp::Table.parse(FIRST)
    assert_equal [ "2edc5653", 3, %w[slack_id project], [ %w[U0A 6f72626974] ] ], [ table.query_id, table.total, table.columns, table.rows ]
    assert_equal 3, StardanceMcp::Table.parse(page(0, [ %w[U0A 6f72626974] ])).total
    assert_raises(StardanceMcp::Error) { StardanceMcp::Table.parse(FIRST.sub("U0A         | 6f72626974", "U0A | a | b")) }
    assert_raises(StardanceMcp::Error) { StardanceMcp::Table.parse("Something else") }
  end

  test "events: data lines join, and CRLF ends an event too" do
    assert_equal [ { "a" => 1 }, { "b" => [ 2 ] } ], StardanceMcp.events("event: message\r\ndata: {\"a\":1}\r\n\r\ndata: {\"b\":\ndata: [2]}\n\n")
  end

  test "configured only with a token" do
    original = StardanceMcp.method(:token)
    StardanceMcp.define_singleton_method(:token) { nil }
    assert_not StardanceMcp.configured?
    StardanceMcp.define_singleton_method(:token) { "sd_token" }
    assert StardanceMcp.configured?
  ensure
    StardanceMcp.define_singleton_method(:token, &original)
  end
end
