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

unless Rails.env.development?
  warn "development_sample_data.rb is for development only (current RAILS_ENV=#{Rails.env.inspect})."
  exit 1
end

BankCore::Seeds::GlCoa.seed!

if Core::BusinessDate::Models::BusinessDateSetting.none?
  Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.current)
end

stamp = Time.now.utc.strftime("%Y%m%d-%H%M%S")

party = Party::Commands::CreateParty.call(
  party_type: "individual",
  first_name: "Dev",
  middle_name: "Sample",
  last_name: "Customer-#{stamp}"
)

account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)

posted = Core::OperationalEvents::Commands::RecordEvent.call(
  event_type: "deposit.accepted",
  channel: "teller",
  idempotency_key: "dev-seed-#{stamp}-posted",
  amount_minor_units: 100_00,
  currency: "USD",
  source_account_id: account.id
)

posted_result = Core::Posting::Commands::PostEvent.call(operational_event_id: posted[:event].id)

pending = Core::OperationalEvents::Commands::RecordEvent.call(
  event_type: "deposit.accepted",
  channel: "teller",
  idempotency_key: "dev-seed-#{stamp}-pending",
  amount_minor_units: 25_00,
  currency: "USD",
  source_account_id: account.id
)

puts <<~SUMMARY
  Development sample data created.

    party_id:              #{party.id}
    party_name:            #{party.name}
    deposit_account_id:    #{account.id}
    deposit_account_number: #{account.account_number}

    operational_event (posted):   id=#{posted[:event].id}  outcome=#{posted_result[:outcome]}  amount_minor_units=10000
    operational_event (pending): id=#{pending[:event].id}  status=#{pending[:event].status}  amount_minor_units=2500

  Re-run anytime; each run uses a new idempotency stamp and adds new rows.
SUMMARY
