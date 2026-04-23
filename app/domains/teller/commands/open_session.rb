# frozen_string_literal: true

module Teller
  module Commands
    class OpenSession
      class Error < StandardError; end
      class SessionAlreadyOpen < Error; end

      # One open session per drawer_code (nil drawer = single open session for MVP).
      def self.call(drawer_code: nil)
        Teller::Models::TellerSession.transaction do
          scope = Teller::Models::TellerSession.where(status: Teller::Models::TellerSession::STATUS_OPEN)
          scope = scope.where(drawer_code: drawer_code) if drawer_code.present?
          raise SessionAlreadyOpen, "open session exists for drawer" if scope.exists?

          Teller::Models::TellerSession.create!(
            status: Teller::Models::TellerSession::STATUS_OPEN,
            opened_at: Time.current,
            drawer_code: drawer_code
          )
        end
      end
    end
  end
end
