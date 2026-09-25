module Admin
  class PreviewController < BaseController
    def toggle
      if preview?
        cookies.delete(:preview)
      else
        cookies.signed[:preview] = { value: "1", httponly: true, same_site: :lax }
      end
      redirect_to root_path
    end
  end
end
