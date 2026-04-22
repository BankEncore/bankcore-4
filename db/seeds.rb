# frozen_string_literal: true

# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

require_relative "../lib/bank_core/seeds/gl_coa"

BankCore::Seeds::GlCoa.seed!

if Core::BusinessDate::Models::BusinessDateSetting.none?
  Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.current)
end
