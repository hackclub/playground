require "omniauth-oauth2"

# Hackatime's OAuth, per
# https://docs.hackclub.com/handbook/public-infrastructure/hackatime/integrating-hackatime-with-your-ysws
# Tokens last about 16 years, so there is no refresh.
module OmniAuth
  module Strategies
    class Hackatime < OmniAuth::Strategies::OAuth2
      option :name, "hackatime"
      option :scope, "profile read"
      option :client_options, {
        site: "https://hackatime.hackclub.com",
        authorize_url: "/oauth/authorize",
        token_url: "/oauth/token"
      }

      uid { nil }

      def callback_url = full_host + callback_path
    end
  end
end
