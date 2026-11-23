import json
import re
import shutil
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.evaluator import GroundTruthLockError, confusion, evaluate, load_ground_truth
from app.main import app
from app.pipeline import Pipeline

ROOT = Path(__file__).resolve().parents[1]
client = TestClient(app)


def ai_only_flag():
    return next(v for v in client.get("/api/invoices").json()
                if v["rule_status"] == "pass" and v["ai_status"] != "pass")["invoice_id"]


def test_confusion_math_on_toy_data():
    truth = {"a": {"X"}, "b": {"X"}, "c": set(), "d": set()}
    m = confusion({"a", "c"}, truth)
    assert (m["tp"], m["fp"], m["fn"], m["tn"]) == (1, 1, 1, 1)
    assert m["precision"] == 0.5 and m["recall"] == 0.5 and m["f1"] == 0.5


def test_metrics_are_computed_not_hardcoded(data_dir):
    p = Pipeline(data_dir)
    truth = load_ground_truth(data_dir)
    before = evaluate(p.views(), truth)
    views = p.views()
    for v in views:  # sabotage: pretend nothing was flagged by anyone
        v["rule_codes"], v["ai_status"], v["ai_needs_review"], v["ai_codes"] = [], "pass", False, []
    after = evaluate(views, truth)
    positives = sum(1 for t in truth.values() if t)
    assert before["methods"]["rules_ai"]["recall"] > 0.9
    assert after["methods"]["rules_ai"]["recall"] == 0 and after["methods"]["rules_ai"]["fn"] == positives
    assert before != after


def test_ground_truth_lock_detects_tampering(tmp_path, data_dir):
    for f in data_dir.iterdir():
        if f.is_file():
            shutil.copy(f, tmp_path / f.name)
    with (tmp_path / "ground_truth.csv").open("a", encoding="utf-8") as fh:
        fh.write("INV-0001,true,DATE_OUTLIER\n")
    with pytest.raises(GroundTruthLockError):
        load_ground_truth(tmp_path)


def test_evaluation_endpoint_shape_and_counts():
    e = client.get("/api/evaluation").json()
    o = e["overview"]
    assert (o["total_invoices"], o["normal_ground_truth"], o["exception_ground_truth"]) == (100, 70, 30)
    assert set(e["methods"]) == {"manual_sampling", "rules_only", "ai_only", "rules_ai", "final_human"}
    assert e["methods"]["rules_only"]["fp"] == 0
    types = {t["type"] for t in e["per_type"]}
    assert {"DUPLICATE_INVOICE", "MISSING_FIELD", "UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE"} <= types
    assert o["claude_api_calls"] == 0


def test_overview_numbers_reconcile_with_each_other_and_with_methods():
    e = client.get("/api/evaluation").json()
    o, m = e["overview"], e["methods"]
    assert o["sent_to_human_review"] == o["sent_true_exceptions"] + o["sent_false_alarms"]
    assert o["auto_passed"] == o["auto_passed_correct"] + o["auto_passed_missed_exceptions"]
    assert o["exception_ground_truth"] == o["sent_true_exceptions"] + o["auto_passed_missed_exceptions"]
    assert (o["sent_true_exceptions"], o["sent_false_alarms"]) == (m["rules_ai"]["tp"], m["rules_ai"]["fp"])
    queue = [v for v in client.get("/api/invoices").json() if v["in_queue"]]
    assert len(queue) == o["sent_to_human_review"] and 100 - len(queue) == o["auto_passed"]
    assert o["total_invoices"] == o["normal_ground_truth"] + o["exception_ground_truth"]


def test_confirmed_plus_escalated_equal_true_exceptions_after_scripted_reviewer():
    client.post("/api/reviews/scripted-reviewer")
    o = client.get("/api/evaluation").json()["overview"]
    assert o["pending_review"] == 0
    assert o["human_confirmed_exceptions"] + o["human_escalated"] == o["sent_true_exceptions"]
    client.post("/api/reviews/reset")


def test_review_mode_payloads_do_not_leak_ground_truth():
    banned = re.compile(r"ground_truth|anomaly_type|is_exception|ground-truth|actually exception", re.I)
    assert not banned.search(client.get("/api/invoices").text)
    assert not banned.search(client.get("/api/invoices/" + ai_only_flag()).text)
    snap = json.loads((ROOT / "frontend" / "snapshot.json").read_text(encoding="utf-8"))
    assert not banned.search(json.dumps(snap["invoices"])) and not banned.search(json.dumps(snap["details"]))


def test_snapshot_matches_current_data():
    """The static snapshot must be regenerated whenever data or code changes."""
    snap = json.loads((ROOT / "frontend" / "snapshot.json").read_text(encoding="utf-8"))
    live = client.get("/api/invoices").json()
    assert [v["invoice_id"] for v in snap["invoices"]] == [v["invoice_id"] for v in live]
    assert [v["reason_codes"] for v in snap["invoices"]] == [v["reason_codes"] for v in live]
    ev = client.get("/api/evaluation").json()
    assert snap["evaluation"]["overview"]["sent_true_exceptions"] == ev["overview"]["sent_true_exceptions"]
    # every page of the static demo shows ONE state: queue statuses must agree with the Overview counts
    o = snap["evaluation"]["overview"]
    count = lambda s: sum(1 for v in snap["invoices"] if v["final_status"] == s)  # noqa: E731
    assert count("exception_confirmed") == o["human_confirmed_exceptions"]
    assert count("escalated") == o["human_escalated"]
    assert count("ai_flag_rejected") == o["human_ai_flags_rejected"]
    assert count("approved_normal") == o["human_approved_normal"]
    assert count("pending_review") == o["pending_review"]
    assert sum(1 for v in snap["invoices"] if v["in_queue"]) == o["sent_to_human_review"]
    assert all(snap["details"][v["invoice_id"]]["summary"]["final_status"] == v["final_status"] for v in snap["invoices"])
    js = (ROOT / "frontend" / "snapshot.js").read_text(encoding="utf-8")
    assert js == "window.PJ6_SNAPSHOT=" + (ROOT / "frontend" / "snapshot.json").read_text(encoding="utf-8") + ";"


def test_review_actions_are_recorded_with_time_and_note():
    iid = ai_only_flag()
    r = client.post(f"/api/invoices/{iid}/review", json={"action": "reject_ai_flag", "note": "vague but fine"})
    assert r.status_code == 200
    entry = r.json()["entry"]
    assert entry["note"] == "vague but fine" and entry["timestamp"].endswith("+00:00")
    assert r.json()["summary"]["final_status"] == "ai_flag_rejected"
    client.post(f"/api/invoices/{iid}/review", json={"action": "add_note", "note": "second look"})
    hist = client.get(f"/api/invoices/{iid}").json()["reviews"]
    assert [h["action"] for h in hist] == ["reject_ai_flag", "add_note"]
    assert client.get(f"/api/invoices/{iid}").json()["summary"]["final_status"] == "ai_flag_rejected"


def test_review_validation():
    assert client.post("/api/invoices/INV-0001/review", json={"action": "add_note", "note": " "}).status_code == 422
    assert client.post("/api/invoices/INV-0001/review", json={"action": "bogus"}).status_code == 422
    assert client.post("/api/invoices/NOPE/review", json={"action": "escalate"}).status_code == 404
    passing = next(v for v in client.get("/api/invoices").json() if v["ai_status"] == "pass")
    assert client.post(f"/api/invoices/{passing['invoice_id']}/review", json={"action": "reject_ai_flag"}).status_code == 422


def test_human_actions_change_final_evaluation():
    before = client.get("/api/evaluation").json()["overview"]
    assert client.post("/api/reviews/scripted-reviewer").json()["actions_recorded"] == before["sent_to_human_review"]
    e = client.get("/api/evaluation").json()
    assert e["methods"]["final_human"]["fp"] == 0
    assert e["methods"]["final_human"]["fn"] == before["auto_passed_missed_exceptions"]
    assert e["overview"]["pending_review"] == 0
    client.post("/api/reviews/reset")
    assert client.get("/api/evaluation").json()["overview"]["pending_review"] == before["sent_to_human_review"]


def test_live_endpoint_requires_server_side_key(monkeypatch):
    assert client.post("/api/ai/live", json={"invoice_ids": ["INV-0001"]}).status_code == 503
    assert client.get("/api/config").json()["live_available"] is False
    assert client.post("/api/ai/live", json={"invoice_ids": []}).status_code == 422


def test_frontend_has_no_hardcoded_results_and_no_direct_anthropic_calls():
    html = (ROOT / "frontend" / "index.html").read_text(encoding="utf-8")
    js = (ROOT / "frontend" / "app.js").read_text(encoding="utf-8")
    assert not re.search(r"\b(9\d\.\d|8\d\.\d|0\.9\d+|0\.8\d+)%?\b", re.sub(r"toFixed\(\d\)", "", html + js))
    assert "api.anthropic.com" not in js and "x-api-key" not in js.lower()


def test_no_api_key_material_anywhere_in_project():
    pat = re.compile(r"sk-ant-[A-Za-z0-9_\-]{8,}")
    skip = {".venv", "__pycache__", ".pytest_cache", "runtime", "test_artifacts"}
    for f in ROOT.rglob("*"):
        if f.is_file() and not (skip & set(f.relative_to(ROOT).parts)) and f.suffix in {
                ".py", ".js", ".html", ".css", ".json", ".csv", ".md", ".txt", ".example", ".ini", ""}:
            if f.name == "test_ai_schema.py":
                continue  # contains an obviously fake test token
            assert not pat.search(f.read_text(encoding="utf-8", errors="ignore")), f
    assert (ROOT / ".env.example").read_text().replace("\n", "").replace("\r", "") == "ANTHROPIC_API_KEY=ANTHROPIC_MODEL="
