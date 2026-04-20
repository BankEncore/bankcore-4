## Recommended enum sets from your transaction list

Based on the transaction list you shared, I would define **two separate enum families**:

* **Parent event enums** \= the canonical business transaction  
* **Component enums** \= the leg/tender/instrument/allocation pieces inside that transaction

That is the cleanest way to support both:

* simple one-leg transactions  
* composite transactions like mixed deposits, loan payments with fees, account-funded official checks, etc.

---

# 1\. Parent event enum set

These should represent the **customer/business action** as a whole.

## Recommended `parent_event_code`

| Enum | Use For | Derived From |
| :---- | :---- | :---- |
| `cash_deposit` | Deposit funded only by cash, or deposit whose primary business action is deposit-in | 101 |
| `cash_withdrawal` | Cash withdrawal from account | 102 |
| `check_deposit` | Deposit funded by one or more checks | 103, 105, 107 |
| `check_withdrawal` | On-us or similar check-based withdrawal/reversal context | 104, 106, 108 |
| `vault_cash_transfer` | Teller/vault cash movement | 111, 112, 113, 114 |
| `foreign_currency_transaction` | Foreign currency in/out | 121, 122 |
| `loan_payment` | Payment into a loan | 201 |
| `loan_disbursement` | Loan proceeds out | 202 |
| `deposit_transaction` | Generic deposit-account deposit/withdrawal umbrella if you want one parent family | 301, 302 |
| `account_transfer` | Transfer between accounts | 311, 312 |
| `official_check_purchase` | Cashier’s check purchase | 401 |
| `official_check_refund` | Cashier’s check refund | 402 |
| `money_order_purchase` | Money order purchase | 403 |
| `money_order_refund` | Money order refund | 404 |
| `prepaid_card_purchase` | Prepaid card purchase | 405 |
| `prepaid_card_refund` | Prepaid card refund | 406 |
| `fee_assessment` | Explicit fee event | 501, 503, 505, 903 |
| `fee_reversal` | Explicit fee reversal/refund | 502, 504, 506 |
| `tax_payment` | Tax remittance/payment | 601 |
| `tax_payment_refund` | Reversal/refund of tax payment | 602 |
| `bill_payment` | Utility/third-party bill payment | 611 |
| `bill_payment_refund` | Refund/reversal of bill payment | 612 |
| `ach_credit` | ACH inbound credit | 701 |
| `ach_credit_return` | Return of ACH credit | 702 |
| `ach_debit` | ACH outbound debit | 703 |
| `ach_debit_return` | Return of ACH debit | 704 |
| `wire_in` | Incoming wire | 801 |
| `wire_return` | Return of incoming wire | 802 |
| `wire_out` | Outgoing wire | 803 |
| `wire_recall` | Recall/reversal of outgoing wire | 804 |
| `interest_posting_credit` | Interest credit posting | 901 |
| `interest_posting_debit` | Interest debit/adjustment | 902 |
| `service_charge` | System-assessed service charge | 903 |
| `hold_release` | Release of hold | 904 |

This is the **full practical parent set** I would infer from your file without inventing categories not represented there.

---

# 2\. More normalized parent-event enum set

If you want a **cleaner long-term set** with fewer values, I would compress the above into this canonical enum set:

## Canonical `parent_event_code`

```
parent_event_code:
  - deposit
  - withdrawal
  - transfer
  - vault_transfer
  - foreign_currency_transaction
  - loan_payment
  - loan_disbursement
  - official_check_purchase
  - official_check_refund
  - money_order_purchase
  - money_order_refund
  - prepaid_card_purchase
  - prepaid_card_refund
  - fee_assessment
  - fee_reversal
  - tax_payment
  - tax_payment_refund
  - bill_payment
  - bill_payment_refund
  - ach_credit
  - ach_credit_return
  - ach_debit
  - ach_debit_return
  - wire_in
  - wire_return
  - wire_out
  - wire_recall
  - interest_posting
  - service_charge
  - hold_release
```

### Why this version is better long-term

Because it lets:

* `deposit` cover cash, check, mixed, government-check, etc.  
* `withdrawal` cover cash and check where appropriate  
* `interest_posting` cover credit/debit direction via a separate enum  
* parent event stay business-focused, not tender-focused

This is the version I would recommend for a new architecture.

---

# 3\. Component enum set

These should represent the **legs** inside a transaction.

## Recommended `component_code`

| Enum | Meaning | Derived From |
| :---- | :---- | :---- |
| `cash` | Cash leg | 101, 102, 111, 112, 201, 301, 401, etc. |
| `vault_cash` | Vault-specific cash movement leg | 111, 112, 113, 114 |
| `branch_vault_cash` | Branch vault counterpart leg | 113, 114 |
| `foreign_currency` | Foreign currency leg | 121, 122 |
| `on_us_check` | On-us check leg | 103, 104 |
| `transit_check` | Transit/external check leg | 105, 106 |
| `government_check` | Government check leg | 107, 108 |
| `deposit_account` | Deposit account leg | 301, 302, 311, 312, 901, 902, 903, 904 |
| `loan_account` | Loan account leg | 201, 202 |
| `official_check` | Cashier’s/official check principal leg | 401, 402 |
| `money_order` | Money order principal leg | 403, 404 |
| `prepaid_card` | Prepaid card principal leg | 405, 406 |
| `fee` | Fee leg | 501–506, 903 |
| `tax_obligation` | Tax payable/remittance leg | 601, 602 |
| `bill_pay_obligation` | Bill pay payable/remittance leg | 611, 612 |
| `ach_settlement` | ACH settlement/account leg | 701–704 |
| `wire_settlement` | Wire settlement/account leg | 801–804 |
| `interest` | Interest posting leg | 901, 902 |
| `service_charge` | Service charge leg | 903 |
| `hold_release` | Hold-release leg | 904 |
| `account_transfer` | Transfer leg between accounts | 311, 312 |
| `clearing` | Generic clearing leg | 701–704, 801–804 |
| `teller_control` | Teller cash/control counterpart leg if you keep one | many teller codes |

That is the broadest component set directly suggested by your file.

---

# 4\. Cleaner long-term component enum set

For long-term architecture, I would normalize the above further.

## Canonical `component_code`

```
component_code:
  - cash
  - foreign_currency
  - on_us_check
  - transit_check
  - government_check
  - deposit_account
  - loan_account
  - escrow
  - official_check
  - money_order
  - prepaid_card
  - fee
  - tax_payment
  - bill_payment
  - ach
  - wire
  - interest
  - service_charge
  - hold
  - transfer
  - clearing
  - teller_cash
  - vault_cash
```

### Why this version is better

Because it keeps components focused on **what the leg is**, not on the exact transaction code or direction.

Direction should be handled separately.

---

# 5\. Additional enums you will likely need alongside these

To make the parent/component model work, parent and component codes alone are not enough.

## `direction_code`

Needed because many parents/components can be inbound or outbound.

```
direction_code:
  - in
  - out
  - debit
  - credit
  - reversal
```

I would usually prefer:

* `debit` / `credit` for accounting  
* `in` / `out` for contextual impact  
* not force one enum to do both jobs

So in practice, I would split these.

### `flow_direction`

```
flow_direction:
  - in
  - out
```

### `entry_direction`

```
entry_direction:
  - debit
  - credit
```

---

## `source_type`

This one is directly in your file.

```
source_type:
  - teller
  - back_office
  - system
```

---

## `account_role`

Useful for account-impact rows.

```
account_role:
  - primary_account
  - source_account
  - destination_account
  - loan_account
  - deposit_account
  - offset_account
  - settlement_account
```

---

## `impact_role`

Useful for the meaning of a component or account impact.

```
impact_role:
  - deposit
  - withdrawal
  - payment
  - disbursement
  - transfer_in
  - transfer_out
  - fee
  - fee_reversal
  - interest_credit
  - interest_debit
  - service_charge
  - hold_release
  - purchase
  - refund
  - clearing_in
  - clearing_out
```

---

## `instrument_type`

Useful especially for deposit/check/payment components.

```
instrument_type:
  - cash
  - check
  - government_check
  - official_check
  - money_order
  - prepaid_card
  - ach
  - wire
  - internal_transfer
  - foreign_currency
```

---

# 6\. How I would map your list in practice

## Parent events

I would **not** make separate parent enums for:

* cash deposit  
* on-us check deposit  
* transit check deposit

Instead, I would use:

* parent event: `deposit`  
* components: `cash`, `on_us_check`, `transit_check`, `government_check`

That is what makes mixed deposits possible.

Likewise, I would **not** make separate parent enums for every fee subtype unless those have very different workflows.

Instead:

* parent event: `fee_assessment`  
* component: `fee`  
* plus subtype metadata such as `cashiers_check_fee`, `money_order_fee`, etc.

---

# 7\. Recommended final enum sets

## A. Parent event enum set I recommend

```
parent_event_code:
  - deposit
  - withdrawal
  - transfer
  - vault_transfer
  - foreign_currency_transaction
  - loan_payment
  - loan_disbursement
  - official_check_purchase
  - official_check_refund
  - money_order_purchase
  - money_order_refund
  - prepaid_card_purchase
  - prepaid_card_refund
  - fee_assessment
  - fee_reversal
  - tax_payment
  - tax_payment_refund
  - bill_payment
  - bill_payment_refund
  - ach_credit
  - ach_credit_return
  - ach_debit
  - ach_debit_return
  - wire_in
  - wire_return
  - wire_out
  - wire_recall
  - interest_posting
  - service_charge
  - hold_release
```

---

## B. Component enum set I recommend

```
component_code:
  - cash
  - teller_cash
  - vault_cash
  - foreign_currency
  - on_us_check
  - transit_check
  - government_check
  - deposit_account
  - loan_account
  - escrow
  - official_check
  - money_order
  - prepaid_card
  - fee
  - tax_payment
  - bill_payment
  - ach
  - wire
  - interest
  - service_charge
  - hold
  - transfer
  - clearing
```

---

## C. Supporting enums I recommend

```
source_type:
  - teller
  - back_office
  - system

flow_direction:
  - in
  - out

entry_direction:
  - debit
  - credit

instrument_type:
  - cash
  - check
  - government_check
  - official_check
  - money_order
  - prepaid_card
  - ach
  - wire
  - internal_transfer
  - foreign_currency

impact_role:
  - deposit
  - withdrawal
  - payment
  - disbursement
  - transfer_in
  - transfer_out
  - fee
  - fee_reversal
  - interest_credit
  - interest_debit
  - service_charge
  - hold_release
  - purchase
  - refund
  - clearing_in
  - clearing_out
```

---

# 8\. Bottom line

From your transaction list, the best long-term structure is:

## Parent events

Use a **smaller, normalized business-event enum set**.

## Components

Use a **leg/tender/instrument enum set** that can be combined to support mixed and cross-boundary transactions.

That means:

* `deposit` is the parent  
* `cash`, `on_us_check`, and `transit_check` are components

rather than making all three separate peer parent events.

If you want, I can turn this next into a **full YAML registry** with:

* enum definitions  
* descriptions  
* allowed component mappings per parent event  
* and sample mixed-deposit / loan-payment compositions.

