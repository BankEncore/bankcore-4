# frozen_string_literal: true

require "test_helper"

class ProductsDepositProductResolverTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @product = create_product!("resolver")
    @account = open_account!(@product)
  end

  test "resolves deposit behavior for account and date" do
    fee_rule = create_fee_rule!(@product)
    overdraft_policy = create_overdraft_policy!(@product)
    statement_profile = create_statement_profile!(@product)

    behavior = Products::Services::DepositProductResolver.call(
      deposit_account: @account,
      as_of: Date.new(2026, 4, 22)
    )

    assert_equal @product, behavior.deposit_product
    assert_equal fee_rule, behavior.monthly_maintenance_fee_rule
    assert_equal overdraft_policy, behavior.deny_nsf_policy
    assert_equal statement_profile, behavior.monthly_statement_profile
  end

  test "resolves nil behavior when product rows are not active" do
    create_fee_rule!(@product, effective_on: Date.new(2026, 5, 1))
    create_overdraft_policy!(@product, status: Products::Models::DepositProductOverdraftPolicy::STATUS_INACTIVE)
    create_statement_profile!(@product, effective_on: Date.new(2026, 3, 1), ended_on: Date.new(2026, 3, 31))

    behavior = Products::Services::DepositProductResolver.call(
      deposit_product_id: @product.id,
      as_of: Date.new(2026, 4, 22)
    )

    assert_equal @product, behavior.deposit_product
    assert_nil behavior.monthly_maintenance_fee_rule
    assert_nil behavior.deny_nsf_policy
    assert_nil behavior.monthly_statement_profile
  end

  test "requires account or product id" do
    assert_raises(ArgumentError) do
      Products::Services::DepositProductResolver.call(as_of: Date.new(2026, 4, 22))
    end
  end

  private

  def create_product!(prefix)
    Products::Models::DepositProduct.create!(
      product_code: "#{prefix}-#{SecureRandom.hex(4)}",
      name: prefix,
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  def open_account!(product)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Resolver",
      last_name: SecureRandom.hex(3)
    )
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: product.id)
  end

  def create_fee_rule!(product, attrs = {})
    Products::Models::DepositProductFeeRule.create!({
      deposit_product: product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 500,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end

  def create_overdraft_policy!(product, attrs = {})
    Products::Models::DepositProductOverdraftPolicy.create!({
      deposit_product: product,
      mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
      nsf_fee_minor_units: 3_500,
      currency: "USD",
      status: Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end

  def create_statement_profile!(product, attrs = {})
    Products::Models::DepositProductStatementProfile.create!({
      deposit_product: product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 1,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end
end
