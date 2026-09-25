class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV["TRAINED_ON_MAIL_FROM"].presence || "trained-on@localhost" }
  layout "mailer"
end
