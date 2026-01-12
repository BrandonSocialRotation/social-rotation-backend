class PasswordResetMailer < ApplicationMailer
  # Send password reset email
  # @param user [User] User requesting password reset
  # @param reset_url [String] Full URL to reset password page with token
  def reset_password_email(user, reset_url)
    @user = user
    @reset_url = reset_url
    
    mail(
      to: user.email,
      subject: 'Reset Your Password - Social Rotation',
      from: ENV['MAILER_FROM_EMAIL'] || 'support@socialrotation.com',
      reply_to: ENV['MAILER_REPLY_TO'] || 'support@socialrotation.com',
      'Message-ID': "<#{SecureRandom.uuid}@socialrotation.com>",
      'X-Mailer': 'Social Rotation',
      'X-Priority': '1',
      'Importance': 'high'
    ) do |format|
      format.html
      format.text
    end
  end
end
