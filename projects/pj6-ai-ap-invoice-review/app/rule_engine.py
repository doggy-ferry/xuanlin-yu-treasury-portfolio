"""Deterministic AP controls: numbers, master data and duplicates.

This module is pure Python. It never reads the ground-truth file and has no
knowledge of how the data set was constructed; it only sees invoices, purchase
orders, goods receipts and the supplier master.
"""

from __future__ import annotations

import csv
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path

from .schemas import RuleFinding

REQUIRED_FIELDS = ["invoice_number", "supplier_id", "po_number", "currency", "subtotal", "tax", "total",
                   "invoice_date", "due_date", "bank_account", "description"]
SEVERITY = {
    "DUPLICATE_INVOICE": "high", "BANK_ACCOUNT_CHANGE": "high", "SUPPLIER_MISMATCH": "high",
    "PO_NOT_FOUND": "high", "CURRENCY_MISMATCH": "high", "SUPPLIER_NOT_FOUND": "high",
    "SUPPLIER_INACTIVE": "high", "AMOUNT_MISMATCH": "medium", "QUANTITY_PRICE_MISMATCH": "medium",
    "TAX_INCONSISTENCY": "medium", "DATE_OUTLIER": "medium", "MISSING_FIELD": "medium",
}
RULE_CODES = sorted(SEVERITY)


@dataclass(frozen=True)
class RuleConfig:
    as_of: date = date(2026, 6, 30)
    pct_tolerance: Decimal = Decimal("0.01")       # 1% price tolerance versus PO / receipt
    max_days_after_receipt: int = 120


@dataclass
class Bundle:
    """Business data visible to the checks (no ground truth)."""

    suppliers: dict[str, dict] = field(default_factory=dict)
    pos: dict[str, dict] = field(default_factory=dict)
    receipts: dict[str, dict] = field(default_factory=dict)  # keyed by po_number
    invoices: list[dict] = field(default_factory=list)
    lines: dict[str, list[dict]] = field(default_factory=dict)


def _read(path: Path) -> list[dict]:
    with path.open(newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def load_bundle(data_dir: Path) -> Bundle:
    data_dir = Path(data_dir)
    b = Bundle()
    b.suppliers = {r["supplier_id"]: r for r in _read(data_dir / "suppliers.csv")}
    b.pos = {r["po_number"]: r for r in _read(data_dir / "purchase_orders.csv")}
    b.receipts = {r["po_number"]: r for r in _read(data_dir / "goods_receipts.csv")}
    b.invoices = sorted(_read(data_dir / "invoices.csv"), key=lambda r: r["invoice_id"])
    for r in _read(data_dir / "invoice_lines.csv"):
        b.lines.setdefault(r["invoice_id"], []).append(r)
    return b


def _dec(v) -> Decimal | None:
    try:
        return Decimal(str(v).strip())
    except (InvalidOperation, AttributeError):
        return None


def _date(v) -> date | None:
    try:
        return date.fromisoformat(str(v).strip())
    except ValueError:
        return None


def _tol(cur: str) -> Decimal:
    return Decimal("0.5") if cur == "JPY" else Decimal("0.011")


def _round(x: Decimal, cur: str) -> Decimal:
    return x.quantize(Decimal("1") if cur == "JPY" else Decimal("0.01"))


def _norm(s: str) -> str:
    return "".join(str(s).split()).upper()


class _Collector:
    def __init__(self) -> None:
        self._m: dict[str, list[str]] = {}

    def add(self, code: str, msg: str) -> None:
        self._m.setdefault(code, []).append(msg)

    def findings(self) -> list[RuleFinding]:
        return [RuleFinding(code=c, severity=SEVERITY[c], message=" ".join(m)) for c, m in self._m.items()]


def run_rules(bundle: Bundle, config: RuleConfig = RuleConfig()) -> dict[str, list[RuleFinding]]:
    """Run every control over every invoice. Invoices are processed in ID order so that
    the *later* submission of a duplicate pair is the one flagged."""
    results: dict[str, list[RuleFinding]] = {}
    seen_number: dict[tuple[str, str], str] = {}
    seen_amount: dict[tuple[str, str, str], tuple[str, str]] = {}
    for inv in bundle.invoices:
        c = _Collector()
        _check_fields(inv, bundle, c)
        _check_master_and_po(inv, bundle, c)
        _check_lines_and_amounts(inv, bundle, config, c)
        _check_tax(inv, bundle, c)
        _check_dates(inv, bundle, config, c)
        _check_bank(inv, bundle, c)
        _check_duplicates(inv, seen_number, seen_amount, c)
        results[inv["invoice_id"]] = c.findings()
    return results


def _check_fields(inv: dict, b: Bundle, c: _Collector) -> None:
    missing = [f for f in REQUIRED_FIELDS if not str(inv.get(f, "")).strip()]
    if not b.lines.get(inv["invoice_id"]):
        missing.append("invoice lines")
    for f in ("subtotal", "tax", "total"):
        if str(inv.get(f, "")).strip() and _dec(inv[f]) is None:
            missing.append(f"{f} (not numeric)")
    if missing:
        c.add("MISSING_FIELD", "Missing or invalid: " + ", ".join(missing) + ".")


def _check_master_and_po(inv: dict, b: Bundle, c: _Collector) -> None:
    sid = inv.get("supplier_id", "").strip()
    if sid:
        sup = b.suppliers.get(sid)
        if sup is None:
            c.add("SUPPLIER_NOT_FOUND", f"Supplier {sid} is not in the supplier master.")
        elif sup.get("status", "active") != "active":
            c.add("SUPPLIER_INACTIVE", f"Supplier {sid} status is {sup['status']}.")
    po_no = inv.get("po_number", "").strip()
    if not po_no:
        return
    po = b.pos.get(po_no)
    if po is None:
        c.add("PO_NOT_FOUND", f"PO {po_no} does not exist in the purchase order table.")
        return
    if sid and po["supplier_id"] != sid:
        c.add("SUPPLIER_MISMATCH", f"Invoice supplier {sid} differs from PO supplier {po['supplier_id']}.")
    if inv.get("currency", "") and po["currency"] != inv["currency"]:
        c.add("CURRENCY_MISMATCH", f"Invoice currency {inv['currency']} differs from PO currency {po['currency']}.")


def _check_lines_and_amounts(inv: dict, b: Bundle, cfg: RuleConfig, c: _Collector) -> None:
    cur = inv.get("currency", "") or "USD"
    tol = _tol(cur)
    lines = b.lines.get(inv["invoice_id"], [])
    subtotal = _dec(inv.get("subtotal"))
    bad_lines = []
    line_sum = Decimal(0)
    for ln in lines:
        q, p, a = _dec(ln["quantity"]), _dec(ln["unit_price"]), _dec(ln["line_amount"])
        if None in (q, p, a):
            continue
        line_sum += a
        if abs(_round(q * p, cur) - a) > tol:
            bad_lines.append(f"line {ln['line_no']} ({q} x {p} != {a})")
    if bad_lines:
        c.add("QUANTITY_PRICE_MISMATCH", "Quantity x unit price differs from line amount: " + "; ".join(bad_lines) + ".")
    if subtotal is not None and lines and abs(line_sum - subtotal) > tol:
        c.add("AMOUNT_MISMATCH", f"Header subtotal {subtotal} differs from sum of lines {line_sum}.")
    po = b.pos.get(inv.get("po_number", "").strip())
    if po and subtotal is not None:
        po_net = _dec(po["net_amount"])
        if po_net is not None and subtotal > po_net * (1 + cfg.pct_tolerance) + tol:
            c.add("AMOUNT_MISMATCH", f"Subtotal {subtotal} exceeds PO net amount {po_net}.")
        gr = b.receipts.get(po["po_number"])
        recv = _dec(gr["received_net_amount"]) if gr else None
        if recv is not None and abs(subtotal - recv) > max(tol, recv * cfg.pct_tolerance):
            c.add("AMOUNT_MISMATCH", f"Subtotal {subtotal} differs from goods receipt value {recv}.")


def _check_tax(inv: dict, b: Bundle, c: _Collector) -> None:
    cur = inv.get("currency", "") or "USD"
    tol = _tol(cur)
    sub, tax, total = _dec(inv.get("subtotal")), _dec(inv.get("tax")), _dec(inv.get("total"))
    if None in (sub, tax, total):
        return
    po = b.pos.get(inv.get("po_number", "").strip())
    sup = b.suppliers.get(inv.get("supplier_id", "").strip())
    rate = _dec(po["tax_rate"]) if po else (_dec(sup["default_tax_rate"]) if sup else None)
    if rate is not None and abs(_round(sub * rate, cur) - tax) > tol:
        c.add("TAX_INCONSISTENCY", f"Tax {tax} does not match {rate:.0%} of subtotal ({_round(sub * rate, cur)}).")
    if abs(sub + tax - total) > tol:
        c.add("TAX_INCONSISTENCY", f"Total {total} differs from subtotal + tax ({sub + tax}).")


def _check_dates(inv: dict, b: Bundle, cfg: RuleConfig, c: _Collector) -> None:
    d, due = _date(inv.get("invoice_date")), _date(inv.get("due_date"))
    if d is None:
        return
    po = b.pos.get(inv.get("po_number", "").strip())
    if po:
        pd = _date(po["po_date"])
        if pd and d < pd:
            c.add("DATE_OUTLIER", f"Invoice date {d} is earlier than PO date {pd}.")
        gr = b.receipts.get(po["po_number"])
        rd = _date(gr["received_date"]) if gr else None
        if rd and (d - rd).days > cfg.max_days_after_receipt:
            c.add("DATE_OUTLIER", f"Invoice date is {(d - rd).days} days after goods receipt.")
    if d > cfg.as_of:
        c.add("DATE_OUTLIER", f"Invoice date {d} is after the review date {cfg.as_of}.")
    if due and due < d:
        c.add("DATE_OUTLIER", f"Due date {due} is before invoice date {d}.")


def _check_bank(inv: dict, b: Bundle, c: _Collector) -> None:
    sup = b.suppliers.get(inv.get("supplier_id", "").strip())
    acct = inv.get("bank_account", "")
    if sup and acct.strip() and _norm(acct) != _norm(sup["bank_account"]):
        c.add("BANK_ACCOUNT_CHANGE", "Bank account on invoice differs from the supplier master record.")


def _check_duplicates(inv: dict, seen_number: dict, seen_amount: dict, c: _Collector) -> None:
    sid, num = inv.get("supplier_id", ""), _norm(inv.get("invoice_number", ""))
    k1 = (sid, num)
    k2 = (sid, str(inv.get("total", "")), str(inv.get("invoice_date", "")))
    if num and k1 in seen_number:
        c.add("DUPLICATE_INVOICE", f"Same supplier and invoice number already submitted as {seen_number[k1]}.")
    elif sid and inv.get("total") and k2 in seen_amount and seen_amount[k2][1] != num:
        c.add("DUPLICATE_INVOICE",
              f"Suspected resubmission: same supplier, amount and date as {seen_amount[k2][0]}.")
    if num:
        seen_number.setdefault(k1, inv["invoice_id"])
    if sid and inv.get("total"):
        seen_amount.setdefault(k2, (inv["invoice_id"], num))


def risk_from_findings(findings: list[RuleFinding]) -> str:
    sev = {f.severity for f in findings}
    return "high" if "high" in sev else "medium" if "medium" in sev else "none"
