class ApplicationMailer < ActionMailer::Base
  # MAIL_FROM, else the SMTP login.
  default from: -> { ENV["MAIL_FROM"].presence || ENV["SMTP_USERNAME"].presence || "playground@example.com" }
  layout "mailer"
end
