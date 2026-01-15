# Preview all emails at http://localhost:3000/rails/mailers/password_reset_mailer_mailer
class PasswordResetMailerPreview < ActionMailer::Preview

  # Preview this email at http://localhost:3000/rails/mailers/password_reset_mailer_mailer/reset_password_email
  def reset_password_email
    PasswordResetMailer.reset_password_email
  end

end
