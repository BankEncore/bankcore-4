# frozen_string_literal: true

class CreateOperatorCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :operator_credentials do |t|
      t.references :operator, null: false, foreign_key: true, index: { unique: true }
      t.string :username, null: false
      t.string :password_digest, null: false
      t.datetime :password_changed_at
      t.integer :failed_login_attempts, null: false, default: 0
      t.datetime :locked_at
      t.datetime :last_sign_in_at
      t.timestamps
    end

    add_index :operator_credentials, "lower(username)", unique: true,
      name: "index_operator_credentials_on_lower_username"
    add_check_constraint :operator_credentials, "btrim(username) <> ''",
      name: "operator_credentials_username_present_check"
    add_check_constraint :operator_credentials, "failed_login_attempts >= 0",
      name: "operator_credentials_failed_attempts_nonnegative_check"
  end
end
