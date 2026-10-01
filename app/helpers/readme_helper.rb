module ReadmeHelper
  # Hosts a README's images may load from. GitHub proxies outside images
  # through camo, so only GitHub hosts are needed.
  README_IMAGE_HOSTS = /(\A|\.)(github\.com|githubusercontent\.com)\z/

  # A participant's README as GitHub renders it, for the review page. Its
  # relative links and images point back into the repository, so none of
  # them loads a page of this site with the reviewer's login. Images load
  # only from GitHub, and a link to this site loses its href.
  def readme_html(html, repo:)
    return if html.blank?
    fragment = Loofah.html5_fragment(html.to_s)
    fragment.css("img").each do |img|
      src = readme_url(img["src"], "https://raw.githubusercontent.com/#{repo}/HEAD/")
      src&.scheme == "https" && src.host.match?(README_IMAGE_HOSTS) ? img["src"] = src.to_s : img.remove
    end
    fragment.css("a[href]").each do |a|
      next if a["href"].start_with?("#")
      href = readme_url(a["href"], "https://github.com/#{repo}/blob/HEAD/")
      href && href.host != request.host ? a["href"] = href.to_s : a.remove_attribute("href")
    end
    sanitize(fragment.to_s)
  end

  private

  def readme_url(url, base)
    uri = URI.join(base, url.to_s.strip)
    uri if uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::Error
    nil
  end
end
