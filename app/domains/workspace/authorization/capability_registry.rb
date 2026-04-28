# frozen_string_literal: true

module Workspace
  module Authorization
    module CapabilityRegistry
      DEPOSIT_ACCEPT = "deposit.accept"
      WITHDRAWAL_POST = "withdrawal.post"
      TRANSFER_COMPLETE = "transfer.complete"
      TELLER_SESSION_OPEN = "teller_session.open"
      TELLER_SESSION_CLOSE = "teller_session.close"
      CASH_DRAWER_MANAGE = "cash_drawer.manage"
      PARTY_CREATE = "party.create"
      ACCOUNT_OPEN = "account.open"
      ACCOUNT_MAINTAIN = "account.maintain"
      HOLD_PLACE = "hold.place"
      FEE_WAIVE = "fee.waive"
      HOLD_RELEASE = "hold.release"
      BUSINESS_DATE_CLOSE = "business_date.close"
      TELLER_SESSION_VARIANCE_APPROVE = "teller_session_variance.approve"
      REVERSAL_CREATE = "reversal.create"
      OPS_BATCH_PROCESS = "ops.batch.process"
      OPS_EXCEPTION_RESOLVE = "ops.exception.resolve"
      OPS_RECONCILIATION_PERFORM = "ops.reconciliation.perform"
      OPERATIONAL_EVENT_VIEW = "operational_event.view"
      JOURNAL_ENTRY_VIEW = "journal_entry.view"
      AUDIT_EXPORT = "audit.export"
      REPORT_VIEW = "report.view"
      USER_MANAGE = "user.manage"
      ROLE_MANAGE = "role.manage"
      SYSTEM_CONFIGURE = "system.configure"

      TELLER = "teller"
      BRANCH_SUPERVISOR = "branch_supervisor"
      CSR = "csr"
      BRANCH_MANAGER = "branch_manager"
      OPERATIONS = "operations"
      AUDITOR = "auditor"
      SYSTEM_ADMIN = "system_admin"

      CAPABILITIES = [
        { code: DEPOSIT_ACCEPT, name: "Accept deposit", category: "transaction",
          description: "May accept a deposit transaction." },
        { code: WITHDRAWAL_POST, name: "Post withdrawal", category: "transaction",
          description: "May post a withdrawal transaction." },
        { code: TRANSFER_COMPLETE, name: "Complete transfer", category: "transaction",
          description: "May complete an internal transfer." },
        { code: TELLER_SESSION_OPEN, name: "Open teller session", category: "teller",
          description: "May open a teller drawer/session." },
        { code: TELLER_SESSION_CLOSE, name: "Close teller session", category: "teller",
          description: "May close a teller drawer/session." },
        { code: CASH_DRAWER_MANAGE, name: "Manage cash drawer", category: "cash",
          description: "May perform teller cash drawer operations." },
        { code: PARTY_CREATE, name: "Create party", category: "party",
          description: "May create party records." },
        { code: ACCOUNT_OPEN, name: "Open account", category: "account",
          description: "May open deposit accounts." },
        { code: ACCOUNT_MAINTAIN, name: "Maintain account", category: "account",
          description: "May maintain account relationships and servicing attributes." },
        { code: HOLD_PLACE, name: "Place hold", category: "control",
          description: "May place account holds." },
        { code: FEE_WAIVE, name: "Waive fee", category: "control",
          description: "May waive posted account fees." },
        { code: HOLD_RELEASE, name: "Release hold", category: "control",
          description: "May release active account holds." },
        { code: BUSINESS_DATE_CLOSE, name: "Close business date", category: "control",
          description: "May close the current business date after readiness checks." },
        { code: TELLER_SESSION_VARIANCE_APPROVE, name: "Approve teller session variance", category: "control",
          description: "May approve a teller session variance." },
        { code: REVERSAL_CREATE, name: "Create reversal", category: "control",
          description: "May create controlled reversals." },
        { code: OPS_BATCH_PROCESS, name: "Process operations batch", category: "operations",
          description: "May run operations batch processes." },
        { code: OPS_EXCEPTION_RESOLVE, name: "Resolve operations exception", category: "operations",
          description: "May resolve operations exceptions." },
        { code: OPS_RECONCILIATION_PERFORM, name: "Perform reconciliation", category: "operations",
          description: "May perform operations reconciliation." },
        { code: OPERATIONAL_EVENT_VIEW, name: "View operational events", category: "audit",
          description: "May view operational event records." },
        { code: JOURNAL_ENTRY_VIEW, name: "View journal entries", category: "audit",
          description: "May view journal entries and journal lines." },
        { code: AUDIT_EXPORT, name: "Export audit data", category: "audit",
          description: "May export audit evidence." },
        { code: REPORT_VIEW, name: "View reports", category: "reporting",
          description: "May view internal operational reports." },
        { code: USER_MANAGE, name: "Manage users", category: "admin",
          description: "May manage internal users/operators." },
        { code: ROLE_MANAGE, name: "Manage roles", category: "admin",
          description: "May manage RBAC role assignments." },
        { code: SYSTEM_CONFIGURE, name: "Configure system", category: "admin",
          description: "May configure internal system settings." }
      ].freeze

      ROLES = [
        { code: TELLER, name: "Teller", description: "Branch teller transaction operator." },
        { code: BRANCH_SUPERVISOR, name: "Branch Supervisor", description: "Supervisor for branch and teller controls." },
        { code: CSR, name: "CSR", description: "Customer service representative for branch servicing." },
        { code: BRANCH_MANAGER, name: "Branch Manager", description: "Branch manager servicing and control authority." },
        { code: OPERATIONS, name: "Operations", description: "Back-office operations staff." },
        { code: AUDITOR, name: "Auditor", description: "Read-only audit and evidence reviewer." },
        { code: SYSTEM_ADMIN, name: "System Administrator", description: "Technology administration staff." }
      ].freeze

      ROLE_CAPABILITIES = {
        TELLER => [
          DEPOSIT_ACCEPT, WITHDRAWAL_POST, TRANSFER_COMPLETE, TELLER_SESSION_OPEN, TELLER_SESSION_CLOSE,
          CASH_DRAWER_MANAGE, PARTY_CREATE, ACCOUNT_OPEN, HOLD_PLACE, REPORT_VIEW
        ],
        BRANCH_SUPERVISOR => [
          DEPOSIT_ACCEPT, WITHDRAWAL_POST, TRANSFER_COMPLETE, TELLER_SESSION_OPEN, TELLER_SESSION_CLOSE,
          CASH_DRAWER_MANAGE, PARTY_CREATE, ACCOUNT_OPEN, ACCOUNT_MAINTAIN, HOLD_PLACE, FEE_WAIVE, HOLD_RELEASE,
          BUSINESS_DATE_CLOSE, TELLER_SESSION_VARIANCE_APPROVE, REVERSAL_CREATE, OPERATIONAL_EVENT_VIEW, REPORT_VIEW
        ],
        CSR => [
          PARTY_CREATE, ACCOUNT_OPEN, ACCOUNT_MAINTAIN, HOLD_PLACE, OPERATIONAL_EVENT_VIEW, REPORT_VIEW
        ],
        BRANCH_MANAGER => [
          PARTY_CREATE, ACCOUNT_OPEN, ACCOUNT_MAINTAIN, HOLD_PLACE, FEE_WAIVE, HOLD_RELEASE, REVERSAL_CREATE,
          OPERATIONAL_EVENT_VIEW, JOURNAL_ENTRY_VIEW, REPORT_VIEW
        ],
        OPERATIONS => [
          OPS_BATCH_PROCESS, OPS_EXCEPTION_RESOLVE, OPS_RECONCILIATION_PERFORM, OPERATIONAL_EVENT_VIEW,
          JOURNAL_ENTRY_VIEW, AUDIT_EXPORT, REPORT_VIEW, BUSINESS_DATE_CLOSE, TELLER_SESSION_VARIANCE_APPROVE
        ],
        AUDITOR => [
          OPERATIONAL_EVENT_VIEW, JOURNAL_ENTRY_VIEW, AUDIT_EXPORT, REPORT_VIEW
        ],
        SYSTEM_ADMIN => [
          USER_MANAGE, ROLE_MANAGE, SYSTEM_CONFIGURE, OPERATIONAL_EVENT_VIEW, REPORT_VIEW
        ]
      }.freeze

      LEGACY_ROLE_MAPPING = {
        "teller" => TELLER,
        "supervisor" => BRANCH_SUPERVISOR,
        "operations" => OPERATIONS,
        "admin" => SYSTEM_ADMIN
      }.freeze

      def self.capability_codes
        CAPABILITIES.map { |capability| capability.fetch(:code) }
      end

      def self.role_codes
        ROLES.map { |role| role.fetch(:code) }
      end

      def self.role_capability_pairs
        ROLE_CAPABILITIES.flat_map do |role_code, capability_codes|
          capability_codes.map { |capability_code| { role_code: role_code, capability_code: capability_code } }
        end
      end
    end
  end
end
