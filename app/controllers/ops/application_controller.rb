# frozen_string_literal: true

module Ops
  class ApplicationController < Internal::ApplicationController
    before_action :require_ops_operator!
  end
end
