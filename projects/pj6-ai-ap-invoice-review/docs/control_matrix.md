# Control matrix

| Control / exception | Code | Owner | How it is tested |
|---|---|---|---|
| Duplicate invoice (same number, or same supplier + amount + date) | `DUPLICATE_INVOICE` | Rules | exact and renumbered cases in data and unit tests |
| Supplier not in master / inactive | `SUPPLIER_NOT_FOUND`, `SUPPLIER_INACTIVE` | Rules | mutation tests |
| PO not found | `PO_NOT_FOUND` | Rules | data + mutation |
| Invoice supplier differs from PO supplier | `SUPPLIER_MISMATCH` | Rules | data + mutation |
| Invoice currency differs from PO currency | `CURRENCY_MISMATCH` | Rules | data + mutation |
| Header subtotal vs line sum; invoice vs PO net or receipt value (1% tolerance) | `AMOUNT_MISMATCH` | Rules | data + mutation |
| Quantity x unit price vs line amount | `QUANTITY_PRICE_MISMATCH` | Rules | data + mutation |
| Tax vs PO tax rate; total vs subtotal + tax | `TAX_INCONSISTENCY` | Rules | data + mutation |
| Invoice before PO, in the future, too long after receipt, or due before invoice | `DATE_OUTLIER` | Rules | data + mutation |
| Bank account differs from supplier master | `BANK_ACCOUNT_CHANGE` | Rules | data + mutation |
| Required field missing or non-numeric amount | `MISSING_FIELD` | Rules | mutation |
| Invoice wording conflicts with PO | `SEMANTIC_DESCRIPTION_CONFLICT` | AI | precomputed results; fake-client tests |
| Exception condition hidden in notes | `EXCEPTION_CONDITION_IN_NOTES` (counted as semantic conflict) | AI | precomputed results |
| Vague description | `VAGUE_DESCRIPTION` | AI | precomputed results |
| Unreadable or low-confidence evidence | `UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE` | AI | precomputed results |
| AI output invalid / API unavailable | `AI_OUTPUT_INVALID`, `AI_UNAVAILABLE` | AI layer (safe failure) | fake-client tests |
| Acceptance of any exception, disposal, payment decision | n/a | **Human** | review-store tests |

Nothing in this project approves or releases a payment.
