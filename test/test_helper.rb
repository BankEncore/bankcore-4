ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require_relative "../lib/bank_core/seeds/gl_coa"
require_relative "../lib/bank_core/seeds/deposit_products"
require_relative "../lib/bank_core/seeds/operating_units"
require_relative "../lib/bank_core/seeds/rbac"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # `parallelize_setup` runs in forked workers only; below the parallelization threshold the suite
    # runs in the parent process, so seed here too (structure.sql has empty `deposit_products`).
    BankCore::Seeds::DepositProducts.seed!
    BankCore::Seeds::OperatingUnits.seed! if ActiveRecord::Base.connection.table_exists?(:operating_units)
    BankCore::Seeds::Rbac.seed! if ActiveRecord::Base.connection.table_exists?(:capabilities)

    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    parallelize_setup do |_worker|
      BankCore::Seeds::DepositProducts.seed!
      BankCore::Seeds::OperatingUnits.seed! if ActiveRecord::Base.connection.table_exists?(:operating_units)
      BankCore::Seeds::Rbac.seed! if ActiveRecord::Base.connection.table_exists?(:capabilities)
    end

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end

class ActionDispatch::IntegrationTest
  def teller_json_headers(operator)
    {
      "CONTENT_TYPE" => "application/json",
      "X-Operator-Id" => operator.id.to_s
    }
  end

  def create_workspace_operators!
    default_operating_unit = Organization::Services::DefaultOperatingUnit.branch
    teller = Workspace::Models::Operator.create!(
      role: "teller",
      display_name: "Test Teller",
      active: true,
      default_operating_unit: default_operating_unit
    )
    supervisor = Workspace::Models::Operator.create!(
      role: "supervisor",
      display_name: "Test Supervisor",
      active: true,
      default_operating_unit: default_operating_unit
    )
    BankCore::Seeds::Rbac.seed!
    [ teller, supervisor ]
  end

  def create_operator_with_credential!(role:, username:, password: "password123", active: true)
    operator = Workspace::Models::Operator.create!(
      role: role,
      display_name: "Test #{role.titleize}",
      active: active,
      default_operating_unit: Organization::Services::DefaultOperatingUnit.branch
    )
    operator.create_credential!(
      username: username,
      password: password,
      password_changed_at: Time.current
    )
    BankCore::Seeds::Rbac.seed!
    operator
  end

  def internal_login!(username:, password: "password123")
    post "/login", params: { username: username, password: password }
    assert_redirected_to "/internal"
  end
end
