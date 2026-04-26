# frozen_string_literal: true

class AddServicingMetadataToHolds < ActiveRecord::Migration[8.1]
  def change
    add_column :holds, :hold_type, :string, null: false, default: "administrative"
    add_column :holds, :reason_code, :string, null: false, default: "manual_review"
    add_column :holds, :reason_description, :string
    add_column :holds, :expires_on, :date
    add_reference :holds, :expired_by_operational_event, null: true, foreign_key: { to_table: :operational_events }

    add_check_constraint :holds,
      "hold_type IN ('administrative','deposit','legal','channel_authorization')",
      name: "holds_hold_type_enum"
    add_check_constraint :holds,
      "reason_code IN ('deposit_availability','customer_request','fraud_review','legal_order','manual_review','other')",
      name: "holds_reason_code_enum"
  end
end
