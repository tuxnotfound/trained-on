module Admin
  # The integrity gate. One reviewer, credentials from the environment.
  # Browsers log in through a form (/admin/login), because HTTP Basic prompts
  # do not appear in every browser. Scripts and tests may still send HTTP Basic.
  # Without credentials configured, the admin refuses every request.
  class BaseController < ApplicationController
    include AdminCredentials

    before_action :authenticate
    helper_method :admin_logged_in?

    private

    # In development the review decisions file is kept current after every
    # decision, ready to commit. Production reviews are exported on demand.
    def export_decisions
      TrainedOn::Decisions.export! if Rails.env.development?
    end

    def authenticate
      return render(plain: AdminCredentials::DISABLED, status: :forbidden) unless admin_configured?
      return if admin_logged_in?

      if request.authorization.present?
        authenticate_or_request_with_http_basic("Trained On review") { |user, password| valid_admin?(user, password) }
      else
        redirect_to admin_login_path(return_to: (request.fullpath if request.get?))
      end
    end
  end
end
