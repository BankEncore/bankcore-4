# frozen_string_literal: true

# Populates the development database with sample domain data (party, deposit account,
# operational events). Run from the app root:
#
#   bin/rails runner script/development_sample_data.rb
#
# In Docker (development Compose):
#
#   docker compose run --rm web bin/rails runner script/development_sample_data.rb
#
# Or: bin/dev-seed-sample-data

require_relative "../lib/bank_core/seeds/gl_coa"
require_relative "../lib/bank_core/seeds/deposit_products"
require_relative "../lib/bank_core/seeds/operating_units"
require_relative "../lib/bank_core/seeds/operators"
require_relative "../lib/bank_core/seeds/rbac"
require_relative "../lib/bank_core/seeds/cash_inventory"

unless Rails.env.development?
  warn "development_sample_data.rb is for development only (current RAILS_ENV=#{Rails.env.inspect})."
  exit 1
end

BankCore::Seeds::GlCoa.seed!
BankCore::Seeds::DepositProducts.seed!
BankCore::Seeds::OperatingUnits.seed!

if Core::BusinessDate::Models::BusinessDateSetting.none?
  Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.current)
end

BankCore::Seeds::Operators.seed!
BankCore::Seeds::Rbac.seed!
BankCore::Seeds::CashInventory.seed!

stamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")
teller = Workspace::Models::Operator.find_by!(role: "teller")
supervisor = Workspace::Models::Operator.find_by!(role: "supervisor")
branch = Organization::Services::DefaultOperatingUnit.branch!
vault = Cash::Models::CashLocation.active.find_by!(
  operating_unit: branch,
  location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT
)

party = Party::Commands::CreateParty.call(
  party_type: "individual",
  first_name: "Dev",
  middle_name: "Sample",
  last_name: "Customer-#{stamp}"
)

account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)

cash_session = Teller::Commands::OpenSession.call(drawer_code: "dev-sample-#{stamp}", operator_id: teller.id)

if vault.cash_balance.amount_minor_units.to_i < 2_500
  Cash::Commands::RecordCashCount.call(
    cash_location_id: vault.id,
    counted_amount_minor_units: 10_000,
    expected_amount_minor_units: vault.cash_balance.amount_minor_units,
    actor_id: supervisor.id,
    idempotency_key: "dev-sample-#{stamp}-vault-opening-count",
    channel: "branch"
  )
end

cash_transfer = Cash::Commands::TransferCash.call(
  source_cash_location_id: vault.id,
  destination_cash_location_id: cash_session.cash_location_id,
  amount_minor_units: 2_500,
  actor_id: teller.id,
  approval_actor_id: supervisor.id,
  idempotency_key: "dev-sample-#{stamp}-vault-to-drawer",
  channel: "branch"
)

posted = Core::OperationalEvents::Commands::RecordEvent.call(
  event_type: "deposit.accepted",
  channel: "teller",
  idempotency_key: "dev-seed-#{stamp}-posted",
  amount_minor_units: 100_00,
  currency: "USD",
  source_account_id: account.id,
  teller_session_id: cash_session.id
)

posted_result = Core::Posting::Commands::PostEvent.call(operational_event_id: posted[:event].id)

pending = Core::OperationalEvents::Commands::RecordEvent.call(
  event_type: "deposit.accepted",
  channel: "teller",
  idempotency_key: "dev-seed-#{stamp}-pending",
  amount_minor_units: 25_00,
  currency: "USD",
  source_account_id: account.id,
  teller_session_id: cash_session.id
)

puts <<~SUMMARY
  Development sample data created.

    party_id:              #{party.id}
    party_name:            #{party.name}
    deposit_account_id:    #{account.id}
    deposit_account_number: #{account.account_number}

    operational_event (posted):   id=#{posted[:event].id}  outcome=#{posted_result[:outcome]}  amount_minor_units=10000
    operational_event (pending): id=#{pending[:event].id}  status=#{pending[:event].status}  amount_minor_units=2500
    cash_transfer:                id=#{cash_transfer.id}  status=#{cash_transfer.status}  amount_minor_units=2500
    teller_cash_location_id:      #{cash_session.cash_location_id}

  Re-run anytime; each run uses a new idempotency stamp and adds new rows.
SUMMARY
