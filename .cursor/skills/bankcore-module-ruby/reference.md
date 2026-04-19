# BankCORE module catalog — quick reference

Full spec: [bankcore-module-catalog.md](../../docs/architecture/bankcore-module-catalog.md)

## Domain map (catalog §3)

| Area | Modules |
|------|---------|
| Financial kernel | `Core::OperationalEvents`, `Core::Posting`, `Core::Ledger`, `Core::BusinessDate` |
| Customer / contract | `Party`, `Products`, `Accounts` |
| Servicing | `Deposits`, `Loans`, `Limits` |
| Branch ops | `Teller`, `Cash`, `Workflow` |
| Control / edge | `Compliance`, `Documents`, `Reporting`, `Integration` |

## Table ownership (catalog §10)

| Table family | Owning module |
|--------------|---------------|
| `party_*` | `Party` |
| `product_*`, `fee_*`, `interest_*` | `Products` |
| `deposit_accounts`, `loan_accounts`, `account_relationships` | `Accounts` |
| `operational_events`, `reversal_links` | `Core::OperationalEvents` |
| `posting_batches`, `posting_legs` | `Core::Posting` |
| `journal_entries`, `journal_lines`, `gl_accounts` | `Core::Ledger` |
| `holds`, `authorization_decisions` | `Limits` |
| `teller_sessions`, `teller_transactions` | `Teller` |
| `cash_locations`, `vault_transfers`, `cash_counts` | `Cash` |
| `approval_requests`, `approval_decisions` | `Workflow` |
| `document_records` | `Documents` |
| `daily_balance_snapshots`, `reporting_extracts` | `Reporting` |

## Workspaces (catalog §7.1)

`Teller`, `CustomerService`, `Ops`, `Admin`, `Api` — routes split with `config/routes/*.rb` and `draw`.

## Do not extract early (catalog §14.2)

Keep inside the main app unless there is a very strong reason: `Core::OperationalEvents`, `Core::Posting`, `Core::Ledger`, `Core::BusinessDate`, `Accounts`.
