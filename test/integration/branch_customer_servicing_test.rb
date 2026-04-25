# frozen_string_literal: true

require "test_helper"

class BranchCustomerServicingTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 10))
    @product = Products::Queries::FindDepositProduct.default_slice1!
    @teller = create_operator_with_credential!(role: "teller", username: "csr-teller")
    @supervisor = create_operator_with_credential!(role: "supervisor", username: "csr-supervisor")
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Csr", last_name: "Member")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id, deposit_product_id: @product.id)
  end

  test "branch customer search, customer 360, and account profile are available to branch roles" do
    internal_login!(username: "csr-teller")

    get branch_path
    assert_response :success
    assert_includes response.body, "Customer servicing"

    get branch_customers_path(query: "Member")
    assert_response :success
    assert_includes response.body, @party.name

    get branch_customer_path(@party)
    assert_response :success
    assert_includes response.body, "Linked deposit accounts"
    assert_includes response.body, @account.account_number

    get branch_servicing_deposit_account_path(@account)
    assert_response :success
    assert_includes response.body, "Available balance"
    assert_includes response.body, "Operational events"
  end

  test "branch account holds use branch channel and actor attribution" do
    internal_login!(username: "csr-teller")

    post branch_account_hold_placements_path(@account), params: {
      hold: {
        amount_minor_units: 800,
        currency: "USD",
        idempotency_key: "csr-place-hold"
      }
    }
    assert_response :created

    hold_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "csr-place-hold")
    assert_equal "hold.placed", hold_event.event_type
    assert_equal "branch", hold_event.channel
    assert_equal @teller.id, hold_event.actor_id

    post branch_account_hold_placements_path(@account), params: {
      hold: {
        amount_minor_units: 800,
        currency: "USD",
        idempotency_key: "csr-place-hold"
      }
    }
    assert_response :ok
    assert_equal 1, Core::OperationalEvents::Models::OperationalEvent.where(idempotency_key: "csr-place-hold").count

    post branch_account_hold_placements_path(@account), params: {
      hold: {
        amount_minor_units: 900,
        currency: "USD",
        idempotency_key: "csr-place-hold"
      }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "idempotency replay mismatch"

    hold = Accounts::Models::Hold.find_by!(placed_by_operational_event: hold_event)

    get branch_release_account_hold_path(@account, hold)
    assert_redirected_to branch_path
    delete logout_path

    internal_login!(username: "csr-supervisor")
    post branch_release_account_hold_path(@account, hold), params: {
      hold_release: { idempotency_key: "csr-release-hold" }
    }
    assert_response :created

    release_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "csr-release-hold")
    assert_equal "hold.released", release_event.event_type
    assert_equal "branch", release_event.channel
    assert_equal @supervisor.id, release_event.actor_id
    assert_equal Accounts::Models::Hold::STATUS_RELEASED, hold.reload.status
  end

  test "supervisor can waive a posted fee through posting flow" do
    fund_account!(amount: 10_000, key: "csr-fee-funding")
    fee_event = record_and_post_event!(
      event_type: "fee.assessed",
      amount: 1_000,
      key: "csr-fee-assessed"
    )

    internal_login!(username: "csr-supervisor")
    post branch_fee_waivers_path(@account), params: {
      fee_waiver: {
        fee_assessment_event_id: fee_event.id,
        idempotency_key: "csr-fee-waiver",
        record_and_post: "1"
      }
    }

    assert_response :created
    waiver = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "csr-fee-waiver")
    assert_equal "fee.waived", waiver.event_type
    assert_equal "branch", waiver.channel
    assert_equal @supervisor.id, waiver.actor_id
    assert_equal fee_event.id.to_s, waiver.reference_id
    assert_equal Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED, waiver.status
    assert waiver.journal_entries.exists?
  end

  test "supervisor can record and post reversal from branch channel" do
    original = fund_account!(amount: 2_500, key: "csr-reversal-original")

    internal_login!(username: "csr-supervisor")
    post branch_reversals_path, params: {
      reversal: {
        original_operational_event_id: original.id,
        idempotency_key: "csr-reversal",
        record_and_post: "1"
      }
    }

    assert_response :created
    reversal = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "csr-reversal")
    assert_equal "posting.reversal", reversal.event_type
    assert_equal "branch", reversal.channel
    assert_equal @supervisor.id, reversal.actor_id
    assert_equal original.id, reversal.reversal_of_event_id
    assert_equal reversal.id, original.reload.reversed_by_event_id
    assert_equal Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED, reversal.status
  end

  private

  def fund_account!(amount:, key:)
    record_and_post_event!(event_type: "deposit.accepted", amount: amount, key: key)
  end

  def record_and_post_event!(event_type:, amount:, key:)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: event_type,
      channel: "branch",
      idempotency_key: key,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      actor_id: @supervisor.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
    event.reload
  end
end
