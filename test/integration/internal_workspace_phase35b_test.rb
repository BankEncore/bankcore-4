# frozen_string_literal: true

require "test_helper"
require "tempfile"

class InternalWorkspacePhase35bTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @teller = create_operator_with_credential!(role: "teller", username: "branch-teller")
    @operations = create_operator_with_credential!(role: "operations", username: "ops-user")
    @admin = create_operator_with_credential!(role: "admin", username: "admin-user")
  end

  test "branch workspace exposes session and transaction parity routes" do
    internal_login!(username: "branch-teller")

    get branch_path
    assert_response :success
    assert_includes response.body, "Open session"
    assert_includes response.body, "Transfer"
    assert_includes response.body, "Place hold"

    get new_branch_teller_session_path
    assert_response :success
    assert_includes response.body, "Open teller session"

    get new_branch_transfer_path
    assert_response :success
    assert_includes response.body, "Record transfer"

    get new_branch_hold_path
    assert_response :success
    assert_includes response.body, "Place hold"

    get branch_operational_events_path
    assert_response :success
    assert_includes response.body, "Branch operational events"
  end

  test "ops workspace exposes close package and exception queues" do
    internal_login!(username: "ops-user")

    get ops_path
    assert_response :success
    assert_includes response.body, "Close package"
    assert_includes response.body, "Exception queues"
    assert_includes response.body, "ACH receipt ingestion"

    get ops_close_package_path
    assert_response :success
    assert_includes response.body, "Close package"

    get ops_exceptions_path
    assert_response :success
    assert_includes response.body, "Exception queues"
  end

  test "ops search and close package expose support observability evidence" do
    account = open_account!
    event = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "fee.assessed",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: Date.new(2026, 4, 22),
      channel: "branch",
      idempotency_key: "ops-support-event",
      amount_minor_units: 125,
      currency: "USD",
      source_account_id: account.id,
      reference_id: "support-case-123",
      actor_id: @operations.id
    )

    internal_login!(username: "ops-user")

    get ops_operational_events_path(reference_id: "support-case-123")
    assert_response :success
    assert_includes response.body, "Support keys"
    assert_includes response.body, "Reference: support-case-123"
    assert_includes response.body, "Idempotency: ops-support-event"
    assert_includes response.body, "##{event.id}"

    get ops_close_package_path
    assert_response :success
    assert_includes response.body, "EOD impact evidence"
    assert_includes response.body, "By channel"
    assert_includes response.body, "branch"
    assert_includes response.body, "fee.assessed"
  end

  test "ops support search finds ACH receipt items by reference and idempotency keys" do
    account = open_account!
    ach = Integration::Ach::Commands::IngestReceiptFile.call(
      file_id: "file-ops-ach-001",
      batches: [
        {
          batch_id: "batch-1",
          items: [
            {
              item_id: "trace-ops-001",
              account_number: account.account_number,
              amount_minor_units: 12_500,
              currency: "USD"
            }
          ]
        }
      ]
    )
    row = ach.outcomes.sole

    internal_login!(username: "ops-user")

    get ops_operational_events_path(reference_id: row.fetch(:reference_id))
    assert_response :success
    assert_includes response.body, "ach.credit.received"
    assert_includes response.body, "Reference: ach:file-ops-ach-001:batch-1:trace-ops-001"
    assert_includes response.body, "Idempotency: ach-credit-received:file-ops-ach-001:batch-1:trace-ops-001"
    assert_includes response.body, "##{row.fetch(:operational_event_id)}"

    get ops_operational_events_path(idempotency_key: row.fetch(:idempotency_key))
    assert_response :success
    assert_includes response.body, "ach.credit.received"
    assert_includes response.body, "##{row.fetch(:operational_event_id)}"
  end

  test "ops can preview and ingest structured ACH receipt upload" do
    account = open_account!

    internal_login!(username: "ops-user")

    get ops_new_ach_receipt_ingestion_path
    assert_response :success
    assert_includes response.body, "ACH receipt ingestion"
    assert_includes response.body, "Structured JSON file"
    assert_includes response.body, "Ingest and post"

    payload = {
      file_id: "file-ops-form-001",
      batches: [
        {
          batch_id: "batch-1",
          items: [
            {
              item_id: "trace-form-001",
              account_number: account.account_number,
              amount_minor_units: 12_500,
              currency: "USD"
            }
          ]
        }
      ]
    }

    post ops_ach_receipt_ingestions_path,
      params: {
        mode: "preview",
        ach_receipt_ingestion: {
          structured_input: JSON.pretty_generate(payload),
          business_date: "2026-04-22"
        }
      }
    assert_response :success
    assert_includes response.body, "ACH receipt preview"
    assert_includes response.body, "preview: ACH credit would be posted"
    assert_equal 0, Core::OperationalEvents::Models::OperationalEvent.where(event_type: "ach.credit.received").count

    Tempfile.create([ "ach-receipt", ".json" ]) do |file|
      file.write(JSON.generate(payload))
      file.rewind

      post ops_ach_receipt_ingestions_path,
        params: {
          mode: "ingest",
          ach_receipt_ingestion: {
            receipt_file: Rack::Test::UploadedFile.new(file.path, "application/json"),
            business_date: "2026-04-22"
          }
        }
    end

    assert_response :created
    assert_includes response.body, "ACH receipt results"
    assert_includes response.body, "ACH credit posted"
    assert_includes response.body, "ach:file-ops-form-001:batch-1:trace-form-001"
    assert_includes response.body, "ach-credit-received:file-ops-form-001:batch-1:trace-form-001"
    event = Core::OperationalEvents::Models::OperationalEvent.find_by!(event_type: "ach.credit.received")
    assert_equal "posted", event.status
    assert_equal 1, event.posting_batches.count
  end

  test "admin product workspace exposes readiness review" do
    internal_login!(username: "admin-user")
    product = Products::Queries::FindDepositProduct.default_slice1!

    get admin_deposit_product_path(product)
    assert_response :success
    assert_includes response.body, "Readiness"

    get admin_deposit_product_readiness_path(product)
    assert_response :success
    assert_includes response.body, "Product readiness"
  end

  private

  def open_account!
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Ops", last_name: SecureRandom.hex(3))
    Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end
end
