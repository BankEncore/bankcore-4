# frozen_string_literal: true

module Core
  module Ledger
    module Models
      class GlAccount < ApplicationRecord
        self.table_name = "gl_accounts"
      end
    end
  end
end
