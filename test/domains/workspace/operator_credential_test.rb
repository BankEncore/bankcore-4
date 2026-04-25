# frozen_string_literal: true

require "test_helper"

module Workspace
  module Models
    class OperatorCredentialTest < ActiveSupport::TestCase
      test "normalizes username and authenticates password" do
        operator = Operator.create!(role: "teller", display_name: "Teller", active: true)
        credential = operator.create_credential!(
          username: "  Test.Teller  ",
          password: "password123",
          password_changed_at: Time.current
        )

        assert_equal "test.teller", credential.username
        assert credential.authenticate("password123")
        assert_not credential.authenticate("wrong-password")
      end

      test "find_for_login only returns active operators" do
        inactive = Operator.create!(role: "teller", display_name: "Inactive", active: false)
        inactive.create_credential!(username: "inactive", password: "password123")

        assert_nil OperatorCredential.find_for_login("inactive")
      end

      test "roles include operations and admin" do
        operations = Operator.create!(role: "operations", display_name: "Ops", active: true)
        admin = Operator.create!(role: "admin", display_name: "Admin", active: true)

        assert_predicate operations, :operations?
        assert_predicate admin, :admin?
      end
    end
  end
end
