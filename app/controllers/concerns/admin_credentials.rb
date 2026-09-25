# The single reviewer's credentials, from TRAINED_ON_ADMIN_USER and
# TRAINED_ON_ADMIN_PASSWORD (a gitignored .env in development).
module AdminCredentials
  extend ActiveSupport::Concern

  DISABLED = "The review admin is off: set TRAINED_ON_ADMIN_USER and TRAINED_ON_ADMIN_PASSWORD.".freeze

  private

  def admin_user = ENV["TRAINED_ON_ADMIN_USER"].presence
  def admin_password = ENV["TRAINED_ON_ADMIN_PASSWORD"].presence
  def admin_configured? = admin_user.present? && admin_password.present?

  def valid_admin?(user, password)
    return false unless admin_configured?
    ActiveSupport::SecurityUtils.secure_compare(user.to_s, admin_user) &
      ActiveSupport::SecurityUtils.secure_compare(password.to_s, admin_password)
  end

  # Stored in the session at login. Derived from the credentials, so changing
  # the password ends every existing session.
  def admin_token = Digest::SHA256.hexdigest("#{admin_user}\0#{admin_password}")
  def admin_logged_in? = admin_configured? && session[:admin].present? && ActiveSupport::SecurityUtils.secure_compare(session[:admin].to_s, admin_token)
end
