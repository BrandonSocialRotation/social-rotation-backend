class ApplicationMailer < ActionMailer::Base
  default from: ENV['MAILER_FROM_EMAIL'] || "noreply@socialrotation.app"
  layout "mailer"
end
