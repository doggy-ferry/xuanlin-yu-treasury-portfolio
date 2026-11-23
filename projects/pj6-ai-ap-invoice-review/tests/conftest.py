import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


@pytest.fixture(autouse=True)
def _isolated_runtime(tmp_path, monkeypatch):
    """Review logs, AI call logs and live results never touch the real runtime folder."""
    monkeypatch.setenv("PJ6_RUNTIME_DIR", str(tmp_path / "runtime"))
    for var in ("ANTHROPIC_API_KEY", "ANTHROPIC_MODEL"):
        monkeypatch.delenv(var, raising=False)
    import app.main as main
    main._pipeline = None
    yield
    main._pipeline = None


@pytest.fixture(scope="session")
def data_dir() -> Path:
    return ROOT / "data"
