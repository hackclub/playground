# Public GitHub data for the submit gate and the review page. Unauthenticated
# calls get 60 an hour, so results are cached and credentials github.token is
# used when set.
class Github
  API = "https://api.github.com"
  Repo = Data.define(:full_name, :private, :default_branch, :pushed_at, :commits, :readme, :stars)
  Release = Data.define(:tag, :url, :assets)

  def self.repo(full_name)
    Rails.cache.fetch([ "github-repo", full_name ], expires_in: 10.minutes) do
      body = get("/repos/#{full_name}")
      Repo.new(full_name: body["full_name"], private: body["private"], default_branch: body["default_branch"],
               pushed_at: body["pushed_at"], commits: commit_count(full_name), readme: readme?(full_name),
               stars: body["stargazers_count"])
    end
  rescue HttpJson::Error => e
    raise unless e.status == 404
    nil
  end

  # The release a playable URL points at: /releases/tag/X, or the latest one
  # for /releases and /releases/latest. nil when the URL is not a release.
  def self.release_for(url)
    m = url.to_s.match(%r{\Ahttps://github\.com/([\w.-]+/[\w.-]+)/releases(?:/(latest|tag/([^/?#]+)))?/?\z})
    return unless m
    path = m[3] ? "/repos/#{m[1]}/releases/tags/#{m[3]}" : "/repos/#{m[1]}/releases/latest"
    Rails.cache.fetch([ "github-release", path ], expires_in: 10.minutes) do
      body = get(path)
      Release.new(tag: body["tag_name"], url: body["html_url"],
                  assets: Array(body["assets"]).map { { "name" => it["name"], "size" => it["size"], "url" => it["browser_download_url"] } })
    end
  rescue HttpJson::Error => e
    raise unless e.status == 404
    Release.new(tag: nil, url: url, assets: [])
  end

  def self.readme_html(full_name)
    Rails.cache.fetch([ "github-readme-html", full_name ], expires_in: 10.minutes) do
      _, body = HttpJson.request(:get, "#{API}/repos/#{full_name}/readme", headers: headers.merge("Accept" => "application/vnd.github.html"))
      body.to_s
    end
  rescue HttpJson::Error
    nil
  end

  def self.recent_commits(full_name, limit: 15)
    Array(get("/repos/#{full_name}/commits?per_page=#{limit}")).map do
      { "sha" => it["sha"].first(7), "message" => it.dig("commit", "message").to_s.lines.first.to_s.strip,
        "date" => it.dig("commit", "author", "date"), "url" => it["html_url"] }
    end
  rescue HttpJson::Error
    []
  end

  def self.readme?(full_name)
    get("/repos/#{full_name}/readme")
    true
  rescue HttpJson::Error => e
    raise unless e.status == 404
    false
  end

  # The commit count from the last page number of a one-per-page listing.
  def self.commit_count(full_name)
    res, body = HttpJson.request(:get, "#{API}/repos/#{full_name}/commits?per_page=1", headers: headers)
    last = res["link"].to_s[/[?&]page=(\d+)>; rel="last"/, 1]
    last ? last.to_i : Array(body).size
  rescue HttpJson::Error => e
    e.status == 409 ? 0 : raise # 409: the repository is empty
  end

  def self.get(path) = HttpJson.get("#{API}#{path}", headers: headers)

  def self.headers
    token = Rails.application.credentials.dig(:github, :token)
    { "Accept" => "application/vnd.github+json", "X-GitHub-Api-Version" => "2022-11-28" }
      .merge(token ? { "Authorization" => "Bearer #{token}" } : {})
  end
end
