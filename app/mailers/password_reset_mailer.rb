class PasswordResetMailer < ApplicationMailer
  # Send password reset email
  # @param user [User] User requesting password reset
  # @param reset_url [String] Full URL to reset password page with token
  def reset_password_email(user, reset_url)
    @user = user
    @reset_url = reset_url
    
    mail(
      to: user.email,
      subject: 'Reset Your Password - Social Rotation'
    )
  end
end
