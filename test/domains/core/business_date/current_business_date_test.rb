# frozen_string_literal: true

require "test_helper"

class CoreBusinessDateCurrentBusinessDateTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
  end

  test "call raises when no row" do
    assert_raises(Core::BusinessDate::Errors::NotSet) do
      Core::BusinessDate::Services::CurrentBusinessDate.call
    end
  end

  test "call returns stored date after set" do
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 15))
    assert_equal Date.new(2026, 4, 15), Core::BusinessDate::Services::CurrentBusinessDate.call
  end

  test "advance moves forward one day" do
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 1, 2))
    Core::BusinessDate::Commands::AdvanceBusinessDate.call
    assert_equal Date.new(2026, 1, 3), Core::BusinessDate::Services::CurrentBusinessDate.call
  end

  test "set updates existing singleton" do
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 6, 1))
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 6, 10))
    assert_equal 1, Core::BusinessDate::Models::BusinessDateSetting.count
    assert_equal Date.new(2026, 6, 10), Core::BusinessDate::Services::CurrentBusinessDate.call
  end
end
