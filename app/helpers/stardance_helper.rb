module StardanceHelper
  # Links to the Stardance projects of a repo shipped there, each opening in
  # a new tab. Empty when there are none.
  def stardance_links(ids)
    safe_join(Array(ids).map { link_to "see it on Stardance ↗", StardanceRepos.project_url(it), target: "_blank", rel: "noopener" }, " ")
  end
end
