# frozen_string_literal: true

module Workspace
  module Commands
    class CreateOperator
      class InvalidRequest < StandardError; end

      def self.call(attributes:)
        attrs = attributes.to_h.symbolize_keys
        credential_attrs = attrs.slice(:username, :password)
        operator_attrs = attrs.slice(:display_name, :role, :active, :default_operating_unit_id)

        Models::Operator.transaction do
          operator = Models::Operator.create!(operator_attrs)
          create_credential!(operator, credential_attrs) if credential_attrs[:username].present?
          operator
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        raise InvalidRequest, e.message
      end

      def self.create_credential!(operator, credential_attrs)
        if credential_attrs[:password].blank?
          raise InvalidRequest, "Password is required when creating credentials"
        end

        operator.create_credential!(
          username: credential_attrs[:username],
          password: credential_attrs[:password],
          password_changed_at: Time.current,
          failed_login_attempts: 0,
          locked_at: nil
        )
      end
      private_class_method :create_credential!
    end
  end
end
