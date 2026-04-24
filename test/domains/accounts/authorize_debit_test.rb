# frozen_string_literal: true

require "test_helper"

class AccountsAuthorizeDebitTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @product = create_product!("authorize-debit")
    @policy = create_policy!(@product, nsf_fee_minor_units: 3_500)
    @account = open_account!(@product)
    @destination = open_account!(@product)
  end

  test "sufficient withdrawal creates normal pending financial event" do
    fund_account!(@account, 10_000)

    result = Accounts::Commands::AuthorizeDebit.call(
      event_type: "withdrawal.posted",
      channel: "batch",
      idempotency_key: "wd-ok-#{SecureRandom.hex(4)}",
      amount_minor_units: 1_000,
      currency: "USD",
      source_account_id: @account.id
    )

    assert_equal :created, result[:outcome]
    assert_equal "withdrawal.posted", result[:event].event_type
    assert_equal "pending", result[:event].status
    assert_nil Core::OperationalEvents::Models::OperationalEvent.find_by(event_type: "overdraft.nsf_denied")
  end

  test "insufficient withdrawal records denial and forced NSF fee but no withdrawal" do
    result = authorize_overdrawn_withdrawal!("wd-nsf-#{SecureRandom.hex(4)}", amount: 1_000)

    assert_equal :nsf_denied, result[:outcome]
    assert_equal "overdraft.nsf_denied", result[:denial_event].event_type
    assert_equal "posted", result[:denial_event].status
    assert_equal "attempt:withdrawal.posted", result[:denial_event].reference_id
    assert_equal "fee.assessed", result[:fee_event].event_type
    assert_equal "posted", result[:fee_event].status
    assert_equal "nsf_denial:#{result[:denial_event].id}", result[:fee_event].reference_id
    assert_nil Core::OperationalEvents::Models::OperationalEvent.find_by(event_type: "withdrawal.posted")
  end

  test "insufficient transfer records denial and forced NSF fee but no transfer" do
    result = Accounts::Commands::AuthorizeDebit.call(
      event_type: "transfer.completed",
      channel: "batch",
      idempotency_key: "xfer-nsf-#{SecureRandom.hex(4)}",
      amount_minor_units: 1_000,
      currency: "USD",
      source_account_id: @account.id,
      destination_account_id: @destination.id
    )

    assert_equal :nsf_denied, result[:outcome]
    assert_equal "attempt:transfer.completed", result[:denial_event].reference_id
    assert_equal @destination.id, result[:denial_event].destination_account_id
    assert_nil Core::OperationalEvents::Models::OperationalEvent.find_by(event_type: "transfer.completed")
  end

  test "same idempotency key replays same denial and fee without double charge" do
    idem = "wd-nsf-replay-#{SecureRandom.hex(4)}"
    first = authorize_overdrawn_withdrawal!(idem, amount: 1_000)
    second = authorize_overdrawn_withdrawal!(idem, amount: 1_000)

    assert_equal :nsf_denied, first[:outcome]
    assert_equal :nsf_denied_replay, second[:outcome]
    assert_equal first[:denial_event].id, second[:denial_event].id
    assert_equal first[:fee_event].id, second[:fee_event].id
    assert_equal 1, Core::OperationalEvents::Models::OperationalEvent.where(event_type: "fee.assessed").count
  end

  test "missing active policy falls back to insufficient funds rejection" do
    no_policy_product = create_product!("no-policy")
    no_policy_account = open_account!(no_policy_product)

    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Accounts::Commands::AuthorizeDebit.call(
        event_type: "withdrawal.posted",
        channel: "batch",
        idempotency_key: "wd-no-policy-#{SecureRandom.hex(4)}",
        amount_minor_units: 1_000,
        currency: "USD",
        source_account_id: no_policy_account.id
      )
    end
    assert_match(/insufficient available balance/i, err.message)
  end

  test "NSF fee can drive account negative" do
    fund_account!(@account, 100)

    authorize_overdrawn_withdrawal!("wd-negative-#{SecureRandom.hex(4)}", amount: 1_000)

    available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)
    assert_equal(-3_400, available)
  end

  test "fee.waived can waive an NSF fee" do
    result = authorize_overdrawn_withdrawal!("wd-waive-#{SecureRandom.hex(4)}", amount: 1_000)

    waiver = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.waived",
      channel: "batch",
      idempotency_key: "waive-nsf-#{SecureRandom.hex(4)}",
      amount_minor_units: @policy.nsf_fee_minor_units,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: result[:fee_event].id.to_s
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: waiver.id)

    assert_equal "posted", waiver.reload.status
  end

  private

  def authorize_overdrawn_withdrawal!(idempotency_key, amount:)
    Accounts::Commands::AuthorizeDebit.call(
      event_type: "withdrawal.posted",
      channel: "batch",
      idempotency_key: idempotency_key,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )
  end

  def create_product!(prefix)
    Products::Models::DepositProduct.create!(
      product_code: "#{prefix}-#{SecureRandom.hex(4)}",
      name: prefix,
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  def create_policy!(product, attrs = {})
    Products::Models::DepositProductOverdraftPolicy.create!({
      deposit_product: product,
      mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
      nsf_fee_minor_units: 3_500,
      currency: "USD",
      status: Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end

  def open_account!(product)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "OD",
      last_name: SecureRandom.hex(3)
    )
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: product.id)
  end

  def fund_account!(account, amount)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "fund-od-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end
end
