import csv
import importlib.util
from collections import Counter
from pathlib import Path

from app.evaluator import ANOMALY_TYPES, load_ground_truth

ROOT = Path(__file__).resolve().parents[1]
SPEC = {"DUPLICATE_INVOICE": 4, "AMOUNT_MISMATCH": 4, "CURRENCY_MISMATCH": 3, "PO_NOT_FOUND": 3,
        "SUPPLIER_MISMATCH": 3, "QUANTITY_PRICE_MISMATCH": 3, "TAX_INCONSISTENCY": 2, "DATE_OUTLIER": 2,
        "BANK_ACCOUNT_CHANGE": 2, "MISSING_FIELD": 2, "SEMANTIC_DESCRIPTION_CONFLICT": 3,
        "UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE": 2}


def rows(data_dir, name):
    with (data_dir / f"{name}.csv").open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def test_exactly_100_invoices_and_required_tables(data_dir):
    assert len(rows(data_dir, "invoices")) == 100
    assert (data_dir / "precomputed_ai_results.json").exists()
    for t in ("suppliers", "purchase_orders", "goods_receipts", "invoice_lines", "ground_truth"):
        assert (data_dir / f"{t}.csv").exists()


def test_invoice_fields_and_volume(data_dir):
    inv = rows(data_dir, "invoices")
    for f in ("invoice_id", "invoice_number", "supplier_id", "po_number", "currency", "subtotal", "tax", "total",
              "invoice_date", "due_date", "bank_account", "description"):
        assert f in inv[0]
    assert len(rows(data_dir, "invoice_lines")) >= 250
    assert 20 <= len(rows(data_dir, "suppliers")) <= 25
    assert {"JPY", "USD", "CNY", "EUR", "GBP"} <= {r["currency"] for r in inv}


def test_ids_unique_and_only_deliberate_duplicate_numbers(data_dir):
    inv = rows(data_dir, "invoices")
    assert len({r["invoice_id"] for r in inv}) == 100
    counts = Counter((r["supplier_id"], r["invoice_number"]) for r in inv)
    dupes = [k for k, n in counts.items() if n > 1]
    assert len(dupes) == 2  # the two exact-duplicate exceptions; renumbered ones differ by suffix


def test_70_normal_30_exception(data_dir):
    truth = load_ground_truth(data_dir)
    assert len(truth) == 100
    assert sum(1 for t in truth.values() if not t) == 70
    assert sum(1 for t in truth.values() if t) == 30


def test_ground_truth_distribution_matches_spec(data_dir):
    truth = load_ground_truth(data_dir)
    counts = Counter(t for labs in truth.values() for t in labs)
    assert dict(counts) == SPEC
    assert set(SPEC) == set(ANOMALY_TYPES)
    multi = [i for i, labs in truth.items() if len(labs) > 1]
    assert 3 <= len(multi) <= 5


def test_everything_is_visibly_synthetic(data_dir):
    for r in rows(data_dir, "suppliers"):
        assert r["bank_account"].startswith("SYN-")
    blob = "".join(p.read_text(encoding="utf-8") for p in data_dir.glob("*.csv")).lower()
    assert "http" not in blob and "@" not in blob


def test_generation_is_reproducible_and_ground_truth_locked(tmp_path, data_dir):
    spec = importlib.util.spec_from_file_location("gen", ROOT / "scripts" / "generate_synthetic_data.py")
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)
    gen.main(tmp_path)
    for name in ("suppliers", "purchase_orders", "goods_receipts", "invoices", "invoice_lines", "ground_truth"):
        assert (tmp_path / f"{name}.csv").read_bytes() == (data_dir / f"{name}.csv").read_bytes(), name
    assert (tmp_path / "ground_truth.lock").read_text() == (data_dir / "ground_truth.lock").read_text()

