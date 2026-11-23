# Architecture

```
data/*.csv ──► rule_engine.py ──────────────┐
(100% synthetic)   (deterministic controls)  ├─► pipeline.py ─► FastAPI ─► frontend (vanilla JS)
                ┌► ai_review.py ─────────────┘        ▲
precomputed_ai_results.json (Demo Mode)               │
Claude API via backend only (Live API Mode)   review_store.py (human actions, local JSON)

ground_truth.csv ──► evaluator.py ONLY (locked by SHA-256) ──► /api/evaluation
```

## Layers

1. **Deterministic rules** (`app/rule_engine.py`): pure Python over invoices, lines, PO, goods receipt and supplier master.
   Arithmetic, tax, duplicate, currency, supplier, bank-account and date controls. No model involved.
2. **Semantic AI check** (`app/ai_review.py`): limited to description-vs-PO conflict, vague wording, exception conditions in
   notes and unreadable evidence. Output is validated against `AIResult` (Pydantic). Any failure degrades to
   `uncertain` + `needs_human_review`.
3. **Human review** (`app/review_store.py`): approve as normal, confirm exception, reject AI flag, escalate, add note; each
   entry stores timestamp, outcome and note. Demo storage only, no accounts.

## Modes

| | Demo Mode (default, public) | Live API Mode (local/secure backend) |
|---|---|---|
| Key needed | No | Yes: `ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL` on the server |
| AI results | `precomputed_ai_results.json` (offline simulation, labelled as such) | Real Claude call through the Anthropic Python SDK |
| Limits | n/a | max 5 invoices per request (`PJ6_LIVE_MAX_INVOICES`), bounded retries, per-invoice cache |
| Front end | Reads only this backend or the static `snapshot.json` | Never talks to Anthropic and never sees the key |

## Ground-truth isolation

`ground_truth.csv` is written last by the generator and locked with a hash. Only `app/evaluator.py` opens it; a test asserts
that no other module mentions it, and that the rule engine gives identical output when the file does not exist. Review-mode
API payloads contain no ground-truth fields (tested). Overview and Evaluation views are explicitly labelled as using it.

## Final-status logic

An invoice is *auto-passed* only if no rule fired, the AI status is `pass` and the AI did not ask for review (confidence ≥ 0.70).
Otherwise it is queued. The last human decision sets the final status; `reject_ai_flag` clears only the AI flag (rule findings
remain). Pending queue items count as flagged in evaluation.

## Scripted demo reviewer (simulation)

To show the Final row without inventing human judgement, `POST /api/reviews/scripted-reviewer` applies a fixed policy to pending
items: rule finding → confirm exception; AI exception ≥ 0.75 confidence → confirm; unreadable evidence → escalate; otherwise
reject the AI-only flag. Entries are tagged `scripted-demo-reviewer`. It does not read the ground truth.
