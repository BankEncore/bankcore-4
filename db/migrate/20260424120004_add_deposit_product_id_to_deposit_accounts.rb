# frozen_string_literal: true

class AddDepositProductIdToDepositAccounts < ActiveRecord::Migration[8.1]
  def up
    add_reference :deposit_accounts, :deposit_product, foreign_key: true, null: true

    slice1 = "slice1_demand_deposit"
    say_with_time "seed default deposit product" do
      execute <<~SQL.squish
        INSERT INTO deposit_products (product_code, name, status, currency, created_at, updated_at)
        SELECT '#{slice1}', 'Slice 1 demand deposit (seeded)', 'active', 'USD', NOW(), NOW()
        WHERE NOT EXISTS (SELECT 1 FROM deposit_products WHERE product_code = '#{slice1}')
      SQL
    end

    say_with_time "backfill deposit_product_id" do
      execute <<~SQL.squish
        UPDATE deposit_accounts AS da
        SET deposit_product_id = dp.id
        FROM deposit_products AS dp
        WHERE da.deposit_product_id IS NULL
          AND da.product_code = dp.product_code
      SQL
    end

    orphans = connection.select_value("SELECT COUNT(*) FROM deposit_accounts WHERE deposit_product_id IS NULL").to_i
    if orphans.positive?
      raise ActiveRecord::IrreversibleMigration,
        "deposit_accounts has #{orphans} row(s) with no matching deposit_products.product_code"
    end

    change_column_null :deposit_accounts, :deposit_product_id, false
  end

  def down
    change_column_null :deposit_accounts, :deposit_product_id, true
    remove_reference :deposit_accounts, :deposit_product, foreign_key: true
  end
end
