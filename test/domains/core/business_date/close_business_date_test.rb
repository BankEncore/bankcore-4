# frozen_string_literal: true

require "test_helper"

class CoreBusinessDateCloseBusinessDateTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 3, 1))
    @operator = Workspace::Models::Operator.create!(role: "supervisor", display_name: "Business Date Supervisor", active: true)
  end

  test "close advances when institution is eod_ready" do
    result = Core::BusinessDate::Commands::CloseBusinessDate.call(closed_by_operator_id: @operator.id)
    assert_equal Date.new(2026, 3, 2), result[:setting].current_business_on
    assert_equal Date.new(2026, 3, 1), result[:closed_on]
    ev = Core::BusinessDate::Models::BusinessDateCloseEvent.sole
    assert_equal @operator.id, ev.closed_by_operator_id
  end

  test "close raises when a teller session is still open" do
    Teller::Commands::OpenSession.call(drawer_code: "close-block-#{SecureRandom.hex(4)}")
    err = assert_raises(Core::BusinessDate::Errors::EodNotReady) do
      Core::BusinessDate::Commands::CloseBusinessDate.call(closed_by_operator_id: @operator.id)
    end
    assert_equal false, err.readiness[:eod_ready]
  end

  test "close raises when business_date param does not match current" do
    assert_raises(ArgumentError) do
      Core::BusinessDate::Commands::CloseBusinessDate.call(
        closed_by_operator_id: @operator.id,
        business_date: Date.new(2026, 2, 1)
      )
    end
  end
end
