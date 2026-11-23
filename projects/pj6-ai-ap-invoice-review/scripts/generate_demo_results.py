"""Create data/precomputed_ai_results.json for Demo Mode.

IMPORTANT - honesty note
------------------------
The default output of this script is NOT produced by Claude. It comes from a small,
deterministic, offline *simulation* of a semantic checker (word-overlap and keyword
heuristics). It exists so the public demo can run without an API key and without
spending money. It has no access to the ground-truth file, but it is a stand-in and
must not be read as a measurement of Claude's accuracy.

To regenerate the file from real Claude calls with your own key:
    set ANTHROPIC_API_KEY=...  and  ANTHROPIC_MODEL=...
    python scripts/generate_demo_results.py --live --limit 5
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.ai_review import AIReviewer, build_context  # noqa: E402
from app.rule_engine import load_bundle  # noqa: E402
from app.schemas import AIResult  # noqa: E402

STOP = {"the", "of", "and", "for", "a", "an", "to", "in", "on", "supply", "invoice", "covering", "with", "as"}
VAGUE = re.compile(r"\b(miscellaneous|general services|sundry|as discussed|as agreed)\b", re.I)
CONDITION = re.compile(r"\b(conditional|revised terms|advance payment|subject to|disputed|pending approval)\b", re.I)
UNREADABLE = re.compile(r"\b(illegible|unreadable|poor scan|scan quality poor|handwritten corrections)\b", re.I)


def _tokens(text: str) -> set[str]:
    return {w for w in re.findall(r"[a-z0-9\-]+", text.lower()) if w not in STOP and len(w) > 2}


def simulate(ctx: dict) -> AIResult:
    iid = ctx["invoice_id"]
    notes = ctx["invoice_notes"] or ""
    inv_text = " ".join([ctx["invoice_description"], *ctx["invoice_line_descriptions"]])
    if UNREADABLE.search(notes):
        return AIResult(invoice_id=iid, semantic_status="uncertain",
                        reason_codes=["UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE"], confidence=0.3, needs_human_review=True,
                        explanation="Notes indicate the source evidence is partly unreadable; the extracted text cannot be relied on.")
    if CONDITION.search(notes):
        return AIResult(invoice_id=iid, semantic_status="exception", reason_codes=["EXCEPTION_CONDITION_IN_NOTES"],
                        confidence=0.82, needs_human_review=True,
                        explanation="Notes state a payment condition that is not part of the purchase order terms.")
    if VAGUE.search(inv_text):
        return AIResult(invoice_id=iid, semantic_status="uncertain", reason_codes=["VAGUE_DESCRIPTION"],
                        confidence=0.55, needs_human_review=True,
                        explanation="Description is too generic to verify what was supplied.")
    po_tokens = _tokens(ctx["po_description"] or "")
    if not po_tokens:
        return AIResult(invoice_id=iid, semantic_status="uncertain", reason_codes=["SEMANTIC_DESCRIPTION_CONFLICT"],
                        confidence=0.4, needs_human_review=True,
                        explanation="No purchase order text is available to compare against.")
    overlap = len(po_tokens & _tokens(inv_text)) / len(po_tokens)
    if overlap < 0.2:
        return AIResult(invoice_id=iid, semantic_status="exception", reason_codes=["SEMANTIC_DESCRIPTION_CONFLICT"],
                        confidence=0.88, needs_human_review=True,
                        explanation="Invoiced goods or services do not correspond to the purchase order description.")
    if overlap < 0.5:
        return AIResult(invoice_id=iid, semantic_status="uncertain", reason_codes=["SEMANTIC_DESCRIPTION_CONFLICT"],
                        confidence=0.55, needs_human_review=True,
                        explanation="Partial overlap between invoice and purchase order wording; needs a human look.")
    return AIResult(invoice_id=iid, semantic_status="pass", reason_codes=[], confidence=0.93, needs_human_review=False,
                    explanation="Invoice wording is consistent with the purchase order description.")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--live", action="store_true", help="use real Claude calls (needs your own key)")
    ap.add_argument("--limit", type=int, default=5)
    args = ap.parse_args()
    bundle = load_bundle(ROOT / "data")
    ids = [i["invoice_id"] for i in bundle.invoices]
    if args.live:
        results = AIReviewer().review_many(bundle, ids[: args.limit])
        meta = {"source": "live_claude", "note": "Generated from live Claude calls on a subset."}
    else:
        results = [simulate(build_context(bundle, i)).model_copy(update={"source": "precomputed_simulation"}) for i in ids]
        meta = {
            "source": "precomputed_simulation",
            "generator": "scripts/generate_demo_results.py (deterministic offline heuristic)",
            "disclosure": ("Pre-generated synthetic demo results. NOT live Claude output. Produced by a deterministic "
                           "offline simulation so the demo runs without an API key."),
            "schema_version": 1,
        }
    out = ROOT / "data" / "precomputed_ai_results.json"
    out.write_text(json.dumps({"meta": meta, "results": [r.model_dump() for r in results]}, indent=1) + "\n", encoding="utf-8")
    print(f"Wrote {len(results)} results ({meta['source']}) to {out}")


if __name__ == "__main__":
    main()
