# frozen_string_literal: true

require "test_helper"

class BranchTransactionFormsTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 8, 1))
    @teller = create_operator_with_credential!(role: "teller", username: "branch-forms-teller")
    @supervisor = create_operator_with_credential!(role: "supervisor", username: "branch-forms-supervisor")
    @product = Products::Queries::FindDepositProduct.default_slice1!
  end

  test "branch transaction forms are available to branch roles and forbidden to other internal roles" do
    internal_login!(username: "branch-forms-teller")
    get "/branch/deposits/new"
    assert_response :success
    delete "/logout"

    internal_login!(username: "branch-forms-supervisor")
    get "/branch/withdrawals/new"
    assert_response :success
    delete "/logout"

    create_operator_with_credential!(role: "operations", username: "branch-forms-ops")
    internal_login!(username: "branch-forms-ops")
    get "/branch/deposits/new"
    assert_response :forbidden
    delete "/logout"

    create_operator_with_credential!(role: "admin", username: "branch-forms-admin")
    internal_login!(username: "branch-forms-admin")
    get "/branch/deposit_accounts/new"
    assert_response :forbidden
  end

  test "branch supervisor can receive external cash shipment and teller cannot" do
    vault = Cash::Commands::CreateLocation.call(
      location_type: "branch_vault",
      operating_unit_id: @supervisor.default_operating_unit_id,
      actor_id: @supervisor.id
    )

    internal_login!(username: "branch-forms-teller")
    get "/branch/cash/shipments/received/new"
    assert_redirected_to "/branch"
    delete "/logout"

    internal_login!(username: "branch-forms-supervisor")
    get "/branch/cash/shipments/received/new"
    assert_response :success
    assert_includes response.body, "cash_shipment[shipment_reference]"

    post "/branch/cash/shipments/received", params: {
      cash_shipment: {
        destination_cash_location_id: vault.id,
        amount_minor_units: 90_000,
        external_source: "Federal Reserve",
        shipment_reference: "UI-FRB-001",
        idempotency_key: "ui-fed-cash-receipt"
      }
    }

    assert_redirected_to "/branch/cash"
    movement = Cash::Models::CashMovement.find_by!(idempotency_key: "ui-fed-cash-receipt")
    assert_equal Cash::Models::CashMovement::TYPE_EXTERNAL_SHIPMENT_RECEIVED, movement.movement_type
    assert_equal 90_000, vault.cash_balance.reload.amount_minor_units
    assert_equal "posted", movement.operational_event.status
  end

  test "branch cash transfer form renders advisory preview" do
    source = create_cash_location!(
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
      name: "Source Vault"
    )
    destination = create_cash_location!(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      name: "Destination Drawer",
      drawer_code: "cash-preview-drawer"
    )
    create_cash_balance!(source, 5_000)
    create_cash_balance!(destination, 500)

    internal_login!(username: "branch-forms-supervisor")
    get "/branch/cash/transfers/new", params: {
      source_cash_location_id: source.id,
      destination_cash_location_id: destination.id,
      amount_minor_units: 1_200
    }

    assert_response :success
    assert_includes response.body, "Transaction impact preview"
    assert_includes response.body, "Source cash location"
    assert_includes response.body, "Destination cash location"
    assert_includes response.body, "Projected cash balance"

    post "/branch/cash/transfers", params: {
      cash_transfer: {
        source_cash_location_id: source.id,
        destination_cash_location_id: destination.id,
        amount_minor_units: 1_200,
        reason_code: "drawer_funding",
        idempotency_key: "branch-cash-transfer-result"
      }
    }
    assert_response :created
    assert_includes response.body, "Cash movement recorded"
    assert_includes response.body, "Cash movement"
    assert_includes response.body, "Approval required"
  end

  test "branch supervisor panel approves cash movement with inline credentials" do
    source = create_cash_location!(
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
      name: "Inline Source Vault"
    )
    destination = create_cash_location!(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      name: "Inline Destination Drawer",
      drawer_code: "inline-cash-approval"
    )
    create_cash_balance!(source, 4_000)
    create_cash_balance!(destination, 0)
    movement = Cash::Commands::TransferCash.call(
      source_cash_location_id: source.id,
      destination_cash_location_id: destination.id,
      amount_minor_units: 1_000,
      actor_id: @teller.id,
      idempotency_key: "branch-inline-cash-movement"
    )

    internal_login!(username: "branch-forms-teller")
    get "/branch#supervisor"
    assert_response :success
    assert_includes response.body, "Supervisor control catalog"
    assert_includes response.body, "Approve cash movement"

    post branch_approve_cash_movement_path(movement), params: {
      cash_movement_approval: {
        supervisor_username: "branch-forms-supervisor",
        supervisor_password: "password123"
      }
    }

    assert_redirected_to "/branch#supervisor"
    assert_equal Cash::Models::CashMovement::STATUS_COMPLETED, movement.reload.status
    assert_equal @supervisor.id, movement.approving_actor_id
    assert_equal "cash.movement.completed", movement.operational_event.event_type
  end

  test "branch cash movement inline approval preserves no self approval" do
    source = create_cash_location!(
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
      name: "Self Approval Source Vault"
    )
    destination = create_cash_location!(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      name: "Self Approval Destination Drawer",
      drawer_code: "self-cash-approval"
    )
    create_cash_balance!(source, 4_000)
    movement = Cash::Commands::TransferCash.call(
      source_cash_location_id: source.id,
      destination_cash_location_id: destination.id,
      amount_minor_units: 1_000,
      actor_id: @supervisor.id,
      idempotency_key: "branch-inline-cash-self-approval"
    )

    internal_login!(username: "branch-forms-teller")
    post branch_approve_cash_movement_path(movement), params: {
      cash_movement_approval: {
        supervisor_username: "branch-forms-supervisor",
        supervisor_password: "password123"
      }
    }

    assert_redirected_to "/branch#supervisor"
    assert_match(/approver must not be the initiator/i, flash[:alert].to_s)
    assert_equal Cash::Models::CashMovement::STATUS_PENDING_APPROVAL, movement.reload.status
  end

  test "branch cash count renders result envelope" do
    location = create_cash_location!(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      name: "Count Drawer",
      drawer_code: "count-result-drawer"
    )
    create_cash_balance!(location, 2_500)

    internal_login!(username: "branch-forms-supervisor")
    post "/branch/cash/counts", params: {
      cash_count: {
        cash_location_id: location.id,
        counted_amount_minor_units: 2_750,
        expected_amount_minor_units: 2_500,
        idempotency_key: "branch-cash-count-result"
      }
    }

    assert_response :created
    assert_includes response.body, "Cash count recorded"
    assert_includes response.body, "Cash variance"
    assert_includes response.body, "Variance approval required"
    assert_includes response.body, "Trace receipt"
  end

  test "party creation redirects to open account form and unsupported party renders validation" do
    internal_login!(username: "branch-forms-teller")

    post "/branch/parties", params: {
      party: { party_type: "individual", first_name: "Sam", last_name: "Rivera" }
    }

    party = Party::Models::PartyRecord.order(:id).last
    assert_redirected_to "/branch/deposit_accounts/new?party_record_id=#{party.id}"

    post "/branch/parties", params: {
      party: { party_type: "business", first_name: "Bad", last_name: "Type" }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "slice 1 supports individual only"
  end

  test "deposit account form opens account and renders known errors" do
    primary = create_party!("Primary", "Owner")
    joint = create_party!("Joint", "Owner")
    internal_login!(username: "branch-forms-teller")

    post "/branch/deposit_accounts", params: {
      deposit_account: {
        party_record_id: primary.id,
        joint_party_record_id: joint.id,
        deposit_product_id: @product.id
      }
    }

    account = Accounts::Models::DepositAccount.order(:id).last
    assert_redirected_to "/branch/deposits/new?deposit_account_id=#{account.id}"

    post "/branch/deposit_accounts", params: {
      deposit_account: { party_record_id: 0 }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "party_record_id=0 not found"

    post "/branch/deposit_accounts", params: {
      deposit_account: { party_record_id: primary.id, joint_party_record_id: primary.id }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "joint_party_record_id must differ from party_record_id"

    post "/branch/deposit_accounts", params: {
      deposit_account: { party_record_id: primary.id, deposit_product_id: 0 }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "Products::Models::DepositProduct"
  end

  test "deposit form can record only and explicit post later" do
    account = open_account!
    session = open_session!
    internal_login!(username: "branch-forms-teller")

    post "/branch/deposits", params: {
      deposit: transaction_params(account: account, session: session, amount: 2_500, key: "branch-deposit-record")
    }

    assert_response :created
    event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-deposit-record")
    assert_equal "pending", event.status
    assert_equal @teller.default_operating_unit_id, event.operating_unit_id
    assert_includes response.body, "Post event"

    post branch_event_post_path(event)
    assert_redirected_to branch_event_path(event)
    assert_equal "posted", event.reload.status
  end

  test "cash deposit and withdrawal forms show operator-facing inputs" do
    account = open_account!
    session = open_session!
    internal_login!(username: "branch-forms-teller")

    get "/branch/deposits/new", params: {
      deposit_account_number: account.account_number,
      teller_session_id: session.id,
      amount_minor_units: 1_500
    }

    assert_response :success
    assert_includes response.body, "deposit[deposit_account_number]"
    assert_includes response.body, "deposit[amount]"
    assert_select "input[name='deposit[amount]'][value='15.00']"
    assert_select "select[name='deposit[teller_session_id]']"
    assert_includes response.body, session.drawer_code
    assert_includes response.body, "Transaction impact preview"
    assert_includes response.body, "Cash in"
    assert_includes response.body, "Drawer cash after submit"
    assert_not_includes response.body, "Amount minor units"
    assert_not_includes response.body, "Enter an internal numeric ID"
    assert_not_includes response.body, "Idempotency key"

    get "/branch/withdrawals/new", params: {
      deposit_account_number: account.account_number,
      teller_session_id: session.id,
      amount_minor_units: 500
    }

    assert_response :success
    assert_includes response.body, "withdrawal[deposit_account_number]"
    assert_includes response.body, "withdrawal[amount]"
    assert_select "input[name='withdrawal[amount]'][value='5.00']"
    assert_select "select[name='withdrawal[teller_session_id]']"
    assert_not_includes response.body, "Amount minor units"
    assert_not_includes response.body, "Enter an internal numeric ID"
    assert_not_includes response.body, "Idempotency key"
  end

  test "cash transaction forms show open-session guidance when no sessions are open" do
    internal_login!(username: "branch-forms-teller")

    get "/branch/deposits/new"

    assert_response :success
    assert_includes response.body, "Open a teller session first"
    assert_select "a[href='#{new_branch_teller_session_path}']", "Open teller session"
    assert_select "select[name='deposit[teller_session_id]'][disabled='disabled']"
    assert_select "input[type='submit'][disabled='disabled']"
  end

  test "deposit form can record and post immediately and requires open teller session" do
    account = open_account!
    session = open_session!
    internal_login!(username: "branch-forms-teller")

    get "/branch/deposits/new", params: {
      deposit_account_id: account.id,
      teller_session_id: session.id,
      amount_minor_units: 1_500
    }
    assert_response :success
    assert_includes response.body, "deposit[deposit_account_number]"
    assert_includes response.body, "Transaction impact preview"
    assert_includes response.body, "Event type"
    assert_includes response.body, "Cash in"
    assert_includes response.body, "Drawer cash after submit"

    post "/branch/deposits", params: {
      deposit: transaction_params(account: account, session: session, amount: 3_000, key: "branch-deposit-post", record_and_post: "1")
    }

    assert_response :created
    event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-deposit-post")
    assert_equal "posted", event.status
    assert_includes response.body, "Post outcome"
    assert_includes response.body, "Posting batches"
    assert_includes response.body, "Journal entries"
    assert_includes response.body, "Trace receipt"

    post "/branch/deposits", params: {
      deposit: {
        deposit_account_number: account.account_number,
        amount: "7.50",
        currency: "USD",
        teller_session_id: session.id,
        idempotency_key: "branch-deposit-number-lookup",
        record_and_post: "1"
      }
    }
    assert_response :created
    number_lookup_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-deposit-number-lookup")
    assert_equal account.id, number_lookup_event.source_account_id

    post "/branch/deposits", params: {
      deposit: transaction_params(account: account, session: nil, amount: 1_000, key: "branch-deposit-no-session")
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "teller_session_id is required"
  end

  test "cash transaction decimal amounts normalize before existing command calls" do
    account = open_account!
    session = open_session!
    internal_login!(username: "branch-forms-teller")

    {
      "10" => 1_000,
      "10.5" => 1_050,
      "10.50" => 1_050,
      "1,234.56" => 123_456
    }.each_with_index do |(display_amount, expected_minor_units), index|
      post "/branch/deposits", params: {
        deposit: cash_transaction_params(
          account: account,
          session: session,
          amount: display_amount,
          key: "branch-deposit-decimal-#{index}"
        )
      }

      assert_response :created
      event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-deposit-decimal-#{index}")
      assert_equal expected_minor_units, event.amount_minor_units
      assert_equal account.id, event.source_account_id
    end
  end

  test "cash transaction amount validation rerenders with entered context" do
    account = open_account!
    session = open_session!
    internal_login!(username: "branch-forms-teller")

    [ "1,23.45", "10.999", "0", "-1.00" ].each_with_index do |amount, index|
      key = "branch-deposit-invalid-amount-#{index}"

      post "/branch/deposits", params: {
        deposit: cash_transaction_params(account: account, session: session, amount: amount, key: key)
      }

      assert_response :unprocessable_entity
      assert_includes response.body, "amount must be greater than 0"
      assert_select "input[name='deposit[amount]'][value='#{amount}']"
      assert_select "input[name='deposit[deposit_account_number]'][value='#{account.account_number}']"
      assert_select "select[name='deposit[teller_session_id]']"
      assert_includes response.body, "value=\"#{key}\""
      assert_nil Core::OperationalEvents::Models::OperationalEvent.find_by(idempotency_key: key)
    end
  end

  test "withdrawal form can record only and record-and-post" do
    account = funded_account!(amount: 10_000)
    session = open_session!
    internal_login!(username: "branch-forms-teller")

    post "/branch/withdrawals", params: {
      withdrawal: cash_transaction_params(account: account, session: session, amount: "20.00", key: "branch-withdrawal-record")
    }

    assert_response :created
    record_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-withdrawal-record")
    assert_equal "pending", record_event.status
    assert_equal 2_000, record_event.amount_minor_units
    assert_equal account.id, record_event.source_account_id
    assert_includes response.body, "Post event"

    post "/branch/withdrawals", params: {
      withdrawal: cash_transaction_params(account: account, session: session, amount: "10", key: "branch-withdrawal-post", record_and_post: "1")
    }

    assert_response :created
    posted_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-withdrawal-post")
    assert_equal "posted", posted_event.status
    assert_equal @teller.default_operating_unit_id, posted_event.operating_unit_id
  end

  test "withdrawal form renders NSF denial and fee ids" do
    account = open_account!
    session = open_session!
    internal_login!(username: "branch-forms-teller")

    get "/branch/withdrawals/new", params: {
      deposit_account_id: account.id,
      teller_session_id: session.id,
      amount_minor_units: 5_000
    }
    assert_response :success
    assert_includes response.body, "Transaction impact preview"
    assert_includes response.body, "Projected available balance would be negative"

    post "/branch/withdrawals", params: {
      withdrawal: transaction_params(account: account, session: session, amount: 5_000, key: "branch-withdrawal-nsf")
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "Withdrawal denied for NSF"
    denial = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-withdrawal-nsf")
    assert_equal "overdraft.nsf_denied", denial.event_type
    assert_equal @teller.default_operating_unit_id, denial.operating_unit_id
    assert_includes response.body, "Denial event"
    assert_includes response.body, "Fee event"
  end

  test "transfer form uses shared envelope and renders trace output" do
    source = funded_account!(amount: 10_000)
    destination = open_account!
    internal_login!(username: "branch-forms-teller")

    get "/branch/transfers/new", params: {
      source_account_id: source.id,
      destination_account_id: destination.id,
      amount_minor_units: 2_500
    }
    assert_response :success
    assert_includes response.body, "transfer[source_account_id]"
    assert_includes response.body, "transfer[destination_account_id]"
    assert_includes response.body, "Transaction impact preview"
    assert_includes response.body, "Source account balance movement"
    assert_includes response.body, "Destination account balance movement"

    post "/branch/transfers", params: {
      transfer: {
        source_account_id: source.id,
        destination_account_id: destination.id,
        amount_minor_units: 2_500,
        currency: "USD",
        idempotency_key: "branch-transfer-post",
        record_and_post: "1"
      }
    }

    assert_response :created
    event = Core::OperationalEvents::Models::OperationalEvent.find_by!(idempotency_key: "branch-transfer-post")
    assert_equal "posted", event.status
    assert_includes response.body, "Source account"
    assert_includes response.body, "Destination account"
    assert_includes response.body, "Posting batches"
    assert_includes response.body, "Journal entries"
  end

  test "existing teller json flow remains unchanged" do
    json_teller, = create_workspace_operators!

    post "/teller/parties",
      params: { party_type: "individual", first_name: "Json", last_name: "Flow" }.to_json,
      headers: teller_json_headers(json_teller)

    assert_response :created
  end

  private

  def create_party!(first_name, last_name)
    Party::Commands::CreateParty.call(party_type: "individual", first_name: first_name, last_name: last_name)
  end

  def open_account!
    party = create_party!("Acct", SecureRandom.hex(3))
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
  end

  def open_session!
    Teller::Commands::OpenSession.call(drawer_code: "branch-form-#{SecureRandom.hex(6)}", operator_id: @teller.id)
  end

  def funded_account!(amount:)
    account = open_account!
    session = open_session!
    result = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: "funding-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id,
      teller_session_id: session.id,
      actor_id: @teller.id
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: result[:event].id)
    account
  end

  def create_cash_location!(location_type:, name:, drawer_code: nil)
    Cash::Models::CashLocation.create!(
      location_type: location_type,
      operating_unit: Organization::Services::DefaultOperatingUnit.branch,
      drawer_code: drawer_code,
      name: name,
      currency: "USD",
      status: Cash::Models::CashLocation::STATUS_ACTIVE
    )
  end

  def create_cash_balance!(location, amount_minor_units)
    Cash::Models::CashBalance.create!(
      cash_location: location,
      currency: "USD",
      amount_minor_units: amount_minor_units
    )
  end

  def transaction_params(account:, session:, amount:, key:, record_and_post: "0")
    {
      deposit_account_id: account.id,
      amount_minor_units: amount,
      currency: "USD",
      teller_session_id: session&.id,
      idempotency_key: key,
      record_and_post: record_and_post
    }
  end

  def cash_transaction_params(account:, session:, amount:, key:, record_and_post: "0")
    {
      deposit_account_number: account.account_number,
      amount: amount,
      currency: "USD",
      teller_session_id: session&.id,
      idempotency_key: key,
      record_and_post: record_and_post
    }
  end
end
