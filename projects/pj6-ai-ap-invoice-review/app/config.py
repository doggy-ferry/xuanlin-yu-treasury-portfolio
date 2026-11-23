"""Paths and environment-driven settings. Secrets are read only from environment variables."""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = Path(os.environ.get("PJ6_DATA_DIR", ROOT / "data"))
FRONTEND_DIR = ROOT / "frontend"


def runtime_dir() -> Path:
    """Local, git-ignored folder for review actions, AI call logs and live results (demo only)."""
    p = Path(os.environ.get("PJ6_RUNTIME_DIR", ROOT / "runtime"))
    p.mkdir(parents=True, exist_ok=True)
    return p


def live_max_invoices() -> int:
    return int(os.environ.get("PJ6_LIVE_MAX_INVOICES", "5"))
