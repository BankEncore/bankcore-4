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
    assert_includes response.body, 'id="csr"'
    assert_match(/customer servicing/i, response.body)

    get branch_customers_path(query: "Member")
    assert_response :success
    assert_includes response.body, @party.name

    get branch_customer_path(@party)
    assert_response :success
    assert_includes response.body, "Current deposit account relationships"
    assert_includes response.body, @account.account_number

    get branch_servicing_deposit_account_path(@account)
    assert_response :success
    assert_includes response.body, "Available balance"
    assert_includes response.body, "Operational events"
  end

  test "branch customer and account views show current and historical account-party relationships" do
    former_party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Former", last_name: "Signer")
    Accounts::Models::DepositAccountParty.create!(
      deposit_account: @account,
      party_record: former_party,
      role: Accounts::Models::DepositAccountParty::ROLE_JOINT_OWNER,
      status: Accounts::Models::DepositAccountParty::STATUS_INACTIVE,
      effective_on: Date.new(2026, 8, 1),
      ended_on: Date.new(2026, 8, 31)
    )

    internal_login!(username: "csr-teller")

    get branch_customer_path(@party)
    assert_response :success
    assert_includes response.body, "Current deposit account relationships"
    assert_includes response.body, "Historical deposit account relationships"
    assert_includes response.body, @account.account_number

    get branch_servicing_deposit_account_path(@account)
    assert_response :success
    assert_includes response.body, "Current parties"
    assert_includes response.body, "Historical parties (1)"
    assert_includes response.body, "Former Signer"
  end

  test "supervisor can add and end authorized signer with audit coverage" do
    signer = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Auth", last_name: "Signer")

    internal_login!(username: "csr-teller")
    get branch_new_account_authorized_signer_path(@account)
    assert_redirected_to branch_path
    delete logout_path

    internal_login!(username: "csr-supervisor")
    get branch_new_account_authorized_signer_path(@account)
    assert_response :success
    assert_includes response.body, "Add authorized signer"

    post branch_account_authorized_signers_path(@account), params: {
      authorized_signer: {
        party_record_id: signer.id,
        effective_on: "2026-09-10",
        idempotency_key: "branch-add-signer"
      }
    }
    assert_response :created
    assert_includes response.body, "authorized_signer.added"

    relationship = Accounts::Models::DepositAccountParty.find_by!(
      deposit_account: @account,
      party_record: signer,
      role: Accounts::Models::DepositAccountParty::ROLE_AUTHORIZED_SIGNER
    )
    audit = Accounts::Models::DepositAccountPartyMaintenanceAudit.find_by!(idempotency_key: "branch-add-signer")
    assert_equal "branch", audit.channel
    assert_equal @supervisor.id, audit.actor_id
    assert_equal relationship.id, audit.deposit_account_party_id

    get branch_servicing_deposit_account_path(@account)
    assert_response :success
    assert_includes response.body, "Auth Signer"
    assert_includes response.body, "End signer"

    post branch_end_account_authorized_signer_path(@account, relationship), params: {
      authorized_signer_end: {
        ended_on: "2026-09-10",
        idempotency_key: "branch-end-signer"
      }
    }
    assert_response :created
    assert_includes response.body, "authorized_signer.ended"

    end_audit = Accounts::Models::DepositAccountPartyMaintenanceAudit.find_by!(idempotency_key: "branch-end-signer")
    assert_equal @supervisor.id, end_audit.actor_id
    assert_equal Accounts::Models::DepositAccountParty::STATUS_INACTIVE, relationship.reload.status
  end

  test "branch account holds use branch channel and actor attribution" do
    get new_branch_hold_path, params: { deposit_account_id: @account.id, amount_minor_units: 800 }
    assert_redirected_to login_path

    internal_login!(username: "csr-teller")

    get new_branch_hold_path, params: { deposit_account_id: @account.id, amount_minor_units: 800 }
    assert_response :success
    assert_includes response.body, "Advisory preview"
    assert_includes response.body, "Source account available"

    post branch_account_hold_placements_path(@account), params: {
      hold: {
        amount_minor_units: 800,
        currency: "USD",
        hold_type: "legal",
        reason_code: "legal_order",
        reason_description: "Court order 456",
        expires_on: "2026-09-15",
        idempotency_key: "csr-place-hold"
      }
    }
    assert_response :created
    assert_includes response.body, "Funds are restricted due to a legal order."

    hold_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "csr-place-hold")
    assert_equal "hold.placed", hold_event.event_type
    assert_equal "branch", hold_event.channel
    assert_equal @teller.id, hold_event.actor_id

    post branch_account_hold_placements_path(@account), params: {
      hold: {
        amount_minor_units: 800,
        currency: "USD",
        hold_type: "legal",
        reason_code: "legal_order",
        reason_description: "Court order 456",
        expires_on: "2026-09-15",
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
    assert_equal "legal", hold.hold_type
    assert_equal "legal_order", hold.reason_code
    assert_equal "Court order 456", hold.reason_description
    assert_equal Date.new(2026, 9, 15), hold.expires_on

    get branch_release_account_hold_path(@account, hold)
    assert_redirected_to branch_path
    delete logout_path

    internal_login!(username: "csr-supervisor")
    post branch_release_account_hold_path(@account, hold), params: {
      hold_release: { idempotency_key: "csr-release-hold" }
    }
    assert_response :created
    assert_includes response.body, "hold.released"

    release_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "csr-release-hold")
    assert_equal "hold.released", release_event.event_type
    assert_equal "branch", release_event.channel
    assert_equal @supervisor.id, release_event.actor_id
    assert_equal Accounts::Models::Hold::STATUS_RELEASED, hold.reload.status

    post release_branch_holds_path, params: {
      hold_release: { hold_id: hold.id, idempotency_key: "csr-release-hold-global-replay" }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "hold is not active"

    fresh_hold_result = Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 100,
      currency: "USD",
      channel: "branch",
      idempotency_key: "csr-place-global-hold",
      actor_id: @supervisor.id,
      operating_unit_id: @supervisor.default_operating_unit_id
    )
    fresh_hold = fresh_hold_result[:hold]

    post release_branch_holds_path, params: {
      hold_release: { hold_id: fresh_hold.id, idempotency_key: "csr-release-global-hold" }
    }
    assert_response :created
    assert_includes response.body, "Hold trace"
    assert_includes response.body, "No-GL evidence"
    assert_includes response.body, "Event detail"
    assert_includes response.body, "Account holds"
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
    get new_branch_reversal_path(original_operational_event_id: original.id)
    assert_response :success
    assert_includes response.body, "Original event preview"
    assert_includes response.body, "deposit.accepted"
    assert_includes response.body, "Posting expected"

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
    assert_includes response.body, "Event detail"
    assert_includes response.body, "Source activity"
  end

  test "supervisor can restrict release and close account from branch servicing" do
    internal_login!(username: "csr-supervisor")

    get branch_new_account_restriction_path(@account)
    assert_response :success
    assert_includes response.body, "Restrict account"

    post branch_account_restrictions_path(@account), params: {
      restriction: {
        restriction_type: "watch_only",
        reason_code: "support_review",
        reason_description: "Documented customer review",
        effective_on: "2026-09-10",
        idempotency_key: "branch-watch-only"
      }
    }
    assert_redirected_to branch_servicing_deposit_account_path(@account)
    follow_redirect!
    assert_includes response.body, "Account restrictions"
    assert_includes response.body, "watch_only"

    restriction = Accounts::Models::AccountRestriction.find_by!(idempotency_key: "branch-watch-only")
    assert_equal "account.restricted", restriction.restricted_operational_event.event_type

    post branch_release_account_restriction_path(@account, restriction), params: {
      idempotency_key: "branch-release-watch"
    }
    assert_redirected_to branch_servicing_deposit_account_path(@account)
    assert_equal Accounts::Models::AccountRestriction::STATUS_RELEASED, restriction.reload.status
    assert_equal "account.unrestricted", restriction.unrestricted_operational_event.event_type

    get branch_close_account_path(@account)
    assert_response :success
    assert_includes response.body, "Close account"

    post branch_close_account_path(@account), params: {
      account_close: {
        reason_code: "customer_request",
        reason_description: "Customer requested close",
        effective_on: "2026-09-10",
        idempotency_key: "branch-close-account"
      }
    }
    assert_redirected_to branch_servicing_deposit_account_path(@account)
    follow_redirect!
    assert_includes response.body, "closed"
    assert_equal Accounts::Models::DepositAccount::STATUS_CLOSED, @account.reload.status
    assert_equal "account.closed", Accounts::Models::AccountLifecycleEvent.find_by!(idempotency_key: "branch-close-account").operational_event.event_type
  end

  test "supervisor can update party contact with party-owned audit evidence" do
    internal_login!(username: "csr-supervisor")

    get branch_new_party_contact_path(@party)
    assert_response :success
    assert_includes response.body, "Update contact"

    post branch_party_contacts_path(@party), params: {
      contact: {
        contact_type: "email",
        purpose: "primary",
        value: "member@example.test",
        effective_on: "2026-09-10",
        idempotency_key: "branch-contact-email"
      }
    }
    assert_redirected_to branch_customer_path(@party)
    follow_redirect!
    assert_includes response.body, "member@example.test"
    assert_includes response.body, "Contact audit"

    audit = Party::Models::PartyContactAudit.find_by!(idempotency_key: "branch-contact-email")
    assert_equal "party_emails", audit.contact_table
    assert_equal @supervisor.id, audit.actor_id
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
