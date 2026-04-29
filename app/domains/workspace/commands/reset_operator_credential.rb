# frozen_string_literal: true

module Workspace
  module Commands
    class ResetOperatorCredential
      class InvalidRequest < StandardError; end

      def self.call(operator_id:, username:, password:)
        raise InvalidRequest, "Password is required" if password.blank?

        operator = Models::Operator.find(operator_id)
        credential = operator.credential || operator.build_credential
        credential.assign_attributes(
          username: username.presence || credential.username,
          password: password,
          password_changed_at: Time.current,
          failed_login_attempts: 0,
          locked_at: nil
        )
        credential.save!
        credential
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
