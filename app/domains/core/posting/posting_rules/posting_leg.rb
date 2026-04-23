# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      # Immutable description of one journal line to persist for an operational event.
      PostingLeg = Struct.new(:sequence_no, :gl_account_number, :side, :amount_minor_units, :deposit_account_id,
                              keyword_init: true)
    end
  end
end
