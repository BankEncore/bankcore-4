# frozen_string_literal: true

module Core
  module Posting
    module PostingRules
      module Registry
        HANDLERS = {
          "deposit.accepted" => DepositAccepted,
          "withdrawal.posted" => WithdrawalPosted,
          "transfer.completed" => TransferCompleted,
          "posting.reversal" => PostingReversal,
          "fee.assessed" => FeeAssessed,
          "fee.waived" => FeeWaived
        }.freeze

        def self.legs_for(event)
          handler = HANDLERS[event.event_type.to_s]
          if handler.nil?
            raise Core::Posting::Commands::PostEvent::InvalidState,
                  "unsupported event_type for posting: #{event.event_type.inspect}"
          end
          handler.legs_for(event)
        end
      end
    end
  end
end
