# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc,
  # The address and phone a goal ships to, and the admin people search, which
  # takes names and emails.
  :shipping, :address, :phone, /\Aq\z/,
  # OAuth callback parameters.
  /\Acode\z/, /\Astate\z/
]
