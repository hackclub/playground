require "net/http"
require "ipaddr"

# The one HTTP helper the service clients share. Raises HttpJson::Error with
# the status on anything but 2xx.
module HttpJson
  class Error < StandardError
    attr_reader :status

    def initialize(message, status: nil)
      super(message)
      @status = status
    end
  end

  # A link that points inside the server's own network, or isn't http(s).
  class Refused < Error; end

  # Addresses a participant's link may not reach: this machine, private and
  # carrier-grade NAT networks, link-local (cloud metadata), multicast, and
  # other reserved ranges.
  BLOCKED = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.168.0.0/16
    198.18.0.0/15 224.0.0.0/3 ::/96 64:ff9b::/96 fc00::/7 fe80::/10 ff00::/8
  ].map { IPAddr.new(it) }.freeze

  module_function

  # public_only: the URL came from a participant, so the request may only go
  # to public addresses, on every redirect too. The host resolves once, and
  # the connection goes to the address that was checked.
  def request(method, url, headers: {}, form: nil, json: nil, timeout: 10, redirects: 5, public_only: false)
    uri = URI(url)
    raise Refused, "only http and https links" unless uri.is_a?(URI::HTTP) && uri.hostname.present?
    ip = public_ip(uri.hostname) if public_only
    klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, head: Net::HTTP::Head }.fetch(method)
    req = klass.new(uri, { "Accept" => "application/json", "User-Agent" => "playground.hackclub.com" }.merge(headers))
    req.set_form_data(form) if form
    if json
      req["Content-Type"] = "application/json"
      req.body = json.to_json
    end
    http = Net::HTTP.new(uri.hostname, uri.port)
    http.ipaddr = ip if ip
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 5
    http.read_timeout = timeout
    res = http.start { it.request(req) }
    if res.is_a?(Net::HTTPRedirection) && method.in?([ :get, :head ]) && redirects.positive? && res["location"]
      target = URI.join(url, res["location"])
      # Credentials go only to the host they were meant for.
      headers = headers.reject { |name, _| name.to_s.casecmp?("authorization") } unless target.host == uri.host
      return request(method, target.to_s, headers:, timeout:, redirects: redirects - 1, public_only:)
    end
    unless res.is_a?(Net::HTTPSuccess)
      raise Error.new("#{method.upcase} #{uri.host}#{uri.path} -> #{res.code}: #{res.body.to_s.first(200)}", status: res.code.to_i)
    end
    type = res["content-type"].to_s
    json = res.body.present? && type.match?(%r{\bjson\b}) && !type.include?("html")
    [ res, json ? JSON.parse(res.body) : res.body ]
  end

  def get(url, **) = request(:get, url, **).last

  # The address to connect to for a participant's link. Every address the
  # host resolves to must be public, so a second lookup can't pick another.
  def public_ip(host)
    ips = Addrinfo.getaddrinfo(host, nil, nil, :STREAM).map(&:ip_address).uniq
    raise Refused, "#{host} is not a public address" if ips.empty? || !ips.all? { public_address?(it) }
    ips.first
  end

  def public_address?(ip)
    ip = IPAddr.new(ip.to_s).native
    BLOCKED.none? { it.include?(ip) }
  rescue IPAddr::InvalidAddressError
    false
  end
end
