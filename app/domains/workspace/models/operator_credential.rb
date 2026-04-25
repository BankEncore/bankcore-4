# frozen_string_literal: true

module Workspace
  module Models
    class OperatorCredential < ApplicationRecord
      self.table_name = "operator_credentials"

      belongs_to :operator, class_name: "Workspace::Models::Operator"

      has_secure_password

      before_validation :normalize_username

      validates :username, presence: true, uniqueness: { case_sensitive: false }
      validates :failed_login_attempts, numericality: { greater_than_or_equal_to: 0, only_integer: true }

      scope :for_active_operator, -> { joins(:operator).where(operators: { active: true }) }

      def self.find_for_login(username)
        for_active_operator.find_by("lower(operator_credentials.username) = ?", username.to_s.strip.downcase)
      end

      private

      def normalize_username
        self.username = username.to_s.strip.downcase.presence
      end
    end
  end
end
