# frozen_string_literal: true

module Branch
  class ApplicationController < Internal::ApplicationController
    before_action :require_branch_operator!
  end
end
