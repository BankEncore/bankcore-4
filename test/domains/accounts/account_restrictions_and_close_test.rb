# frozen_string_literal: true

require "test_helper"

class AccountsAccountRestrictionsAndCloseTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::Rbac.seed!
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 10))
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Restrict", last_name: "Member")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @operator = Workspace::Models::Operator.create!(
      role: "supervisor",
      display_name: "Restriction Supervisor",
      active: true,
      default_operating_unit: Organization::Services::DefaultOperatingUnit.branch
    )
  end

  test "restricts and unreleases account with no-gl operational evidence" do
    result = Accounts::Commands::RestrictAccount.call(
      deposit_account_id: @account.id,
      restriction_type: Accounts::Models::AccountRestriction::TYPE_DEBIT_BLOCK,
      reason_code: "fraud_review",
      idempotency_key: "restrict-account",
      actor_id: @operator.id
    )

    assert_equal :created, result[:outcome]
    assert_equal "account.restricted", result[:event].event_type
    assert_equal Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED, result[:event].status
    assert_equal Accounts::Models::AccountRestriction::STATUS_ACTIVE, result[:restriction].status

    replay = Accounts::Commands::RestrictAccount.call(
      deposit_account_id: @account.id,
      restriction_type: Accounts::Models::AccountRestriction::TYPE_DEBIT_BLOCK,
      reason_code: "fraud_review",
      idempotency_key: "restrict-account",
      actor_id: @operator.id
    )
    assert_equal :replay, replay[:outcome]

    release = Accounts::Commands::UnrestrictAccount.call(
      account_restriction_id: result[:restriction].id,
      idempotency_key: "unrestrict-account",
      actor_id: @operator.id
    )
    assert_equal :created, release[:outcome]
    assert_equal "account.unrestricted", release[:event].event_type
    assert_equal Accounts::Models::AccountRestriction::STATUS_RELEASED, release[:restriction].status
  end

  test "debit-block restriction rejects debit authorization" do
    Accounts::Commands::RestrictAccount.call(
      deposit_account_id: @account.id,
      restriction_type: Accounts::Models::AccountRestriction::TYPE_DEBIT_BLOCK,
      reason_code: "fraud_review",
      idempotency_key: "restrict-debit",
      actor_id: @operator.id
    )

    error = assert_raises(Accounts::Commands::AuthorizeDebit::InvalidRequest) do
      Accounts::Commands::AuthorizeDebit.call(
        event_type: "withdrawal.posted",
        channel: "branch",
        idempotency_key: "restricted-withdrawal",
        amount_minor_units: 100,
        currency: "USD",
        source_account_id: @account.id,
        actor_id: @operator.id
      )
    end
    assert_match(/active debit restriction/, error.message)
  end

  test "closes zero-balance account and blocks close on close restriction" do
    Accounts::Commands::RestrictAccount.call(
      deposit_account_id: @account.id,
      restriction_type: Accounts::Models::AccountRestriction::TYPE_CLOSE_BLOCK,
      reason_code: "estate_review",
      idempotency_key: "restrict-close",
      actor_id: @operator.id
    )

    assert_raises(Accounts::Commands::CloseAccount::InvalidRequest) do
      Accounts::Commands::CloseAccount.call(
        deposit_account_id: @account.id,
        reason_code: "customer_request",
        idempotency_key: "close-blocked",
        actor_id: @operator.id
      )
    end

    restriction = Accounts::Models::AccountRestriction.find_by!(idempotency_key: "restrict-close")
    Accounts::Commands::UnrestrictAccount.call(
      account_restriction_id: restriction.id,
      idempotency_key: "release-close-block",
      actor_id: @operator.id
    )

    result = Accounts::Commands::CloseAccount.call(
      deposit_account_id: @account.id,
      reason_code: "customer_request",
      idempotency_key: "close-account",
      actor_id: @operator.id
    )
    assert_equal :created, result[:outcome]
    assert_equal "account.closed", result[:event].event_type
    assert_equal Accounts::Models::DepositAccount::STATUS_CLOSED, @account.reload.status
    assert_equal result[:event].id, result[:lifecycle_event].operational_event_id
  end
end
