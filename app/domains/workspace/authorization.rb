# frozen_string_literal: true

module Workspace
  module Authorization
    class Error < StandardError; end

    class Forbidden < Error; end
  end
end
