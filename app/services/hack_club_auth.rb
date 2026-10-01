# Reads the participant's identity from Hack Club Auth with their stored
# token, refreshing it on a 401. Used at submit and at redeem, where
# eligibility and the address must be current. Scopes and fields come from
# github.com/hackclub/auth, app/models/oauth_scope.rb.
class HackClubAuth
  SITE = "https://auth.hackclub.com"
  SCOPES = "openid email name slack_id verification_status birthdate phone address".freeze

  def self.for(user) = FakeServices.on? ? Fake.new(user) : new(user)

  def initialize(user)
    @user = user
  end

  def identity
    HttpJson.get("#{SITE}/api/v1/me", headers: { "Authorization" => "Bearer #{@user.hca_access_token}" }).fetch("identity")
  rescue HttpJson::Error => e
    raise unless e.status == 401 && @user.hca_refresh_token.present?
    refresh!
    HttpJson.get("#{SITE}/api/v1/me", headers: { "Authorization" => "Bearer #{@user.hca_access_token}" }).fetch("identity")
  end

  # Fetches the identity and stores what changed. Returns the identity.
  def refresh_user!
    identity.tap do |id|
      @user.assign_identity(id)
      @user.save!
    end
  end

  def self.portal_url(kind, return_to) = "#{SITE}/portal/#{kind}?return_to=#{CGI.escape(return_to)}"

  private

  def refresh!
    creds = Rails.application.credentials.hack_club
    _, body = HttpJson.request(:post, "#{SITE}/oauth/token", form: {
      grant_type: "refresh_token", refresh_token: @user.hca_refresh_token,
      client_id: creds[:client_id], client_secret: creds[:client_secret]
    })
    @user.update!(hca_access_token: body["access_token"], hca_refresh_token: body["refresh_token"].presence || @user.hca_refresh_token)
  end

  class Fake
    def initialize(user)
      @user = user
    end

    def identity
      {
        "id" => @user.hca_id, "primary_email" => @user.email, "first_name" => @user.first_name,
        "last_name" => @user.last_name, "verification_status" => @user.verification_status,
        "ysws_eligible" => @user.ysws_eligible || nil,
        "addresses" => [ { "id" => "addr_1", "first_name" => @user.first_name, "last_name" => @user.last_name,
                           "line_1" => "15 Falls Road", "line_2" => "Unit 2", "city" => "Shelburne", "state" => "VT",
                           "postal_code" => "05482", "country" => "US", "phone_number" => "+1 802 555 0100", "primary" => true } ]
      }.compact
    end

    def refresh_user! = identity
  end
end
