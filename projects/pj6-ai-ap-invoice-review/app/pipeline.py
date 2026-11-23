"""Combine rules, AI results and human actions into per-invoice views (no ground truth here)."""

from __future__ import annotations

import json
from pathlib import Path

from .ai_review import AIReviewer, fallback_result, load_precomputed
from .config import DATA_DIR, runtime_dir
from .review_store import OUTCOME, ReviewStore
from .rule_engine import Bundle, load_bundle, risk_from_findings, run_rules
from .schemas import AIResult

STATUS_LABEL = {
    "auto_passed": "Auto-passed (low risk)", "pending_review": "Human review required",
    "approved_normal": "Approved as normal", "exception_confirmed": "Exception confirmed",
    "ai_flag_rejected": "AI flag rejected", "escalated": "Escalated",
}


class Pipeline:
    def __init__(self, data_dir: Path = DATA_DIR, store: ReviewStore | None = None,
                 reviewer: AIReviewer | None = None) -> None:
        self.data_dir = Path(data_dir)
        self.bundle: Bundle = load_bundle(self.data_dir)
        self.rules = run_rules(self.bundle)
        self.meta, self.precomputed = load_precomputed(self.data_dir / "precomputed_ai_results.json")
        self.store = store or ReviewStore()
        self.reviewer = reviewer
        self._live_path = runtime_dir() / "live_ai_results.json"
        self.live: dict[str, AIResult] = {}
        if self._live_path.exists():
            try:
                self.live = {r["invoice_id"]: AIResult(**r) for r in json.loads(self._live_path.read_text("utf-8"))}
            except (ValueError, KeyError):
                self.live = {}

    # -- AI ---------------------------------------------------------------
    def ai_for(self, invoice_id: str) -> AIResult:
        if invoice_id in self.live:
            return self.live[invoice_id]
        return self.precomputed.get(invoice_id) or fallback_result(
            invoice_id, "AI_UNAVAILABLE", "No AI result stored; escalated to human review.")

    def run_live(self, invoice_ids: list[str]) -> list[AIResult]:
        if self.reviewer is None:
            self.reviewer = AIReviewer()
        results = self.reviewer.review_many(self.bundle, invoice_ids)
        for r in results:
            if r.source != "fallback":
                self.live[r.invoice_id] = r
        self._live_path.write_text(json.dumps([r.model_dump() for r in self.live.values()], indent=1), encoding="utf-8")
        return results

    def api_stats(self) -> dict:
        s = self.reviewer.stats if self.reviewer else {"calls": 0, "estimated_cost_usd": 0.0}
        return {**s, "live_results_stored": len(self.live)}

    # -- views ------------------------------------------------------------
    def _supplier_name(self, sid: str) -> str:
        return self.bundle.suppliers.get(sid, {}).get("supplier_name", "(unknown supplier)")

    def view(self, inv: dict) -> dict:
        iid = inv["invoice_id"]
        findings = self.rules[iid]
        ai = self.ai_for(iid)
        rule_codes = [f.code for f in findings]
        in_queue = bool(findings) or ai.semantic_status != "pass" or ai.needs_human_review
        decision = self.store.latest_decision(iid)
        status = "auto_passed" if not in_queue else "pending_review"
        if decision:
            status = OUTCOME[decision["action"]]
        if status == "auto_passed" or status in ("approved_normal",):
            final_flagged = False
        elif status == "ai_flag_rejected":
            final_flagged = bool(findings)
        else:  # pending, confirmed, escalated
            final_flagged = True
        risk = risk_from_findings(findings)
        if risk == "none":
            risk = "medium" if ai.semantic_status == "exception" else "low" if in_queue else "none"
        reviewed = decision is not None
        return {
            "invoice_id": iid, "supplier_id": inv["supplier_id"], "supplier_name": self._supplier_name(inv["supplier_id"]),
            "invoice_number": inv["invoice_number"], "po_number": inv["po_number"], "currency": inv["currency"],
            "amount": inv["total"], "rule_status": "exception" if findings else "pass", "rule_codes": rule_codes,
            "ai_status": ai.semantic_status, "ai_codes": ai.reason_codes, "ai_confidence": ai.confidence,
            "ai_needs_review": ai.needs_human_review, "ai_source": ai.source,
            "in_queue": in_queue, "review_status": "reviewed" if reviewed else ("pending" if in_queue else "not_required"),
            "final_status": status, "final_label": STATUS_LABEL[status], "final_flagged": final_flagged,
            "risk_level": risk, "reason_codes": sorted(set(rule_codes) | set(ai.reason_codes)),
        }

    def views(self) -> list[dict]:
        return [self.view(i) for i in self.bundle.invoices]

    def public_view(self, v: dict) -> dict:
        """The Review-mode payload: internal evaluation fields are kept, nothing from ground truth exists here."""
        return v

    def detail(self, invoice_id: str) -> dict | None:
        inv = next((i for i in self.bundle.invoices if i["invoice_id"] == invoice_id), None)
        if inv is None:
            return None
        po = self.bundle.pos.get(inv["po_number"])
        ai = self.ai_for(invoice_id)
        return {
            "summary": self.view(inv), "invoice": inv, "supplier": self.bundle.suppliers.get(inv["supplier_id"]),
            "purchase_order": po, "goods_receipt": self.bundle.receipts.get(inv["po_number"]),
            "lines": self.bundle.lines.get(invoice_id, []),
            "rule_findings": [f.model_dump() for f in self.rules[invoice_id]],
            "ai_result": ai.model_dump(), "reviews": self.store.for_invoice(invoice_id),
        }

    # -- scripted reviewer (simulation) --------------------------------------
    def run_scripted_reviewer(self) -> int:
        """Illustrative stand-in for a human: applies a fixed, documented policy to pending items.
        It does not read the ground truth. Actions are tagged actor='scripted-demo-reviewer'."""
        n = 0
        for v in self.views():
            if v["final_status"] != "pending_review":
                continue
            ai = self.ai_for(v["invoice_id"])
            if v["rule_codes"]:
                action, note = "confirm_exception", "Scripted policy: deterministic rule finding verified."
            elif ai.semantic_status == "exception" and ai.confidence >= 0.75:
                action, note = "confirm_exception", "Scripted policy: high-confidence AI exception."
            elif "UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE" in ai.reason_codes:
                action, note = "escalate", "Scripted policy: evidence unreadable, escalate for source document."
            else:
                action, note = "reject_ai_flag", "Scripted policy: AI-only flag with no rule finding; dismissed."
            self.store.add(v["invoice_id"], action, note, actor="scripted-demo-reviewer")
            n += 1
        return n
