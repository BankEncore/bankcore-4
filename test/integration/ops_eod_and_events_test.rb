# frozen_string_literal: true

require "test_helper"

class OpsEodAndEventsTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    @business_date = Date.new(2026, 7, 1)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @business_date)
  end

  test "ops pages are available to operations and admin but not branch roles" do
    create_operator_with_credential!(role: "operations", username: "ops-reader")
    internal_login!(username: "ops-reader")
    get "/ops/eod"
    assert_response :success
    delete "/logout"

    create_operator_with_credential!(role: "admin", username: "ops-admin")
    internal_login!(username: "ops-admin")
    get "/ops/operational_events"
    assert_response :success
    delete "/logout"

    create_operator_with_credential!(role: "teller", username: "ops-teller")
    internal_login!(username: "ops-teller")
    get "/ops/eod"
    assert_response :forbidden
    delete "/logout"

    create_operator_with_credential!(role: "supervisor", username: "ops-supervisor")
    internal_login!(username: "ops-supervisor")
    get "/ops/operational_events"
    assert_response :forbidden
  end

  test "eod page shows readiness and trial balance rows" do
    operator = create_operator_with_credential!(role: "operations", username: "ops-eod")
    seed_posted_deposit!(operator: operator, amount_minor_units: 5_000)

    internal_login!(username: "ops-eod")
    get "/ops/eod"

    assert_response :success
    assert_select "h1", "EOD readiness"
    assert_includes response.body, @business_date.iso8601
    assert_includes response.body, "Open/pending sessions"
    assert_includes response.body, "1110"
    assert_includes response.body, "$50.00"
  end

  test "eod page renders empty state and invalid date errors" do
    create_operator_with_credential!(role: "operations", username: "ops-eod-empty")
    internal_login!(username: "ops-eod-empty")

    get "/ops/eod"
    assert_response :success
    assert_includes response.body, "No GL activity for this business date."

    get "/ops/eod", params: { business_date: "not-a-date" }
    assert_response :unprocessable_entity
    assert_includes response.body, "business_date must be a valid ISO 8601 date"

    get "/ops/eod", params: { business_date: (@business_date + 1.day).iso8601 }
    assert_response :unprocessable_entity
    assert_includes response.body, "business_date cannot be after current business date"
  end

  test "event search filters and paginates operational events" do
    operator = create_operator_with_credential!(role: "operations", username: "ops-events")
    first = seed_posted_deposit!(operator: operator, amount_minor_units: 1_000)
    second = seed_posted_deposit!(operator: operator, amount_minor_units: 2_000)

    internal_login!(username: "ops-events")
    get "/ops/operational_events", params: { business_date: @business_date.iso8601, event_type: "deposit.accepted", limit: 1 }

    assert_response :success
    assert_includes response.body, "Operational event search"
    assert_select "a[href='#{ops_operational_event_path(first)}']", text: "##{first.id}"
    assert_select "a[href='#{ops_operational_event_path(second)}']", count: 0
    assert_includes response.body, "Next page"

    get "/ops/operational_events", params: { business_date: @business_date.iso8601, event_type: "fee.assessed" }
    assert_response :success
    assert_includes response.body, "No operational events matched these filters."
  end

  test "event search renders invalid query errors" do
    create_operator_with_credential!(role: "operations", username: "ops-events-invalid")
    internal_login!(username: "ops-events-invalid")

    get "/ops/operational_events", params: { business_date: (@business_date + 1.day).iso8601 }

    assert_response :unprocessable_entity
    assert_includes response.body, "business_date cannot be after current business date"
  end

  test "event detail renders metadata and journal lines" do
    operator = create_operator_with_credential!(role: "operations", username: "ops-event-detail")
    event = seed_posted_deposit!(operator: operator, amount_minor_units: 7_500)

    internal_login!(username: "ops-event-detail")
    get "/ops/operational_events/#{event.id}"

    assert_response :success
    assert_select "h1", "Operational event ##{event.id}"
    assert_includes response.body, "deposit.accepted"
    assert_includes response.body, "Operational narrative"
    assert_includes response.body, "Traceability"
    assert_includes response.body, "Posting and journal detail"
    assert_includes response.body, "$75.00"
    assert_includes response.body, "Posting batch"
    assert_includes response.body, "Journal entry"
    assert_includes response.body, "1110"
    assert_includes response.body, "2110"
  end

  private

  def seed_posted_deposit!(operator:, amount_minor_units:)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Ops",
      last_name: "Review"
    )
    account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
    session = Teller::Commands::OpenSession.call(drawer_code: "ops-#{SecureRandom.hex(6)}")
    result = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: "ops-deposit-#{SecureRandom.hex(6)}",
      amount_minor_units: amount_minor_units,
      currency: "USD",
      source_account_id: account.id,
      teller_session_id: session.id,
      actor_id: operator.id
    )
    event = result[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
    event.reload
  end
end
