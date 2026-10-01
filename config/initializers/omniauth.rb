require Rails.root.join("lib/omniauth/strategies/hackatime")

# Login through Hack Club Auth, then a second OAuth to link Hackatime.
# address, phone, and birthdate need the app registered as HQ official in
# Hack Club Auth. Request phases are POST only.
Rails.application.config.middleware.use OmniAuth::Builder do
  hca = Rails.application.credentials.hack_club || {}
  hackatime = Rails.application.credentials.hackatime || {}
  # Tests drive both OAuth flows with placeholder apps and never reach the network.
  hca = hackatime = { client_id: "test-client", client_secret: "test-secret" } if Rails.env.test?

  provider :hack_club, hca[:client_id], hca[:client_secret], scope: HackClubAuth::SCOPES if hca[:client_id]
  provider :hackatime, hackatime[:client_id], hackatime[:client_secret] if hackatime[:client_id]
end

OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.on_failure = ->(env) { SessionsController.action(:failure).call(env) }
