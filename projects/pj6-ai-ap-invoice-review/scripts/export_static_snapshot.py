"""Export frontend/snapshot.json so the demo can run as a static site (no backend, no API key).

The snapshot is computed by the same Python code as the API. Review-mode payloads
(invoices, details) contain no ground truth; the evaluation block does, and the UI only
shows it in the Evaluation/Overview views. The Final row uses the scripted demo reviewer.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
os.environ["PJ6_RUNTIME_DIR"] = tempfile.mkdtemp(prefix="pj6_snapshot_")  # keep real review logs untouched

from app.config import DATA_DIR  # noqa: E402
from app.evaluator import evaluate, load_ground_truth  # noqa: E402
from app.pipeline import Pipeline  # noqa: E402


def main() -> None:
    p = Pipeline(DATA_DIR)
    p.run_scripted_reviewer()  # one consistent state for every page: queue, details and evaluation
    base_views = p.views()
    details = {v["invoice_id"]: p.detail(v["invoice_id"]) for v in base_views}
    evaluation = evaluate(p.views(), load_ground_truth(DATA_DIR))
    snapshot = {
        "config": {"mode": "demo", "synthetic": True, "ai_results_source": p.meta.get("source"),
                   "ai_disclosure": p.meta.get("disclosure"), "live_available": False, "backend": False},
        "invoices": base_views, "details": details, "evaluation": evaluation,
    }
    out = ROOT / "frontend" / "snapshot.json"
    payload = json.dumps(snapshot, separators=(",", ":"))
    out.write_text(payload, encoding="utf-8")
    # Same data as a script so index.html also works when opened directly from disk (file://).
    (ROOT / "frontend" / "snapshot.js").write_text("window.PJ6_SNAPSHOT=" + payload + ";", encoding="utf-8")
    print(f"Wrote {out} ({out.stat().st_size // 1024} KiB)")


if __name__ == "__main__":
    main()
