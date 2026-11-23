"""Generate the fully synthetic, reproducible dataset for PJ6.

Everything produced here is fictional: company names, bank accounts, PO numbers,
invoice numbers and amounts. A fixed random seed makes the output byte-identical
on every run. The ground-truth file is written last and locked with a SHA-256
hash (data/ground_truth.lock); only the evaluation module may read it.

Usage:  python scripts/generate_synthetic_data.py [--out data]
"""

from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import random
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

SEED = 20261123
AS_OF = date(2026, 6, 30)
N_INVOICES = 100

CATALOG: dict[str, list[str]] = {
    "IT hardware": ["laptop docking stations", "24-port network switches", "USB-C monitors",
                    "wireless keyboards", "rack mount servers", "external SSD drives"],
    "Software": ["analytics platform licence renewal", "cloud storage subscription",
                 "endpoint security licences", "workflow automation licences",
                 "backup service subscription", "reporting tool licences"],
    "Facilities": ["office cleaning services", "HVAC maintenance visit", "fire extinguisher inspection",
                   "lift servicing", "garden and grounds upkeep", "pest control visit"],
    "Logistics": ["freight forwarding export shipment", "courier services", "customs clearance handling",
                  "warehouse pallet storage", "last-mile delivery runs", "container drayage"],
    "Professional services": ["internal audit support hours", "translation services", "legal drafting hours",
                              "process mapping workshop", "market research report", "training facilitation days"],
    "Office supplies": ["printer paper A4 boxes", "ergonomic chairs", "whiteboard markers",
                        "filing cabinets", "desk lamps", "stapler and binder sets"],
    "Marketing": ["trade show booth design", "printed brochures", "banner stands",
                  "promotional tote bags", "photography session", "social media campaign assets"],
    "Industrial packaging": ["corrugated shipping cartons", "pallet wrap film", "foam edge protectors",
                             "strapping bands", "label rolls", "bubble wrap rolls"],
}
OTHER_CATEGORY = {  # used for category-switch semantic conflicts
    "IT hardware": "Marketing", "Software": "Facilities", "Facilities": "IT hardware",
    "Logistics": "Marketing", "Professional services": "Industrial packaging",
    "Office supplies": "Logistics", "Marketing": "Software", "Industrial packaging": "Professional services",
}
FIRST = ["Quillon", "Vantrel", "Mirevale", "Oskaro", "Tellmark", "Brindlow", "Kestrane", "Hollowfen",
         "Dravik", "Ampelon", "Sorrelby", "Naventa", "Ulmerton", "Pelhaven", "Zyrelle", "Corvane",
         "Fenwick-Lowe", "Gaskarth", "Ilmarin", "Jovelle", "Lumbrey", "Marrowdale"]
NOUN = ["Components", "Systems", "Supply", "Works", "Solutions", "Trading", "Industries", "Partners"]
COUNTRIES = [  # (country, currency, tax_rate)
    ("GB", "GBP", "0.20"), ("US", "USD", "0.08"), ("DE", "EUR", "0.19"), ("JP", "JPY", "0.10"),
    ("CN", "CNY", "0.13"), ("NL", "EUR", "0.21"), ("IE", "EUR", "0.23"), ("US", "USD", "0.07"),
]
CURRENCY_PLAN = ["GBP"] * 5 + ["USD"] * 5 + ["EUR"] * 6 + ["JPY"] * 3 + ["CNY"] * 3  # 22 suppliers

CLEAN_NOTES = ["", "", "", "", "Payment terms as per PO.", "Delivered to main warehouse; signed copy attached.",
               "Thank you for your business.", "Please quote the PO number on remittance."]


def money(value: Decimal | float | int | str, cur: str) -> Decimal:
    places = Decimal("1") if cur == "JPY" else Decimal("0.01")
    return Decimal(str(value)).quantize(places, rounding=ROUND_HALF_UP)


def fmt(value: Decimal, cur: str) -> str:
    return str(money(value, cur))


def build(seed: int = SEED) -> dict[str, list[dict]]:
    rng = random.Random(seed)

    # ---- suppliers -------------------------------------------------------
    cats = list(CATALOG)
    suppliers: list[dict] = []
    used_names: set[str] = set()
    used_banks: set[str] = set()
    for i, cur in enumerate(CURRENCY_PLAN, start=1):
        options = [c for c in COUNTRIES if c[1] == cur]
        country, _, rate = options[(i - 1) % len(options)]
        while True:
            name = f"{rng.choice(FIRST)} {rng.choice(NOUN)} Ltd"
            if name not in used_names:
                used_names.add(name)
                break
        bank = _bank(rng, country, used_banks)
        suppliers.append({
            "supplier_id": f"SUP-{i:03d}", "supplier_name": name, "country": country, "currency": cur,
            "default_tax_rate": rate, "bank_account": bank, "status": "active",
            "category": cats[(i - 1) % len(cats)],
        })

    # ---- base documents --------------------------------------------------
    docs: list[dict] = []
    for i in range(N_INVOICES):
        sup = suppliers[rng.randrange(len(suppliers))]
        cur = sup["currency"]
        items = rng.sample(CATALOG[sup["category"]], rng.randint(2, 4))
        lines = []
        for item in items:
            qty = rng.choice([2, 4, 6, 8, 10, 12, 20, 24])
            if cur == "JPY":
                price = Decimal(rng.randint(15, 900) * 100)
            else:
                price = Decimal(rng.randint(15, 900)) + Decimal(rng.choice(["0.00", "0.50", "0.95"]))
            lines.append({"description": item, "quantity": qty, "unit_price": money(price, cur),
                          "po_price": money(price, cur)})
        po_date = date(2026, 1, 5) + timedelta(days=rng.randint(0, 135))
        recv = po_date + timedelta(days=rng.randint(5, 25))
        inv_date = recv + timedelta(days=rng.randint(1, 10))
        terms = rng.choice([30, 45, 60])
        docs.append({
            "idx": i, "supplier_id": sup["supplier_id"], "category": sup["category"], "currency": cur,
            "tax_rate": Decimal(sup["default_tax_rate"]), "po_number": f"PO-26{i + 1:04d}",
            "po_date": po_date, "recv_date": recv, "invoice_date": inv_date, "terms": terms,
            "items": items, "lines": lines, "po_description": "Supply of " + "; ".join(items),
            "invoice_description": "Invoice covering " + "; ".join(items),
            "notes": rng.choice(CLEAN_NOTES), "bank": sup["bank_account"], "fraction_billed": 1,
            "invoice_number": f"{sup['supplier_id'][-3:]}-{inv_date.strftime('%y%m')}-{1000 + i * 13 + rng.randint(0, 12)}",
            "labels": [], "po_exists": True, "dup_of": None, "dup_style": None,
            "tax_override": None, "total_override": None, "subtotal_override": None,
            "due_override": None, "inv_currency": None, "inv_supplier": None,
        })

    # ---- decide roles ----------------------------------------------------
    dup_idx = rng.sample(range(40, N_INVOICES), 4)
    pool = [i for i in range(N_INVOICES) if i not in dup_idx]
    plan_single = (["AMOUNT_MISMATCH"] * 3 + ["CURRENCY_MISMATCH"] * 3 + ["PO_NOT_FOUND"] * 3
                   + ["SUPPLIER_MISMATCH"] * 3 + ["QUANTITY_PRICE_MISMATCH"] * 2 + ["TAX_INCONSISTENCY"]
                   + ["DATE_OUTLIER"] + ["BANK_ACCOUNT_CHANGE"] + ["SEMANTIC_CATEGORY"] + ["SEMANTIC_SUBTLE"]
                   + ["UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE"] * 2 + ["MISSING_FIELD_PO", "MISSING_FIELD_BANK"])
    plan_double = ["D_DATE_BANK", "D_SEM_AMOUNT", "D_QTY_TAX"]
    chosen = rng.sample(pool, len(plan_single) + len(plan_double))
    roles = dict(zip(chosen, plan_single + plan_double))
    remaining = [i for i in pool if i not in roles]
    originals = rng.sample([i for i in remaining if i < 40], 4)
    normals = [i for i in remaining if i not in originals]

    # ---- benign decoys among the normal invoices (still ground-truth normal) ----
    rng2 = random.Random(seed + 1)
    decoys = rng2.sample(normals, 17)
    for i in decoys[:4]:          # vague wording that is nevertheless consistent with its PO
        d = docs[i]
        d["po_description"] = "General services as agreed"
        d["invoice_description"] = "Miscellaneous services as discussed"
        for ln in d["lines"]:
            ln["description"] = "Miscellaneous services"
    for i in decoys[4:9]:         # legitimate partial receipts, billed only for what arrived
        docs[i]["fraction_billed"] = Decimal("0.5")
    docs[decoys[9]]["notes"] = "Scan slightly skewed but fully legible."
    for i in decoys[10:12]:       # one-cent tax rounding differences within tolerance
        if docs[i]["currency"] != "JPY":
            docs[i]["tax_override"] = -1
    for i in decoys[12:17]:
        docs[i]["notes"] = rng2.choice(["Payment terms: net 30 as per PO.", "Goods delivered in full per delivery note.",
                                        "Remit to the bank account on file."])

    # ---- apply anomalies -------------------------------------------------
    other_supplier = lambda sid, cur: rng.choice(  # noqa: E731
        [s for s in suppliers if s["supplier_id"] != sid and s["currency"] == cur])
    new_bank = lambda: _bank(rng, "GB", used_banks)  # noqa: E731

    def overbill(d: dict) -> None:
        ln = max(d["lines"], key=lambda x: x["quantity"] * x["unit_price"])  # largest line, so the effect is material
        ln["unit_price"] = money(ln["unit_price"] * Decimal(str(rng.choice([1.09, 1.12, 1.15]))), d["currency"])

    amount_cases = 0
    for i, role in roles.items():
        d = docs[i]
        if role == "AMOUNT_MISMATCH":
            amount_cases += 1
            if amount_cases <= 2:
                overbill(d)
            else:
                d["subtotal_override"] = Decimal("1.05")  # header subtotal differs from line sum
            d["labels"] = ["AMOUNT_MISMATCH"]
        elif role == "CURRENCY_MISMATCH":
            cur = d["currency"]
            d["inv_currency"] = rng.choice([c for c in ("USD", "EUR", "GBP", "CNY") if c != cur])
            d["labels"] = ["CURRENCY_MISMATCH"]
        elif role == "PO_NOT_FOUND":
            d["po_exists"] = False
            d["po_number"] = f"PO-9{rng.randint(10000, 99999)}"
            d["labels"] = ["PO_NOT_FOUND"]
        elif role == "SUPPLIER_MISMATCH":
            o = other_supplier(d["supplier_id"], d["currency"])
            d["inv_supplier"] = o["supplier_id"]
            d["bank"] = o["bank_account"]
            d["labels"] = ["SUPPLIER_MISMATCH"]
        elif role == "QUANTITY_PRICE_MISMATCH":
            d["qty_price_break"] = True
            d["labels"] = ["QUANTITY_PRICE_MISMATCH"]
        elif role == "TAX_INCONSISTENCY":
            d["total_override"] = "extra"
            d["labels"] = ["TAX_INCONSISTENCY"]
        elif role == "DATE_OUTLIER":
            d["invoice_date"] = d["po_date"] - timedelta(days=12)
            d["labels"] = ["DATE_OUTLIER"]
        elif role == "BANK_ACCOUNT_CHANGE":
            d["bank"] = new_bank()
            d["labels"] = ["BANK_ACCOUNT_CHANGE"]
        elif role == "SEMANTIC_CATEGORY":
            other = OTHER_CATEGORY[d["category"]]
            wrong = rng.sample(CATALOG[other], len(d["items"]))
            d["invoice_description"] = "Invoice covering " + "; ".join(wrong)
            for ln, w in zip(d["lines"], wrong):
                ln["description"] = w
            d["labels"] = ["SEMANTIC_DESCRIPTION_CONFLICT"]
        elif role == "SEMANTIC_SUBTLE":
            d["po_description"] = "Supply of " + "; ".join(d["items"]) + " (12-month term, standard support)"
            d["invoice_description"] = ("Invoice covering " + "; ".join(d["items"])
                                        + " (scope changed to 36-month term, premium support tier)")
            d["labels"] = ["SEMANTIC_DESCRIPTION_CONFLICT"]
        elif role == "UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE":
            d["notes"] = rng.choice([
                "Scan quality poor; amount and PO reference partly illegible, keyed manually from image.",
                "Document unreadable in places; handwritten corrections on totals, evidence incomplete."])
            d["labels"] = ["UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE"]
        elif role == "MISSING_FIELD_PO":
            d["blank"] = "po_number"
            d["labels"] = ["MISSING_FIELD"]
        elif role == "MISSING_FIELD_BANK":
            d["blank"] = "bank_account"
            d["labels"] = ["MISSING_FIELD"]
        elif role == "D_DATE_BANK":
            d["invoice_date"] = date(2027, 2, 14)
            d["bank"] = new_bank()
            d["labels"] = ["DATE_OUTLIER", "BANK_ACCOUNT_CHANGE"]
        elif role == "D_SEM_AMOUNT":
            overbill(d)
            d["notes"] = ("Payment conditional on revised terms: 50% advance payment required "
                          "before release of the balance.")
            d["labels"] = ["SEMANTIC_DESCRIPTION_CONFLICT", "AMOUNT_MISMATCH"]
        elif role == "D_QTY_TAX":
            d["qty_price_break"] = True
            d["total_override"] = "double_tax"
            d["labels"] = ["QUANTITY_PRICE_MISMATCH", "TAX_INCONSISTENCY"]

    # single semantic case #2 uses the notes-based exception condition on a *clean* amount: handled by D_SEM_AMOUNT.

    # ---- materialise tables ---------------------------------------------
    invoices, lines_out, pos, grs = [], [], {}, {}
    final_docs: list[dict] = []
    line_counter = 0
    for d in docs:
        cur_po = d["currency"]
        frac = d["fraction_billed"]
        billed_lines = []
        for ln in d["lines"]:
            qty = int(ln["quantity"] * frac) if frac != 1 else ln["quantity"]
            billed_lines.append({**ln, "quantity": qty, "amount": money(qty * ln["unit_price"], cur_po)})
        billed_net = sum((ln["amount"] for ln in billed_lines), Decimal(0))
        # PO and goods receipt reflect the agreed (pre-overbilling) price.
        po_net = sum((money(ln["quantity"] * ln["po_price"], cur_po) for ln in d["lines"]), Decimal(0))
        recv_net = sum((money(int(ln["quantity"] * frac) * ln["po_price"], cur_po)
                        for ln in d["lines"]), Decimal(0))
        subtotal = billed_net
        inv_cur = d["inv_currency"] or cur_po
        rate = d["tax_rate"]
        tax = money(subtotal * rate, inv_cur)
        if d["tax_override"] == -1:
            tax = tax - Decimal("0.01")
        if d["subtotal_override"] is not None:
            subtotal = money(subtotal * d["subtotal_override"], inv_cur)
            tax = money(subtotal * rate, inv_cur)
        total = subtotal + tax
        if d["total_override"] == "extra":
            total = total + money(subtotal * Decimal("0.02"), inv_cur)
        elif d["total_override"] == "double_tax":
            tax = tax * 2
            total = subtotal + tax
        if d.get("qty_price_break"):
            for bl in billed_lines:  # unit price drifts away from the stated line amount
                bl["unit_price"] = money(bl["unit_price"] * Decimal("1.07"), inv_cur)
        sid = d["inv_supplier"] or d["supplier_id"]
        due = d["invoice_date"] + timedelta(days=d["terms"])
        final_docs.append({"doc": d, "lines": billed_lines, "subtotal": subtotal, "tax": tax, "total": total,
                           "cur": inv_cur, "sid": sid, "due": due, "po_net": po_net, "recv_net": recv_net})

    # duplicates copy an earlier, already-finalised normal invoice
    orig_for = dict(zip(dup_idx, originals))
    for k, j in enumerate(dup_idx):
        src = copy.deepcopy(final_docs[orig_for[j]])
        dst = final_docs[j]
        style = "exact" if k < 2 else "renumbered"
        number = src["doc"]["invoice_number"] + ("" if style == "exact" else "-R")
        dst["doc"]["labels"] = ["DUPLICATE_INVOICE"]
        dst["doc"]["dup_of"] = orig_for[j]
        for key in ("lines", "subtotal", "tax", "total", "cur", "sid", "due", "po_net", "recv_net"):
            dst[key] = src[key]
        for key in ("po_number", "invoice_date", "bank", "invoice_description", "notes", "po_description"):
            dst["doc"][key] = src["doc"][key]
        dst["doc"]["invoice_number"] = number
        dst["doc"]["po_exists"] = False  # PO belongs to the original; no second PO row is written
        dst["doc"]["currency"] = src["doc"]["currency"]
        dst["doc"]["tax_rate"] = src["doc"]["tax_rate"]

    for fd in final_docs:
        d = fd["doc"]
        inv_id = f"INV-{d['idx'] + 1:04d}"
        cur = fd["cur"]
        invoices.append({
            "invoice_id": inv_id, "invoice_number": d["invoice_number"], "supplier_id": fd["sid"],
            "po_number": "" if d.get("blank") == "po_number" else d["po_number"], "currency": cur, "subtotal": fmt(fd["subtotal"], cur),
            "tax": fmt(fd["tax"], cur), "total": fmt(fd["total"], cur),
            "invoice_date": d["invoice_date"].isoformat(), "due_date": fd["due"].isoformat(),
            "bank_account": "" if d.get("blank") == "bank_account" else d["bank"], "description": d["invoice_description"], "notes": d["notes"],
        })
        for n, bl in enumerate(fd["lines"], start=1):
            line_counter += 1
            lines_out.append({
                "line_id": f"L-{line_counter:04d}", "invoice_id": inv_id, "line_no": n,
                "description": bl["description"], "quantity": bl["quantity"],
                "unit_price": fmt(bl["unit_price"], cur), "line_amount": fmt(bl["amount"], cur),
            })
        if d["po_exists"] and d["dup_of"] is None:
            pos[d["po_number"]] = {
                "po_number": d["po_number"], "supplier_id": d["supplier_id"], "currency": d["currency"],
                "po_date": d["po_date"].isoformat(), "description": d["po_description"],
                "net_amount": fmt(fd["po_net"], d["currency"]), "tax_rate": str(d["tax_rate"]),
            }
            grs[d["po_number"]] = {
                "receipt_id": f"GR-{d['po_number'][3:]}", "po_number": d["po_number"],
                "received_date": d["recv_date"].isoformat(),
                "received_net_amount": fmt(fd["recv_net"], d["currency"]),
                "status": "partial" if d["fraction_billed"] != 1 else "complete",
            }

    truth = []
    for inv, fd in zip(invoices, final_docs):
        labels = fd["doc"]["labels"]
        if not labels:
            truth.append({"invoice_id": inv["invoice_id"], "is_exception": "false", "anomaly_type": "NONE"})
        for lab in labels:
            truth.append({"invoice_id": inv["invoice_id"], "is_exception": "true", "anomaly_type": lab})

    return {
        "suppliers": suppliers,
        "purchase_orders": sorted(pos.values(), key=lambda r: r["po_number"]),
        "goods_receipts": sorted(grs.values(), key=lambda r: r["po_number"]),
        "invoices": invoices, "invoice_lines": lines_out, "ground_truth": truth,
    }


def _bank(rng: random.Random, country: str, used: set[str]) -> str:
    while True:
        acct = f"SYN-{country}-{rng.randint(10**11, 10**12 - 1)}"
        if acct not in used:
            used.add(acct)
            return acct


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()), lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def main(out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    tables = build()
    for name, rows in tables.items():
        write_csv(out / f"{name}.csv", rows)
    digest = hashlib.sha256((out / "ground_truth.csv").read_bytes()).hexdigest()
    (out / "ground_truth.lock").write_text(digest + "\n", encoding="utf-8")
    inv = tables["invoices"]
    print(f"Wrote {len(inv)} invoices, {len(tables['invoice_lines'])} lines, "
          f"{len(tables['suppliers'])} suppliers to {out}; ground truth locked ({digest[:12]}...)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(Path(__file__).resolve().parents[1] / "data"))
    main(Path(ap.parse_args().out))
