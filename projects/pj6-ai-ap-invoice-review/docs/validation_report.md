# Validation report — PJ6 AI-Assisted AP Invoice Review & Exception Triage

Generated 2026-11-23 by `scripts/generate_validation_report.py` from the data and the evaluator; no figure below is typed in by hand. **All data is 100% synthetic. Metrics describe this 100-invoice test set only and are not production accuracy.**

## 1. Final data volume

- Invoices: **100**; invoice lines: **287**; suppliers: **22**; purchase orders: **93**; goods receipts: **93**.
- Currencies: CNY, EUR, GBP, JPY, USD.
- Ground truth locked with SHA-256 (`data/ground_truth.lock`); verified on every evaluation.

## 2. Normal vs exception invoices

- Normal: **70**; exception: **30**; invoices with more than one label: **3**.

## 3. Exception labels by type

| Type | Labels |
|---|---|
| AMOUNT_MISMATCH | 4 |
| BANK_ACCOUNT_CHANGE | 2 |
| CURRENCY_MISMATCH | 3 |
| DATE_OUTLIER | 2 |
| DUPLICATE_INVOICE | 4 |
| MISSING_FIELD | 2 |
| PO_NOT_FOUND | 3 |
| QUANTITY_PRICE_MISMATCH | 3 |
| SEMANTIC_DESCRIPTION_CONFLICT | 3 |
| SUPPLIER_MISMATCH | 3 |
| TAX_INCONSISTENCY | 2 |
| UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE | 2 |

Total labels: 33.

## 4. Rule engine detection

Invoice level: TP 26, FP 0, FN 4, TN 70; precision 100.0%, recall 86.7%, F1 92.9%.

| Type | In data | Rules | AI | Combined | Missed by both |
|---|---|---|---|---|---|
| DUPLICATE_INVOICE | 4 | 4 | 0 | 4 | - |
| AMOUNT_MISMATCH | 4 | 4 | 0 | 4 | - |
| CURRENCY_MISMATCH | 3 | 3 | 0 | 3 | - |
| PO_NOT_FOUND | 3 | 3 | 0 | 3 | - |
| SUPPLIER_MISMATCH | 3 | 3 | 0 | 3 | - |
| QUANTITY_PRICE_MISMATCH | 3 | 3 | 0 | 3 | - |
| TAX_INCONSISTENCY | 2 | 2 | 0 | 2 | - |
| DATE_OUTLIER | 2 | 2 | 0 | 2 | - |
| BANK_ACCOUNT_CHANGE | 2 | 2 | 0 | 2 | - |
| MISSING_FIELD | 2 | 2 | 0 | 2 | - |
| SEMANTIC_DESCRIPTION_CONFLICT | 3 | 0 | 2 | 2 | INV-0017 |
| UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE | 2 | 0 | 2 | 2 | - |

Rules never see semantic or evidence-quality problems, by design; the AI layer covers those.

## 5. Precomputed AI results

- Source: `precomputed_simulation`. **These are not live Claude outputs.** Pre-generated synthetic demo results. NOT live Claude output. Produced by a deterministic offline simulation so the demo runs without an API key.
- Invoices flagged or uncertain: 12 of 100; AI-only precision 66.7%, recall 26.7%.
- The simulation is a word-overlap/keyword heuristic. Its errors (see section 7) illustrate the kind of gaps a human queue must absorb; they do not measure Claude.

## 6. Combined workflow metrics

| Method | Invoices a human checks | TP | FP | FN | TN | Precision | Recall | F1 |
|---|---|---|---|---|---|---|---|---|
| Manual sampling (assumption model) | 25 | 9 | 0 | 21 | 70 | 100.0% | 30.0% | 46.2% |
| Rules only | 26 | 26 | 0 | 4 | 70 | 100.0% | 86.7% | 92.9% |
| AI only | 12 | 8 | 4 | 22 | 66 | 66.7% | 26.7% | 38.1% |
| Rules + AI | 33 | 29 | 4 | 1 | 66 | 87.9% | 96.7% | 92.1% |
| Final (scripted demo reviewer applied) | 29 | 29 | 0 | 1 | 70 | 100.0% | 96.7% | 98.3% |

- Review reduction rate (auto-passed / total): **67.0%** (67 auto-passed, 33 queued).
- The *Final* row uses a **scripted** reviewer policy (documented in `docs/architecture.md`), not real human judgement. Manual sampling is an assumption model (seeded 25% sample, perfect on inspected invoices).

## 7. False positives and false negatives (Rules + AI)

| Kind | Invoice | Ground truth | Rule codes | AI |
|---|---|---|---|---|
| FP | INV-0001 | normal | - | uncertain VAGUE_DESCRIPTION |
| FP | INV-0011 | normal | - | uncertain VAGUE_DESCRIPTION |
| FP | INV-0033 | normal | - | uncertain VAGUE_DESCRIPTION |
| FP | INV-0059 | normal | - | uncertain VAGUE_DESCRIPTION |
| FN | INV-0017 | SEMANTIC_DESCRIPTION_CONFLICT | - | pass  |

FP: consistent invoices with generic wording, deliberately included as realistic decoys; the AI cannot verify them so a human is asked. FN: a subtle scope change (12-month to 36-month term) that shares most words with the PO; the offline simulation passes it. A real model may or may not catch it; that is untested here.

## 8. API error-handling tests

`tests/test_ai_schema.py` uses a fake SDK client (no network, no key) and verifies: invalid JSON, empty output, unknown reason codes and out-of-range confidence all fail safe to `uncertain` + human review; rate limit, timeout, connection and 5xx errors retry up to the configured maximum and then escalate; auth errors are not retried; failures are not cached; the same invoice is never called twice; more than 5 invoices per live run is refused before any call; the log contains no API key; the prompt context holds no ground truth.

## 9. Automated test run

`pytest` result: **103 passed (pytest -q)**.

## 10. Mobile and responsive results

`tests/test_frontend_responsive.py` drives a real Chromium through Playwright at **390x844, 430x932, 768x1024 and 1440x900** on four views (Overview, Review Queue, Invoice Detail, Evaluation):

- No horizontal page overflow (`scrollWidth <= viewport width`) in any combination.
- Every button, select, search box, textarea and checkbox label is at least 44 px tall.
- The queue table switches to stacked cards at 900 px and below, and remains a table on desktop.
- Review Queue and Invoice Detail contain no ground-truth text; ground truth appears only in Overview/Evaluation, which are labelled.
- The static snapshot mode renders without a backend.

## 11. Known limitations

- Synthetic data of 100 invoices; patterns are simple and injected by construction, so rules score unrealistically well.
- AI results in the public demo are an offline simulation, not Claude. Live mode has been tested only against a fake client in this project.
- Invoice-level evaluation; amounts and currencies are not converted; no multi-currency tolerance logic.
- Header-level PO and goods receipt (no PO-line matching, no cumulative invoiced-versus-ordered tracking).
- No document images, OCR or PDF handling; 'unreadable evidence' is represented by a text note.
- Review storage is a local JSON file; no authentication, roles, or audit-grade immutability.
- Cost estimate uses configurable placeholder token prices, not a billing figure.

## 12. Suggested next steps

- Run `generate_demo_results.py --live` on a small subset with your own key and compare against the simulation.
- Add PO-line matching and cumulative invoiced-versus-received checks.
- Add a prompt-injection test set (invoice text that tries to instruct the model).
- Replace JSON storage with an append-only table and add reviewer identity before any real use.
- Report calibration of AI confidence once real model outputs exist.
