# frozen_string_literal: true

class AddExternalShipmentReceiptsToCashMovements < ActiveRecord::Migration[8.1]
  OLD_MOVEMENT_TYPES = %w[vault_to_drawer drawer_to_vault internal_transfer adjustment].freeze
  NEW_MOVEMENT_TYPES = (OLD_MOVEMENT_TYPES + %w[external_shipment_received]).freeze

  def up
    add_column :cash_movements, :external_source, :string
    add_column :cash_movements, :shipment_reference, :string
    add_index :cash_movements, [ :external_source, :shipment_reference ],
      name: "idx_cash_movements_external_shipment_reference"

    remove_check_constraint :cash_movements, name: "cash_movements_type_check"
    add_check_constraint :cash_movements, in_list_sql("movement_type", NEW_MOVEMENT_TYPES),
      name: "cash_movements_type_check"
    add_check_constraint :cash_movements,
      <<~SQL.squish,
        movement_type <> 'external_shipment_received'
        OR (
          source_cash_location_id IS NULL
          AND destination_cash_location_id IS NOT NULL
          AND external_source IS NOT NULL
          AND length(trim(external_source)) > 0
          AND shipment_reference IS NOT NULL
          AND length(trim(shipment_reference)) > 0
        )
      SQL
      name: "cash_movements_external_shipment_required_fields_check"
  end

  def down
    remove_check_constraint :cash_movements, name: "cash_movements_external_shipment_required_fields_check"
    remove_check_constraint :cash_movements, name: "cash_movements_type_check"
    add_check_constraint :cash_movements, in_list_sql("movement_type", OLD_MOVEMENT_TYPES),
      name: "cash_movements_type_check"
    remove_index :cash_movements, name: "idx_cash_movements_external_shipment_reference"
    remove_column :cash_movements, :shipment_reference
    remove_column :cash_movements, :external_source
  end

  private

  def in_list_sql(column_name, values)
    quoted = values.map { |value| connection.quote(value) }.join(", ")
    "#{column_name} IN (#{quoted})"
  end
end
