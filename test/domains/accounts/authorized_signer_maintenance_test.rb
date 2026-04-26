# frozen_string_literal: true

require "test_helper"

class AuthorizedSignerMaintenanceTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 12))
    @product = Products::Queries::FindDepositProduct.default_slice1!
    @owner = create_party!("Owner", "Member")
    @signer = create_party!("Signer", "Member")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @owner.id, deposit_product_id: @product.id)
    @supervisor = Workspace::Models::Operator.create!(role: "supervisor", display_name: "Signer Supervisor", active: true)
    @teller = Workspace::Models::Operator.create!(role: "teller", display_name: "Signer Teller", active: true)
  end

  test "adds authorized signer with audit and idempotent replay" do
    result = add_signer!("add-signer")

    assert_equal :created, result[:outcome]
    relationship = result[:relationship]
    assert_equal Accounts::Models::DepositAccountParty::ROLE_AUTHORIZED_SIGNER, relationship.role
    assert_equal Accounts::Models::DepositAccountParty::STATUS_ACTIVE, relationship.status
    assert_equal Date.new(2026, 9, 12), relationship.effective_on

    audit = result[:audit]
    assert_equal "authorized_signer.added", audit.action
    assert_equal "branch", audit.channel
    assert_equal @supervisor.id, audit.actor_id
    assert_equal relationship.id, audit.deposit_account_party_id

    replay = add_signer!("add-signer")
    assert_equal :replay, replay[:outcome]
    assert_equal relationship.id, replay[:relationship].id
    assert_equal 1, Accounts::Models::DepositAccountPartyMaintenanceAudit.where(idempotency_key: "add-signer").count
  end

  test "rejects duplicate open authorized signer and non supervisor actor" do
    add_signer!("add-signer-once")

    assert_raises(Accounts::Commands::AddAuthorizedSigner::InvalidRequest) do
      add_signer!("add-signer-duplicate")
    end

    assert_raises(Accounts::Commands::AddAuthorizedSigner::InvalidRequest) do
      Accounts::Commands::AddAuthorizedSigner.call(
        deposit_account_id: @account.id,
        party_record_id: create_party!("Other", "Signer").id,
        channel: "branch",
        idempotency_key: "add-signer-teller",
        actor_id: @teller.id
      )
    end
  end

  test "ends authorized signer with audit and idempotent replay" do
    relationship = add_signer!("add-before-end")[:relationship]

    result = Accounts::Commands::EndAuthorizedSigner.call(
      deposit_account_party_id: relationship.id,
      channel: "branch",
      idempotency_key: "end-signer",
      actor_id: @supervisor.id,
      ended_on: Date.new(2026, 9, 12)
    )

    assert_equal :created, result[:outcome]
    assert_equal Accounts::Models::DepositAccountParty::STATUS_INACTIVE, relationship.reload.status
    assert_equal Date.new(2026, 9, 12), relationship.ended_on
    assert_equal "authorized_signer.ended", result[:audit].action
    assert_equal relationship.id, result[:audit].deposit_account_party_id

    replay = Accounts::Commands::EndAuthorizedSigner.call(
      deposit_account_party_id: relationship.id,
      channel: "branch",
      idempotency_key: "end-signer",
      actor_id: @supervisor.id,
      ended_on: Date.new(2026, 9, 12)
    )
    assert_equal :replay, replay[:outcome]
  end

  private

  def add_signer!(idempotency_key)
    Accounts::Commands::AddAuthorizedSigner.call(
      deposit_account_id: @account.id,
      party_record_id: @signer.id,
      channel: "branch",
      idempotency_key: idempotency_key,
      actor_id: @supervisor.id
    )
  end

  def create_party!(first_name, last_name)
    Party::Commands::CreateParty.call(party_type: "individual", first_name: first_name, last_name: last_name)
  end
end
