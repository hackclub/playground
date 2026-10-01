require "test_helper"
require "socket"

# Links a participant typed may only reach public addresses, and credentials
# never follow a redirect to another host.
class HttpJsonTest < ActiveSupport::TestCase
  test "private, loopback, link-local, and reserved addresses are not public" do
    %w[127.0.0.1 10.1.2.3 172.16.0.1 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0 224.0.0.1 ::1 :: fd00::1 fe80::1 ::ffff:127.0.0.1 ::ffff:10.0.0.1].each do
      assert_not HttpJson.public_address?(it), it
    end
    %w[1.1.1.1 140.82.112.3 2606:4700:4700::1111].each { assert HttpJson.public_address?(it), it }
    assert_not HttpJson.public_address?("not an address")
  end

  test "a participant's link to this machine or the cloud metadata address is refused before any connection" do
    [ "http://127.0.0.1:1/", "http://localhost:1/", "http://[::1]:1/", "http://169.254.169.254/latest/meta-data/", "https://10.0.0.1/" ].each do |url|
      assert_raises(HttpJson::Refused, url) { HttpJson.request(:head, url, public_only: true) }
    end
  end

  test "only http and https links are fetched" do
    assert_raises(HttpJson::Refused) { HttpJson.request(:get, "file:///etc/passwd") }
    assert_raises(HttpJson::Refused) { HttpJson.request(:get, "http:///no-host") }
  end

  test "a redirect to another host drops the Authorization header" do
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    requests = []
    thread = Thread.new do
      2.times do
        client = server.accept
        lines = []
        while (line = client.gets) && line != "\r\n"
          lines << line
        end
        requests << lines
        client.write(lines.first.include?("/start") ?
          "HTTP/1.1 302 Found\r\nLocation: http://localhost:#{port}/next\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" :
          "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        client.close
      end
    end
    assert_equal({}, HttpJson.get("http://127.0.0.1:#{port}/start", headers: { "Authorization" => "Bearer secret" }))
    thread.join(5)
    assert requests[0].any? { it.start_with?("Authorization: Bearer secret") }
    assert requests[1].none? { it.downcase.start_with?("authorization") }
  ensure
    server&.close
  end
end
