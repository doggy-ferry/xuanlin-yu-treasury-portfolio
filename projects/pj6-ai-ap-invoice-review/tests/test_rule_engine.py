import copy
import shutil
from pathlib import Path

import pytest

from app.evaluator import load_ground_truth
from app.rule_engine import RULE_CODES, load_bundle, run_rules

ROOT = Path(__file__).resolve().parents[1]
SEMANTIC = {"SEMANTIC_DESCRIPTION_CONFLICT", "UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE"}


@pytest.fixture()
def clean(data_dir):
    """A bundle plus the id of a clean normal invoice that is safe to mutate."""
    b = load_bundle(data_dir)
    res = run_rules(b)
    clean_ids = [i for i, f in res.items() if not f]
    inv_id = next(i for i in clean_ids if b.pos[next(x for x in b.invoices if x["invoice_id"] == i)["po_number"]]["currency"] != "JPY")
    return b, inv_id


def codes_for(b, inv_id):
    return {f.code for f in run_rules(b)[inv_id]}


def mutate(clean_fixture, fn):
    b, inv_id = clean_fixture
    b = copy.deepcopy(b)
    inv = next(i for i in b.invoices if i["invoice_id"] == inv_id)
    fn(b, inv)
    return codes_for(b, inv_id)


def test_rules_match_every_structured_ground_truth_label(data_dir):
    res = run_rules(load_bundle(data_dir))
    truth = load_ground_truth(data_dir)
    for inv_id, labels in truth.items():
        assert {f.code for f in res[inv_id]} == labels - SEMANTIC, inv_id


def test_no_false_positives_on_normal_invoices_including_tolerance_cases(data_dir):
    res = run_rules(load_bundle(data_dir))
    truth = load_ground_truth(data_dir)
    assert all(not res[i] for i, labs in truth.items() if not labs)


@pytest.mark.parametrize("name,fn,expected", [
    ("missing", lambda b, i: i.update(po_number=" ", description=""), "MISSING_FIELD"),
    ("supplier_not_found", lambda b, i: i.update(supplier_id="SUP-999"), "SUPPLIER_NOT_FOUND"),
    ("supplier_inactive", lambda b, i: b.suppliers[i["supplier_id"]].update(status="on_hold"), "SUPPLIER_INACTIVE"),
    ("po_not_found", lambda b, i: i.update(po_number="PO-999999"), "PO_NOT_FOUND"),
    ("supplier_mismatch", lambda b, i: b.pos[i["po_number"]].update(supplier_id="SUP-001" if i["supplier_id"] != "SUP-001" else "SUP-002"), "SUPPLIER_MISMATCH"),
    ("currency", lambda b, i: i.update(currency="CHF"), "CURRENCY_MISMATCH"),
    ("header_vs_lines", lambda b, i: i.update(subtotal=str(float(i["subtotal"]) + 50)), "AMOUNT_MISMATCH"),
    ("vs_po", lambda b, i: b.pos[i["po_number"]].update(net_amount="1.00"), "AMOUNT_MISMATCH"),
    ("qty_price", lambda b, i: b.lines[i["invoice_id"]][0].update(quantity="999"), "QUANTITY_PRICE_MISMATCH"),
    ("tax_rate", lambda b, i: i.update(tax=str(float(i["tax"]) * 2)), "TAX_INCONSISTENCY"),
    ("total_sum", lambda b, i: i.update(total=str(float(i["total"]) + 5)), "TAX_INCONSISTENCY"),
    ("date_before_po", lambda b, i: i.update(invoice_date="2020-01-01"), "DATE_OUTLIER"),
    ("date_future", lambda b, i: i.update(invoice_date="2030-01-01"), "DATE_OUTLIER"),
    ("due_before_invoice", lambda b, i: i.update(due_date="2000-01-01"), "DATE_OUTLIER"),
    ("bank", lambda b, i: i.update(bank_account="SYN-XX-000000000000"), "BANK_ACCOUNT_CHANGE"),
])
def test_each_rule_fires(clean, name, fn, expected):
    assert expected in mutate(clean, fn), name


def test_duplicate_rules_fire_for_exact_and_renumbered(clean):
    b, inv_id = clean
    b = copy.deepcopy(b)
    src = next(i for i in b.invoices if i["invoice_id"] == inv_id)
    exact = {**src, "invoice_id": "INV-9001"}
    renum = {**src, "invoice_id": "INV-9002", "invoice_number": src["invoice_number"] + "-X"}
    b.invoices += [exact, renum]
    b.lines["INV-9001"] = copy.deepcopy(b.lines[inv_id])
    b.lines["INV-9002"] = copy.deepcopy(b.lines[inv_id])
    res = run_rules(b)
    assert "DUPLICATE_INVOICE" in {f.code for f in res["INV-9001"]}
    assert "DUPLICATE_INVOICE" in {f.code for f in res["INV-9002"]}
    assert "DUPLICATE_INVOICE" not in {f.code for f in res[inv_id]}  # original is not flagged


def test_all_declared_rule_codes_are_covered_by_tests():
    covered = {"MISSING_FIELD", "SUPPLIER_NOT_FOUND", "SUPPLIER_INACTIVE", "PO_NOT_FOUND", "SUPPLIER_MISMATCH",
               "CURRENCY_MISMATCH", "AMOUNT_MISMATCH", "QUANTITY_PRICE_MISMATCH", "TAX_INCONSISTENCY",
               "DATE_OUTLIER", "BANK_ACCOUNT_CHANGE", "DUPLICATE_INVOICE"}
    assert covered == set(RULE_CODES)


def test_rule_engine_never_reads_ground_truth(tmp_path, data_dir):
    for mod in ("rule_engine.py", "ai_review.py", "pipeline.py"):
        src = (ROOT / "app" / mod).read_text(encoding="utf-8").lower()
        assert "ground_truth" not in src and "evaluator" not in src, mod
    # and it runs identically when the ground-truth files do not exist at all
    for f in data_dir.iterdir():
        if f.name.startswith("ground_truth"):
            continue
        shutil.copy(f, tmp_path / f.name)
    a = {k: [x.code for x in v] for k, v in run_rules(load_bundle(tmp_path)).items()}
    b = {k: [x.code for x in v] for k, v in run_rules(load_bundle(data_dir)).items()}
    assert a == b
