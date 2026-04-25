# frozen_string_literal: true

module Admin
  class ApplicationController < Internal::ApplicationController
    before_action :require_admin_operator!
  end
end
