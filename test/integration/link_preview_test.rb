require "test_helper"

# A link to the site unfurls, in Slack and elsewhere, into a title, a line of
# text, and a picture. The unfurl is fetched logged out, so the desktop and
# the logged-out pages carry the tags. A page behind the login carries none,
# so nothing from an account can show in them.
class LinkPreviewTest < ActionDispatch::IntegrationTest
  DESCRIPTION = "make a desktop pet, get cool merch! playground is a Hack Club program where you code a pet that lives on your screen.".freeze
  TAGS = "meta[property^='og:'], meta[name^='twitter:'], meta[name='description'], meta[name='theme-color']".freeze

  setup do
    host! "playground.hackclub.com"
    https!
  end

  test "the desktop carries the tags, with the image by an absolute URL on the request's host" do
    get root_path
    assert_response :ok

    assert_equal "playground", tag("og:title")
    assert_equal "playground", tag("og:site_name")
    assert_equal "website", tag("og:type")
    assert_equal DESCRIPTION, tag("og:description")
    assert_equal "https://playground.hackclub.com/", tag("og:url")
    assert_match %r{\Ahttps://playground\.hackclub\.com/assets/opengraph-\w+\.jpg\z}, tag("og:image")
    assert_equal "1200", tag("og:image:width")
    assert_equal "675", tag("og:image:height")
    assert_match "learn how to make a desktop pet!", tag("og:image:alt")
    assert_match "10h, very cool shirt", tag("og:image:alt")
    assert_equal "summary_large_image", tag("twitter:card")
    assert_equal "playground", tag("twitter:title")
    assert_equal DESCRIPTION, tag("twitter:description")
    assert_equal tag("og:image"), tag("twitter:image")
    assert_equal tag("og:image:alt"), tag("twitter:image:alt")
    assert_equal DESCRIPTION, tag("description")
    assert_equal "#3a70b8", tag("theme-color")
    assert_no_match(/ysws/i, css_select(TAGS).map { it["content"] }.join(" "))

    host! "preview.example.org"
    get root_path
    assert_match %r{\Ahttps://preview\.example\.org/assets/opengraph-\w+\.jpg\z}, tag("og:image")
  end

  test "the image is a 1200 by 675 JPEG under 300 KB" do
    get root_path
    get URI(tag("og:image")).path
    assert_response :ok
    assert_equal "image/jpeg", response.media_type
    assert_operator response.body.bytesize, :<, 300.kilobytes
    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal [ 1200, 675 ], [ image.width, image.height ]
  end

  test "the login and a pet link seen logged out carry the tags" do
    get login_path
    assert_equal "https://playground.hackclub.com/login", tag("og:url")
    assert_equal DESCRIPTION, tag("og:description")

    pet = User.create!(hca_id: "ident!other", email: "other@example.com").projects.create!(name: "not yours")
    get edit_project_path(pet)
    follow_redirect!
    assert_equal "https://playground.hackclub.com/login", tag("og:url")
  end

  test "pages behind the login carry no tags and show nothing from the account in the head" do
    user = log_in("participant")
    pet = user.projects.create!(name: "Secret Pet Name", description: "a secret description")
    [ dashboard_path, project_path(pet), edit_project_path(pet), checks_project_path(pet), new_project_path ].each do |path|
      get path
      assert_response :ok, path
      assert_select TAGS, 0, path
      head = css_select("head").to_s
      [ pet.name, pet.description, user.display_name, user.email ].each { assert_not_includes head, it, path }
    end

    # The desktop is the same page for everyone, and keeps its tags.
    get root_path
    assert_equal DESCRIPTION, tag("og:description")
    assert_not_includes css_select("head").to_s, pet.name
  end

  test "admin pages carry no tags" do
    log_in("admin")
    [ admin_root_path, admin_people_path, admin_person_path(User.first) ].each do |path|
      get path
      assert_response :ok, path
      assert_select TAGS, 0, path
    end
  end

  private

  def tag(name)
    meta = css_select("meta[property='#{name}'], meta[name='#{name}']")
    assert_equal 1, meta.size, "one #{name} tag"
    meta.first["content"]
  end
end
