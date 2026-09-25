module Admin
  class SessionsController < ApplicationController
    include AdminCredentials

    before_action :require_configured
    rate_limit to: 10, within: 3.minutes, only: :create,
               with: -> { redirect_to admin_login_path, alert: "Too many attempts. Try again in a few minutes." }

    def new
      redirect_to admin_root_path if admin_logged_in?
    end

    def create
      if valid_admin?(params[:username], params[:password])
        return_to = safe_return_to
        reset_session
        session[:admin] = admin_token
        redirect_to return_to
      else
        flash.now[:alert] = "Wrong username or password."
        render :new, status: :unprocessable_content
      end
    end

    def destroy
      reset_session
      redirect_to root_path, notice: "Logged out."
    end

    private

    def require_configured
      render plain: AdminCredentials::DISABLED, status: :forbidden unless admin_configured?
    end

    # Only paths inside the admin, never another host.
    def safe_return_to
      path = params[:return_to].to_s
      path.start_with?("/admin") && !path.start_with?("//") ? path : admin_root_path
    end
  end
end
