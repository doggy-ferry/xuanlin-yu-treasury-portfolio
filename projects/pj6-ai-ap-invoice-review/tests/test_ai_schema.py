import json
from types import SimpleNamespace

import anthropic
import httpx
import pytest

from app.ai_review import (AIConfigError, AIReviewer, LiveLimitError, build_context, load_precomputed,
                           parse_ai_response)
from app.pipeline import Pipeline
from app.rule_engine import load_bundle
from app.schemas import AIResult

REQ = httpx.Request("POST", "https://example.invalid/v1/messages")


def good(iid="INV-0001", **over):
    d = {"invoice_id": iid, "semantic_status": "pass", "reason_codes": [], "explanation": "ok",
         "confidence": 0.95, "needs_human_review": False}
    d.update(over)
    return json.dumps(d)


class FakeClient:
    """Mimics client.messages.create; `script` items are exceptions or text."""

    def __init__(self, script):
        self.script, self.calls = list(script), 0
        self.messages = SimpleNamespace(create=self._create)

    def _create(self, **kw):
        self.calls += 1
        item = self.script.pop(0) if len(self.script) > 1 else self.script[0]
        if isinstance(item, Exception):
            raise item
        content = [SimpleNamespace(text=item)] if item is not None else []
        return SimpleNamespace(content=content, usage=SimpleNamespace(input_tokens=400, output_tokens=80))


@pytest.fixture()
def bundle(data_dir):
    return load_bundle(data_dir)


def reviewer(script, tmp_path, attempts=3):
    return AIReviewer(client=FakeClient(script), model="test-model", max_attempts=attempts,
                      sleep=lambda s: None, log_path=tmp_path / "calls.jsonl")


# ---- parsing / schema ----
@pytest.mark.parametrize("text", ["not json at all", "", None, "[1,2]", "{}", good(semantic_status="maybe"),
                                  good(confidence=7), good(reason_codes=["MADE_UP_CODE"])])
def test_bad_output_fails_safe_to_human_review(text):
    r = parse_ai_response(text, "INV-0001")
    assert r.semantic_status == "uncertain" and r.needs_human_review and r.source == "fallback"
    assert r.reason_codes == ["AI_OUTPUT_INVALID"]


def test_valid_and_fenced_json_accepted():
    assert parse_ai_response(good(), "INV-0001").semantic_status == "pass"
    assert parse_ai_response("```json\n" + good() + "\n```", "INV-0001").source == "live_claude"


def test_echoed_invoice_id_is_not_trusted():
    assert parse_ai_response(good(iid="INV-9999"), "INV-0001").invoice_id == "INV-0001"


def test_low_confidence_goes_to_human_queue():
    r = parse_ai_response(good(confidence=0.4), "INV-0001")
    assert r.needs_human_review and r.semantic_status == "uncertain"
    r2 = AIResult(invoice_id="x", semantic_status="exception", confidence=0.9, needs_human_review=False).normalised()
    assert r2.needs_human_review  # any non-pass result needs a human


def test_low_confidence_precomputed_result_is_queued(data_dir, monkeypatch):
    p = Pipeline(data_dir)
    p.precomputed["INV-0002"] = AIResult(invoice_id="INV-0002", semantic_status="pass", confidence=0.2,
                                         needs_human_review=False).normalised()
    v = next(x for x in p.views() if x["invoice_id"] == "INV-0002")
    assert v["in_queue"]


# ---- API behaviour (fake SDK client) ----
def test_success_path_records_stats_and_log_without_secrets(bundle, tmp_path, monkeypatch):
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test-secret-123")
    rv = reviewer([good("INV-0001")], tmp_path)
    res = rv.review_one(bundle, "INV-0001")
    assert res.semantic_status == "pass" and rv.stats["calls"] == 1 and rv.stats["estimated_cost_usd"] > 0
    log = (tmp_path / "calls.jsonl").read_text()
    assert "sk-ant" not in log and "INV-0001" in log


def test_same_invoice_is_never_called_twice(bundle, tmp_path):
    rv = reviewer([good()], tmp_path)
    rv.review_one(bundle, "INV-0001"); rv.review_one(bundle, "INV-0001")
    assert rv._client.calls == 1


@pytest.mark.parametrize("exc", [
    anthropic.RateLimitError("rl", response=httpx.Response(429, request=REQ), body=None),
    anthropic.APITimeoutError(request=REQ),
    anthropic.APIConnectionError(request=REQ),
    anthropic.InternalServerError("boom", response=httpx.Response(500, request=REQ), body=None),
])
def test_transient_errors_retry_then_escalate(bundle, tmp_path, exc):
    rv = reviewer([exc], tmp_path, attempts=3)
    r = rv.review_one(bundle, "INV-0001")
    assert rv._client.calls == 3  # bounded retries
    assert r.reason_codes == ["AI_UNAVAILABLE"] and r.needs_human_review
    assert rv.review_one(bundle, "INV-0001") and rv._client.calls == 6  # failures are not cached


def test_rate_limit_then_success(bundle, tmp_path):
    rl = anthropic.RateLimitError("rl", response=httpx.Response(429, request=REQ), body=None)
    rv = reviewer([rl, good()], tmp_path)
    assert rv.review_one(bundle, "INV-0001").semantic_status == "pass" and rv._client.calls == 2


def test_auth_error_is_not_retried(bundle, tmp_path):
    exc = anthropic.AuthenticationError("bad key", response=httpx.Response(401, request=REQ), body=None)
    rv = reviewer([exc], tmp_path)
    assert rv.review_one(bundle, "INV-0001").reason_codes == ["AI_UNAVAILABLE"] and rv._client.calls == 1


def test_empty_and_invalid_model_output(bundle, tmp_path):
    assert reviewer([None], tmp_path).review_one(bundle, "INV-0001").reason_codes == ["AI_OUTPUT_INVALID"]
    assert reviewer(["I think it is fine"], tmp_path).review_one(bundle, "INV-0001").needs_human_review


def test_live_batch_limit_default_five(bundle, tmp_path):
    rv = reviewer([good()], tmp_path)
    ids = [i["invoice_id"] for i in bundle.invoices][:6]
    with pytest.raises(LiveLimitError):
        rv.review_many(bundle, ids)
    assert rv._client.calls == 0
    assert len(rv.review_many(bundle, ids[:5])) == 5


def test_config_errors_without_env(bundle):
    with pytest.raises(AIConfigError):
        AIReviewer().review_one(bundle, "INV-0001")
    assert not AIReviewer.available()


def test_prompt_context_contains_no_ground_truth_or_arithmetic_fields(bundle):
    ctx = build_context(bundle, "INV-0001")
    blob = json.dumps(ctx).lower()
    assert set(ctx) == {"invoice_id", "invoice_description", "invoice_notes", "invoice_line_descriptions",
                        "po_description", "goods_receipt_status"}
    assert "ground" not in blob and "anomaly" not in blob and "bank" not in blob


def test_demo_mode_runs_without_key_or_network(data_dir, monkeypatch):
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    p = Pipeline(data_dir)
    assert len(p.views()) == 100
    meta, results = load_precomputed(data_dir / "precomputed_ai_results.json")
    assert "NOT live" in meta["disclosure"] and len(results) == 100
    assert all(r.source == "precomputed_simulation" for r in results.values())
