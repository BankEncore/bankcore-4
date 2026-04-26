# frozen_string_literal: true

require "test_helper"

class CoreOperationalEventsListOperationalEventsTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    BankCore::Seeds::DepositProducts.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 5, 10))
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "L", last_name: "ist")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @session = Teller::Commands::OpenSession.call(drawer_code: "list-oe-#{SecureRandom.hex(4)}")
  end

  test "defaults to current business day when no date params" do
    ev = record_deposit!(idem: "d1", amount: 100)
    result = Core::OperationalEvents::Queries::ListOperationalEvents.call
    assert_equal 1, result[:rows].size
    assert_equal ev.id, result[:rows].sole.id
    assert_equal Date.new(2026, 5, 10), result[:envelope][:business_date_from]
    assert_equal false, result[:envelope][:posting_day_closed]
  end

  test "filters by business_date single day" do
    record_deposit!(idem: "a", amount: 50)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 5, 11))
    record_deposit!(idem: "b", amount: 60)

    past = Core::OperationalEvents::Queries::ListOperationalEvents.call(business_date: Date.new(2026, 5, 10))
    assert_equal 1, past[:rows].size
    assert_equal 50, past[:rows].sole.amount_minor_units
    assert past[:envelope][:posting_day_closed]

    today = Core::OperationalEvents::Queries::ListOperationalEvents.call(business_date: Date.new(2026, 5, 11))
    assert_equal 1, today[:rows].size
    assert_equal 60, today[:rows].sole.amount_minor_units
    assert_equal false, today[:envelope][:posting_day_closed]
  end

  test "rejects future end date" do
    assert_raises(Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery) do
      Core::OperationalEvents::Queries::ListOperationalEvents.call(business_date: Date.new(2026, 5, 20))
    end
  end

  test "rejects range over max span" do
    assert_raises(Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery) do
      Core::OperationalEvents::Queries::ListOperationalEvents.call(
        business_date_from: Date.new(2026, 4, 1),
        business_date_to: Date.new(2026, 5, 10)
      )
    end
  end

  test "paginates with after_id" do
    record_deposit!(idem: "p1", amount: 10)
    record_deposit!(idem: "p2", amount: 20)
    r1 = Core::OperationalEvents::Queries::ListOperationalEvents.call(limit: 1)
    assert r1[:has_more]
    assert_equal 1, r1[:rows].size
    r2 = Core::OperationalEvents::Queries::ListOperationalEvents.call(limit: 1, after_id: r1[:rows].sole.id)
    assert_equal 1, r2[:rows].size
    assert_operator r2[:rows].sole.id, :>, r1[:rows].sole.id
  end

  test "filters by deposit_product_id" do
    record_deposit!(idem: "prod", amount: 30)
    result = Core::OperationalEvents::Queries::ListOperationalEvents.call(
      deposit_product_id: @account.deposit_product_id
    )
    assert_equal 1, result[:rows].size
  end

  test "filters by support search keys" do
    original = create_event!(
      event_type: "fee.assessed",
      idempotency_key: "support-original",
      reference_id: "support-case-1"
    )
    create_event!(
      event_type: "fee.assessed",
      idempotency_key: "support-other",
      reference_id: "support-case-2"
    )
    reversal = create_event!(
      event_type: "posting.reversal",
      idempotency_key: "support-reversal",
      reference_id: original.id.to_s,
      reversal_of_event_id: original.id
    )

    by_reference = Core::OperationalEvents::Queries::ListOperationalEvents.call(reference_id: "support-case-1")
    assert_equal [ original.id ], by_reference[:rows].map(&:id)

    by_idempotency = Core::OperationalEvents::Queries::ListOperationalEvents.call(idempotency_key: "support-reversal")
    assert_equal [ reversal.id ], by_idempotency[:rows].map(&:id)

    by_reversal = Core::OperationalEvents::Queries::ListOperationalEvents.call(reversal_of_event_id: original.id)
    assert_equal [ reversal.id ], by_reversal[:rows].map(&:id)
  end

  private

  def record_deposit!(idem:, amount:)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      teller_session_id: @session.id
    )[:event]
  end

  def create_event!(event_type:, idempotency_key:, reference_id: nil, reversal_of_event_id: nil)
    Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: event_type,
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: Date.new(2026, 5, 10),
      channel: "branch",
      idempotency_key: idempotency_key,
      amount_minor_units: 100,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: reference_id,
      reversal_of_event_id: reversal_of_event_id
    )
  end
end
