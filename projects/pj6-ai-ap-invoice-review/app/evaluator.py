"""Evaluation against the locked ground truth. This is the ONLY module that reads it.

Every figure is computed from the data on request; nothing here (or in the front end)
is a hard-coded result.
"""

from __future__ import annotations

import csv
import hashlib
import random
from collections import defaultdict
from pathlib import Path

ANOMALY_TYPES = [
    "DUPLICATE_INVOICE", "AMOUNT_MISMATCH", "CURRENCY_MISMATCH", "PO_NOT_FOUND", "SUPPLIER_MISMATCH",
    "QUANTITY_PRICE_MISMATCH", "TAX_INCONSISTENCY", "DATE_OUTLIER", "BANK_ACCOUNT_CHANGE",
    "MISSING_FIELD", "SEMANTIC_DESCRIPTION_CONFLICT", "UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE",
]
AI_CODE_TO_TYPE = {"EXCEPTION_CONDITION_IN_NOTES": "SEMANTIC_DESCRIPTION_CONFLICT"}
MANUAL_SAMPLE_RATE = 0.25
MANUAL_SAMPLE_SEED = 7


class GroundTruthLockError(RuntimeError):
    pass


def load_ground_truth(data_dir: Path, verify_lock: bool = True) -> dict[str, set[str]]:
    """invoice_id -> set of anomaly types (empty set = normal)."""
    data_dir = Path(data_dir)
    path = data_dir / "ground_truth.csv"
    if verify_lock:
        lock = (data_dir / "ground_truth.lock").read_text(encoding="utf-8").strip()
        if hashlib.sha256(path.read_bytes()).hexdigest() != lock:
            raise GroundTruthLockError("ground_truth.csv does not match its lock hash")
    truth: dict[str, set[str]] = defaultdict(set)
    with path.open(newline="", encoding="utf-8") as fh:
        for r in csv.DictReader(fh):
            truth.setdefault(r["invoice_id"], set())
            if r["anomaly_type"] != "NONE":
                truth[r["invoice_id"]].add(r["anomaly_type"])
    return dict(truth)


def confusion(flagged: set[str], truth: dict[str, set[str]]) -> dict:
    positives = {i for i, t in truth.items() if t}
    tp, fp = len(flagged & positives), len(flagged - positives)
    fn, tn = len(positives - flagged), len(set(truth) - positives - flagged)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {"tp": tp, "fp": fp, "fn": fn, "tn": tn, "precision": round(precision, 4), "recall": round(recall, 4),
            "f1": round(f1, 4), "flagged_for_human": len(flagged),
            "false_positive_ids": sorted(flagged - positives), "false_negative_ids": sorted(positives - flagged)}


def evaluate(views: list[dict], truth: dict[str, set[str]], api_stats: dict | None = None) -> dict:
    """`views` are pipeline invoice views (rule codes, AI codes, queue flag, final prediction)."""
    ids = {v["invoice_id"] for v in views}
    truth = {i: t for i, t in truth.items() if i in ids}
    by_id = {v["invoice_id"]: v for v in views}

    rules_flag = {v["invoice_id"] for v in views if v["rule_codes"]}
    ai_flag = {v["invoice_id"] for v in views if v["ai_status"] != "pass" or v["ai_needs_review"]}
    union_flag = rules_flag | ai_flag
    final_flag = {v["invoice_id"] for v in views if v["final_flagged"]}
    rng = random.Random(MANUAL_SAMPLE_SEED)
    sample = set(rng.sample(sorted(ids), round(len(ids) * MANUAL_SAMPLE_RATE)))
    positives = {i for i, t in truth.items() if t}
    manual_flag = sample & positives  # assumption: a reviewer is perfect on the invoices they actually inspect

    methods = {
        "manual_sampling": {**confusion(manual_flag, truth), "flagged_for_human": len(sample),
                            "label": "Manual sampling (assumption model)"},
        "rules_only": {**confusion(rules_flag, truth), "label": "Rules only"},
        "ai_only": {**confusion(ai_flag, truth), "label": "AI only"},
        "rules_ai": {**confusion(union_flag, truth), "label": "Rules + AI"},
        "final_human": {**confusion(final_flag, truth), "label": "Final human-reviewed"},
    }
    pending = sum(1 for v in views if v["final_status"] == "pending_review")
    methods["final_human"]["pending_items"] = pending

    per_type = []
    for t in ANOMALY_TYPES:
        inv = {i for i, labs in truth.items() if t in labs}
        r_hit = {i for i in inv if t in by_id[i]["rule_codes"]}
        a_hit = {i for i in inv if t in {AI_CODE_TO_TYPE.get(c, c) for c in by_id[i]["ai_codes"]}}
        per_type.append({"type": t, "total": len(inv), "rules": len(r_hit), "ai": len(a_hit),
                         "combined": len(r_hit | a_hit), "missed_by_both": sorted(inv - (r_hit | a_hit))})

    queue = [v for v in views if v["in_queue"]]
    queue_ids = {v["invoice_id"] for v in queue}
    auto = [v for v in views if not v["in_queue"]]
    decisions = [v for v in views if v["final_status"] in ("approved_normal", "exception_confirmed", "ai_flag_rejected", "escalated")]
    stats = api_stats or {"calls": 0, "estimated_cost_usd": 0.0}
    count = lambda s: sum(1 for v in views if v["final_status"] == s)  # noqa: E731
    fh = methods["final_human"]
    err_detail = lambda ids_: [  # noqa: E731
        {"invoice_id": i, "ground_truth_types": sorted(truth[i]), "rule_codes": by_id[i]["rule_codes"],
         "ai_codes": by_id[i]["ai_codes"], "ai_status": by_id[i]["ai_status"]} for i in ids_]
    return {
        "overview": {
            "total_invoices": len(views),
            "normal_ground_truth": sum(1 for t in truth.values() if not t),
            "exception_ground_truth": len(positives),
            "auto_passed": len(auto),
            "sent_to_human_review": len(queue),
            # first-pass triage (rules + AI), before any human decision; reconciles: sent = TP + FP
            "sent_true_exceptions": methods["rules_ai"]["tp"], "sent_false_alarms": methods["rules_ai"]["fp"],
            "auto_passed_missed_exceptions": methods["rules_ai"]["fn"], "auto_passed_correct": methods["rules_ai"]["tn"],
            "first_pass": {k: methods["rules_ai"][k] for k in ("precision", "recall", "f1")},
            # current human-review state
            "human_confirmed_exceptions": count("exception_confirmed"), "human_escalated": count("escalated"),
            "human_approved_normal": count("approved_normal"), "human_ai_flags_rejected": count("ai_flag_rejected"),
            "human_decisions_recorded": len(decisions), "pending_review": pending,
            "after_review": {k: fh[k] for k in ("tp", "fp", "fn", "tn", "precision", "recall", "f1")},
            "review_reduction_rate": round(len(auto) / len(views), 4) if views else 0.0,
            "claude_api_calls": stats.get("calls", 0),
            "estimated_api_cost_usd": stats.get("estimated_cost_usd", 0.0),
            "queue_ids": sorted(queue_ids),
        },
        "methods": methods, "per_type": per_type,
        "errors": {
            "rules_ai_false_positives": err_detail(methods["rules_ai"]["false_positive_ids"]),
            "rules_ai_false_negatives": err_detail(methods["rules_ai"]["false_negative_ids"]),
            "final_false_positives": err_detail(methods["final_human"]["false_positive_ids"]),
            "final_false_negatives": err_detail(methods["final_human"]["false_negative_ids"]),
        },
        "assumptions": [
            "Metrics describe this 100-invoice synthetic set only; they are not production accuracy.",
            f"Manual sampling baseline assumes a reviewer inspects a seeded {int(MANUAL_SAMPLE_RATE * 100)}% sample and is perfect on it.",
            "Invoice-level evaluation: an invoice counts as flagged if any control or the AI check raised it.",
            "Pending queue items are counted as flagged in the Final human-reviewed row.",
        ],
    }
