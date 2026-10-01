require "test_helper"

# The browser gate: Safari from 16.4, the first with import maps. Every iOS
# browser runs Safari's engine, so Chrome on iOS goes by its iOS version, not
# its Chrome version. Opera on Chrome's engine goes by its Chrome version, not
# its Opera version. Apple's Messages app fetches its link previews as Safari
# 9, and passes by the crawler name it adds. The user agents are real ones, as
# the browsers sent them.
class BrowserFloorTest < ActionDispatch::IntegrationTest
  IOS_SAFARI_16_4 = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Mobile/15E148 Safari/604.1"
  IOS_SAFARI_16_3 = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.3 Mobile/15E148 Safari/604.1"
  MAC_SAFARI_16_4 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Safari/605.1.15"
  IOS_16_6_CHROME_115 = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/115.0.5790.160 Mobile/15E148 Safari/604.1"
  IOS_16_3_CHROME_138 = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/138.0.7204.33 Mobile/15E148 Safari/604.1"
  WINDOWS_CHROME_119 = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
  ANDROID_OPERA_102_CHROME_152 = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36 OPR/102.0.0.0"
  WINDOWS_OPERA_106_CHROME_120 = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 OPR/106.0.0.0"
  WINDOWS_OPERA_100_CHROME_114 = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 OPR/100.0.0.0"
  MAC_SAFARI_9 ="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_1) AppleWebKit/601.2.4 (KHTML, like Gecko) Version/9.0.1 Safari/601.2.4"
  MESSAGES_LINK_PREVIEW = "#{MAC_SAFARI_9} facebookexternalhit/1.1 Facebot Twitterbot/1.0".freeze

  test "iOS Safari 16.4 gets the desktop and, logged in, the dashboard" do
    get root_path, headers: { "User-Agent" => IOS_SAFARI_16_4 }
    assert_response :ok
    assert_select "#apps"

    get dev_login_path(as: "participant"), headers: { "User-Agent" => IOS_SAFARI_16_4 }
    get dashboard_path, headers: { "User-Agent" => IOS_SAFARI_16_4 }
    assert_response :ok
    assert_select "h2", "your meter"
  end

  test "iOS Safari 16.3 gets the unsupported browser page, logged in or not" do
    get root_path, headers: { "User-Agent" => IOS_SAFARI_16_3 }
    assert_response :not_acceptable

    log_in("participant")
    get dashboard_path, headers: { "User-Agent" => IOS_SAFARI_16_3 }
    assert_response :not_acceptable
    assert_match "Your browser is not supported", response.body
  end

  test "Safari 16.4 on a Mac gets the site" do
    get root_path, headers: { "User-Agent" => MAC_SAFARI_16_4 }
    assert_response :ok
  end

  test "Chrome on iOS goes by the iOS version" do
    get root_path, headers: { "User-Agent" => IOS_16_6_CHROME_115 }
    assert_response :ok
    get root_path, headers: { "User-Agent" => IOS_16_3_CHROME_138 }
    assert_response :not_acceptable
  end

  test "Chrome elsewhere keeps Rails' modern minimum" do
    get root_path, headers: { "User-Agent" => WINDOWS_CHROME_119 }
    assert_response :not_acceptable
  end

  test "Opera goes by the Chrome it runs on, so Opera for Android's low version number passes" do
    get root_path, headers: { "User-Agent" => ANDROID_OPERA_102_CHROME_152 }
    assert_response :ok
    get root_path, headers: { "User-Agent" => WINDOWS_OPERA_106_CHROME_120 }
    assert_response :ok
    get root_path, headers: { "User-Agent" => WINDOWS_OPERA_100_CHROME_114 }
    assert_response :not_acceptable
    assert_match "Your browser is not supported", response.body
  end

  test "Apple's Messages app gets the page for its link preview, and Safari 9 alone does not" do
    get root_path, headers: { "User-Agent" => MESSAGES_LINK_PREVIEW }
    assert_response :ok
    assert_select "meta[property='og:title'][content='playground']"

    get root_path, headers: { "User-Agent" => MAC_SAFARI_9 }
    assert_response :not_acceptable
  end
end
