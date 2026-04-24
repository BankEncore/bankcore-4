ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require_relative "../lib/bank_core/seeds/gl_coa"
require_relative "../lib/bank_core/seeds/deposit_products"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    parallelize_setup do |_worker|
      BankCore::Seeds::DepositProducts.seed!
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
    teller = Workspace::Models::Operator.create!(role: "teller", display_name: "Test Teller", active: true)
    supervisor = Workspace::Models::Operator.create!(role: "supervisor", display_name: "Test Supervisor", active: true)
    [ teller, supervisor ]
  end
end
