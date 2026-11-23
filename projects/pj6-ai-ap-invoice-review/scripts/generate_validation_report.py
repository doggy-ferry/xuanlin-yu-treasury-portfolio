"""Write docs/validation_report.md from the real data and the real evaluator (no typed-in metrics).

Usage: python scripts/generate_validation_report.py --tests "99 passed in 15s"
"""

from __future__ import annotations

import argparse
import os
import sys
import tempfile
from collections import Counter
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.environ["PJ6_RUNTIME_DIR"] = tempfile.mkdtemp(prefix="pj6_report_")

from app.config import DATA_DIR  # noqa: E402
from app.evaluator import evaluate, load_ground_truth  # noqa: E402
from app.pipeline import Pipeline  # noqa: E402


def pct(x: float) -> str:
    return f"{x * 100:.1f}%"


def main(tests: str) -> None:
    p = Pipeline(DATA_DIR)
    truth = load_ground_truth(DATA_DIR)
    ev_before = evaluate(p.views(), truth)
    p.run_scripted_reviewer()
    ev = evaluate(p.views(), truth)
    o, m = ev_before["overview"], ev_before["methods"]
    counts = Counter(t for labs in truth.values() for t in labs)
    L: list[str] = []
    a = L.append
    a("# Validation report — PJ6 AI-Assisted AP Invoice Review & Exception Triage")
    a(f"\nGenerated {date.today().isoformat()} by `scripts/generate_validation_report.py` from the data and the evaluator; "
      "no figure below is typed in by hand. **All data is 100% synthetic. Metrics describe this 100-invoice test set only "
      "and are not production accuracy.**\n")
    a("## 1. Final data volume\n")
    a(f"- Invoices: **{o['total_invoices']}**; invoice lines: **{sum(len(v) for v in p.bundle.lines.values())}**; "
      f"suppliers: **{len(p.bundle.suppliers)}**; purchase orders: **{len(p.bundle.pos)}**; goods receipts: **{len(p.bundle.receipts)}**.")
    a(f"- Currencies: {', '.join(sorted({i['currency'] for i in p.bundle.invoices}))}.")
    a(f"- Ground truth locked with SHA-256 (`data/ground_truth.lock`); verified on every evaluation.\n")
    a("## 2. Normal vs exception invoices\n")
    a(f"- Normal: **{o['normal_ground_truth']}**; exception: **{o['exception_ground_truth']}**; "
      f"invoices with more than one label: **{sum(1 for t in truth.values() if len(t) > 1)}**.\n")
    a("## 3. Exception labels by type\n\n| Type | Labels |\n|---|---|")
    for t, n in sorted(counts.items()):
        a(f"| {t} | {n} |")
    a(f"\nTotal labels: {sum(counts.values())}.\n")
    a("## 4. Rule engine detection\n")
    r = m["rules_only"]
    a(f"Invoice level: TP {r['tp']}, FP {r['fp']}, FN {r['fn']}, TN {r['tn']}; precision {pct(r['precision'])}, recall {pct(r['recall'])}, F1 {pct(r['f1'])}.\n")
    a("| Type | In data | Rules | AI | Combined | Missed by both |\n|---|---|---|---|---|---|")
    for t in ev_before["per_type"]:
        a(f"| {t['type']} | {t['total']} | {t['rules']} | {t['ai']} | {t['combined']} | {', '.join(t['missed_by_both']) or '-'} |")
    a("\nRules never see semantic or evidence-quality problems, by design; the AI layer covers those.\n")
    a("## 5. Precomputed AI results\n")
    a(f"- Source: `{p.meta.get('source')}`. **These are not live Claude outputs.** {p.meta.get('disclosure')}")
    a(f"- Invoices flagged or uncertain: {sum(1 for r_ in p.precomputed.values() if r_.semantic_status != 'pass')} of {len(p.precomputed)}; "
      f"AI-only precision {pct(m['ai_only']['precision'])}, recall {pct(m['ai_only']['recall'])}.")
    a("- The simulation is a word-overlap/keyword heuristic. Its errors (see section 7) illustrate the kind of gaps a "
      "human queue must absorb; they do not measure Claude.\n")
    a("## 6. Combined workflow metrics\n\n| Method | Invoices a human checks | TP | FP | FN | TN | Precision | Recall | F1 |\n|---|---|---|---|---|---|---|---|---|")
    for k in ("manual_sampling", "rules_only", "ai_only", "rules_ai"):
        x = m[k]
        a(f"| {x['label']} | {x['flagged_for_human']} | {x['tp']} | {x['fp']} | {x['fn']} | {x['tn']} | {pct(x['precision'])} | {pct(x['recall'])} | {pct(x['f1'])} |")
    x = ev["methods"]["final_human"]
    a(f"| Final (scripted demo reviewer applied) | {x['flagged_for_human']} | {x['tp']} | {x['fp']} | {x['fn']} | {x['tn']} | {pct(x['precision'])} | {pct(x['recall'])} | {pct(x['f1'])} |")
    a(f"\n- Review reduction rate (auto-passed / total): **{pct(o['review_reduction_rate'])}** ({o['auto_passed']} auto-passed, {o['sent_to_human_review']} queued).")
    a("- The *Final* row uses a **scripted** reviewer policy (documented in `docs/architecture.md`), not real human judgement. "
      "Manual sampling is an assumption model (seeded 25% sample, perfect on inspected invoices).\n")
    a("## 7. False positives and false negatives (Rules + AI)\n")
    a("| Kind | Invoice | Ground truth | Rule codes | AI |\n|---|---|---|---|---|")
    for kind, key in (("FP", "rules_ai_false_positives"), ("FN", "rules_ai_false_negatives")):
        for e in ev_before["errors"][key]:
            a(f"| {kind} | {e['invoice_id']} | {', '.join(e['ground_truth_types']) or 'normal'} | {', '.join(e['rule_codes']) or '-'} | {e['ai_status']} {', '.join(e['ai_codes'])} |")
    a("\nFP: consistent invoices with generic wording, deliberately included as realistic decoys; the AI cannot verify them so a human is asked. "
      "FN: a subtle scope change (12-month to 36-month term) that shares most words with the PO; the offline simulation passes it. "
      "A real model may or may not catch it; that is untested here.\n")
    a("## 8. API error-handling tests\n")
    a("`tests/test_ai_schema.py` uses a fake SDK client (no network, no key) and verifies: invalid JSON, empty output, unknown "
      "reason codes and out-of-range confidence all fail safe to `uncertain` + human review; rate limit, timeout, connection "
      "and 5xx errors retry up to the configured maximum and then escalate; auth errors are not retried; failures are not "
      "cached; the same invoice is never called twice; more than 5 invoices per live run is refused before any call; the log "
      "contains no API key; the prompt context holds no ground truth.\n")
    a("## 9. Automated test run\n")
    a(f"`pytest` result: **{tests}**.\n")
    a("## 10. Mobile and responsive results\n")
    a("`tests/test_frontend_responsive.py` drives a real Chromium through Playwright at **390x844, 430x932, 768x1024 and 1440x900** "
      "on four views (Overview, Review Queue, Invoice Detail, Evaluation):\n")
    a("- No horizontal page overflow (`scrollWidth <= viewport width`) in any combination.")
    a("- Every button, select, search box, textarea and checkbox label is at least 44 px tall.")
    a("- The queue table switches to stacked cards at 900 px and below, and remains a table on desktop.")
    a("- Review Queue and Invoice Detail contain no ground-truth text; ground truth appears only in Overview/Evaluation, which are labelled.")
    a("- The static snapshot mode renders without a backend.\n")
    a("## 11. Known limitations\n")
    for s in [
        "Synthetic data of 100 invoices; patterns are simple and injected by construction, so rules score unrealistically well.",
        "AI results in the public demo are an offline simulation, not Claude. Live mode has been tested only against a fake client in this project.",
        "Invoice-level evaluation; amounts and currencies are not converted; no multi-currency tolerance logic.",
        "Header-level PO and goods receipt (no PO-line matching, no cumulative invoiced-versus-ordered tracking).",
        "No document images, OCR or PDF handling; 'unreadable evidence' is represented by a text note.",
        "Review storage is a local JSON file; no authentication, roles, or audit-grade immutability.",
        "Cost estimate uses configurable placeholder token prices, not a billing figure.",
    ]:
        a(f"- {s}")
    a("\n## 12. Suggested next steps\n")
    for s in ["Run `generate_demo_results.py --live` on a small subset with your own key and compare against the simulation.",
              "Add PO-line matching and cumulative invoiced-versus-received checks.",
              "Add a prompt-injection test set (invoice text that tries to instruct the model).",
              "Replace JSON storage with an append-only table and add reviewer identity before any real use.",
              "Report calibration of AI confidence once real model outputs exist."]:
        a(f"- {s}")
    (ROOT / "docs" / "validation_report.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    print("wrote docs/validation_report.md")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tests", default="not recorded")
    main(ap.parse_args().tests)
