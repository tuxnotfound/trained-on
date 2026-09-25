module Admin
  # The integrity gate. One reviewer, HTTP basic auth, credentials from the
  # environment. Without them set, the admin refuses every request.
  class BaseController < ApplicationController
    before_action :authenticate

    private

    # In development the review decisions file is kept current after every
    # decision, ready to commit. Production reviews are exported on demand.
    def export_decisions
      TrainedOn::Decisions.export! if Rails.env.development?
    end

    def authenticate
      user, password = ENV["TRAINED_ON_ADMIN_USER"], ENV["TRAINED_ON_ADMIN_PASSWORD"]
      return head(:forbidden) if user.blank? || password.blank?
      authenticate_or_request_with_http_basic("Trained On review") do |u, p|
        ActiveSupport::SecurityUtils.secure_compare(u, user) & ActiveSupport::SecurityUtils.secure_compare(p, password)
      end
    end
  end
end
