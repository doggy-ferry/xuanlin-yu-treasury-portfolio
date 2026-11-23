"""Append-only JSON log of human review actions. Demo storage only: no users, no auth, no database."""

from __future__ import annotations

import json
import threading
from datetime import datetime, timezone
from pathlib import Path

from .config import runtime_dir

OUTCOME = {  # action -> resulting final status (add_note changes nothing)
    "approve_normal": "approved_normal",
    "confirm_exception": "exception_confirmed",
    "reject_ai_flag": "ai_flag_rejected",
    "escalate": "escalated",
}


class ReviewStore:
    def __init__(self, path: Path | None = None) -> None:
        self.path = path or runtime_dir() / "reviews.json"
        self._lock = threading.Lock()

    def _load(self) -> list[dict]:
        try:
            return json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return []

    def all(self) -> list[dict]:
        with self._lock:
            return self._load()

    def add(self, invoice_id: str, action: str, note: str = "", actor: str = "demo-reviewer") -> dict:
        with self._lock:
            rows = self._load()
            entry = {"id": len(rows) + 1, "invoice_id": invoice_id, "action": action, "note": note.strip(),
                     "actor": actor, "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds")}
            rows.append(entry)
            tmp = self.path.with_suffix(".tmp")
            tmp.write_text(json.dumps(rows, indent=1), encoding="utf-8")
            tmp.replace(self.path)
            return entry

    def for_invoice(self, invoice_id: str) -> list[dict]:
        return [r for r in self.all() if r["invoice_id"] == invoice_id]

    def latest_decision(self, invoice_id: str) -> dict | None:
        decisions = [r for r in self.for_invoice(invoice_id) if r["action"] in OUTCOME]
        return decisions[-1] if decisions else None

    def reset(self) -> None:
        with self._lock:
            if self.path.exists():
                self.path.write_text("[]", encoding="utf-8")
