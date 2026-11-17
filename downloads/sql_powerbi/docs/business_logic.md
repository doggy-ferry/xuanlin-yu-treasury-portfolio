# Business logic

All rules live in SQL (`sql/sqlserver/03_transform.sql`, `04_business_views.sql`); Power BI only adds measures. This page states each rule once, in business terms.

## A. Cash flow, Actual and Forecast

| Topic | Rule |
|---|---|
| Sign | Inflow +, outflow -. A category has an expected sign (inflow categories must be positive, outflow negative; Borrowing and Pooling may be either); test T18 enforces it. |
| Amounts | `amount_original` in the transaction currency; `fx_rate` = JPY per unit; `amount_base` = JPY. **Original amounts are never added across currencies**; cross-currency totals use `amount_base` (test T16 checks `original x rate = base` within 1 JPY). |
| Rates | Forecast lines use the planning rate (`dim_currency.reference_rate_jpy`: USD 150, EUR 163, GBP 190, CNY 21). Actual lines use a monthly rate that differs by up to 3 %, so part of a variance is a currency effect. |
| Scenario | `Actual` or `Forecast` (CHECK constraint and test T17). |
| Variance | `Actual - Forecast`. Negative = the Actual cash movement is lower than planned (see the sign note below). |
| Variance % | `variance / NULLIF(ABS(forecast), 0)`: a zero forecast gives NULL, never an error. |
| Variance status | `Unplanned` (no forecast line), `Not realised` (forecast but no actual), `Large variance` (at least 3 million JPY **and** at least 20 %), otherwise `Within range`. |
| Cash position | Opening balance (per entity) + running sum of Actual flows (window function `SUM() OVER (... ROWS UNBOUNDED PRECEDING)`); every entity appears every day, flows or not. Closing cash after the last Actual flow equals **745,000,000 JPY**, the balance in the workbook's `cash summary sheet` on 2026-10-31 (test T27). |
| Continuity | Opening of a day = closing of the previous day (test T28, `LAG`). |
| Pooling | Sweeps between entities net to zero on every date (test T30). |
| Join fan-out | Each view aggregates to the join grain before it joins (flows by day and entity; amounts by month, entity, currency, category), so a join never multiplies a row. |

*Sign note.* Because outflows are negative, "Actual - Forecast" is negative when an outflow is larger than planned **or** an inflow is smaller than planned, and positive for the reverse. A payment that is delayed (Actual outflow smaller than Forecast) therefore shows a positive variance.

### Planted events (so the dashboard has something to say)

| Event | Where | What the variance view shows |
|---|---|---|
| Customer pays only 55 % | ENT3, 2026-03, USD trade receipts | Large variance |
| Payment run delayed to October | ENT1, 2026-09, trade payments (JPY, USD, EUR) | Not realised in September, Large variance in October |
| Receipt never arrives in July | ENT4, 2026-07, GBP trade receipts | Not realised |
| ... and arrives, doubled, in August | ENT4, 2026-08, GBP | Large variance |
| Unplanned repair of 9 million JPY | ENT2, 2026-06, expenses | Large variance |

The tests D08 to D11 check that each one is detected.

### Dirty staging rows (so the cleaning has something to do)

Six rows in `stg_cashflow` are rejected with a reason, never silently dropped: two exact duplicates (`DUPLICATE_REF`), an unknown currency, a missing amount, an impossible date (2026-13-45), an unknown entity. Three more rows arrive with a lower-case, space-padded currency code (` usd `) and are **fixed** by standardisation, not rejected. Test T25: staging rows = loaded rows + rejected rows.

## B. FX payment control

Three sources are linked for every payment:

- **Request**: the invoice (`invoice sheet`), joined by invoice number and currency.
- **Plan**: the ERP payment schedule (`ERP payment schedule sheet`), joined by account + currency + payment date.
- **History**: the vendor bank history (`vendor bank history sheet`), joined by account.

The payment instruction is checked against all three. Every failed rule is stored (`fact_payment_exception`, 44 rows for 150 payments); one **primary** exception per payment drives the dashboard.

| Code | Rule | Risk | Excel rule |
|---|---|---|---|
| FX02 | Name is in history but the account is not (account changed) | High | (2) |
| FX04 | SWIFT differs from history (first 8 characters and branch; `XXX` tolerated) | High | (4) |
| FX05 | Bank country differs from history | High | (5) |
| FX11 | First two characters of the IBAN differ from the bank country | High | (11) |
| FX19 | IBAN length differs from the country table | High | IBAN table |
| FX01 | SWIFT missing | High | (1) |
| FX12 | CNY payment to a bank in China with no PURP code | High | (12) |
| FX13 | No ERP schedule for account + currency + date | High | (13) |
| FX20 | Payment total differs from the ERP schedule total | High | amount check |
| FX14 | BOP code not found in ERP for this account | High | (14) |
| FX25 | Vendor key present but not in the vendor master | High | added |
| FX03 | New beneficiary (neither name nor account in history) | Medium | (3) |
| FX07 | Currency never used for this account | Medium | (7) |
| FX08 | BOP code never used for this account | Medium | (8) |
| FX06 | Bank name differs from history | Medium | (6) |
| FX09 / FX10 | Beneficiary country / city differs from history | Medium | (9), (10) |
| FX24 | Name spelling differs from history | Medium | name variation |
| FX22 | Invoice breakdown incomplete (a missing BOP declaration, or more than 3 codes) | Medium | (22) |
| FX23 | Invoice total differs from the payment | Medium | (23) |

- **Primary exception** = the failed rule with the smallest `priority_rank` (red rules first). `ROW_NUMBER() OVER (PARTITION BY payment ORDER BY priority_rank)`. Test T21 checks that no failed rule ranks above it.
- **Risk level**: `High` (red), `Medium` (amber, "Review required"), `Passed` (green). Review status: *Hold for confirmation* / *Review required* / *Passed defined checks*. "Passed" means no defined rule failed; it does not mean the payment is correct.
- **Flags** (1 pass / 0 fail / NULL not applicable): vendor history, ERP account, amount, currency, SWIFT, IBAN, bank, BOP, invoice. Tests T22 to T24 check that a flag is 0 exactly when its exception exists.
- **Unmatched data is kept.** A payment whose vendor cannot be found stays in `fact_fx_payment` with a NULL `vendor_key` (`LEFT JOIN`); an INNER JOIN would have dropped three payments without a message (query Q8 shows it). A payment that cannot be placed at all (unknown entity, currency or date) goes to `rejected_record`.
- **Masking.** Account numbers and IBANs are shown as the first four and last four characters; the full value exists only in staging.

## C. What this model does not do

- No full cash-flow statement and no operating / investing / financing split: only receipts, payments and funding movements.
- No bank connectivity, no real payment release: the control stops at "review required".
- A single static planning rate per currency for forecasts and a monthly rate for actuals; not a valuation method.
- The rules replicate the existing workbook; they are not a fraud model. Passing them is not evidence that a payment is genuine.
