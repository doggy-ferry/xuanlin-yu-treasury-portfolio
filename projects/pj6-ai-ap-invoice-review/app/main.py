"""FastAPI backend. Review endpoints never expose ground truth; /api/evaluation does (Evaluation mode only)."""

from __future__ import annotations

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .ai_review import AIConfigError, AIReviewer, LiveLimitError
from .config import DATA_DIR, FRONTEND_DIR, live_max_invoices
from .evaluator import evaluate, load_ground_truth
from .pipeline import Pipeline
from .schemas import LiveRequest, ReviewRequest

app = FastAPI(title="AP Invoice Review & Exception Triage (synthetic demo)", version="1.0.0")
_pipeline: Pipeline | None = None


def get_pipeline() -> Pipeline:
    global _pipeline
    if _pipeline is None:
        _pipeline = Pipeline()
    return _pipeline


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/api/config")
def config() -> dict:
    p = get_pipeline()
    return {
        "mode": "demo", "synthetic": True, "ai_results_source": p.meta.get("source"),
        "ai_disclosure": p.meta.get("disclosure"), "live_available": AIReviewer.available(),
        "live_max_invoices": live_max_invoices(), "backend": True,
    }


@app.get("/api/invoices")
def invoices() -> list[dict]:
    return get_pipeline().views()


@app.get("/api/invoices/{invoice_id}")
def invoice_detail(invoice_id: str) -> dict:
    d = get_pipeline().detail(invoice_id)
    if d is None:
        raise HTTPException(404, "Invoice not found")
    return d


@app.post("/api/invoices/{invoice_id}/review")
def post_review(invoice_id: str, req: ReviewRequest) -> dict:
    p = get_pipeline()
    d = p.detail(invoice_id)
    if d is None:
        raise HTTPException(404, "Invoice not found")
    if req.action == "add_note" and not req.note.strip():
        raise HTTPException(422, "A note is required for add_note")
    if req.action == "reject_ai_flag" and d["ai_result"]["semantic_status"] == "pass":
        raise HTTPException(422, "There is no AI flag to reject on this invoice")
    entry = p.store.add(invoice_id, req.action, req.note)
    return {"entry": entry, "summary": p.detail(invoice_id)["summary"]}


@app.get("/api/reviews")
def reviews() -> list[dict]:
    return get_pipeline().store.all()


@app.post("/api/reviews/scripted-reviewer")
def scripted_reviewer() -> dict:
    return {"actions_recorded": get_pipeline().run_scripted_reviewer()}


@app.post("/api/reviews/reset")
def reset_reviews() -> dict:
    get_pipeline().store.reset()
    return {"status": "reset"}


@app.get("/api/evaluation")
def evaluation() -> dict:
    p = get_pipeline()
    return evaluate(p.views(), load_ground_truth(DATA_DIR), p.api_stats())


@app.post("/api/ai/live")
def live_ai(req: LiveRequest) -> dict:
    """Live API mode: the key stays on the server; capped at PJ6_LIVE_MAX_INVOICES (default 5)."""
    p = get_pipeline()
    if not AIReviewer.available():
        raise HTTPException(503, "Live API mode is not configured (set ANTHROPIC_API_KEY and ANTHROPIC_MODEL on the server).")
    try:
        results = p.run_live(req.invoice_ids)
    except LiveLimitError as exc:
        raise HTTPException(422, str(exc)) from exc
    except AIConfigError as exc:
        raise HTTPException(503, str(exc)) from exc
    return {"results": [r.model_dump() for r in results], "stats": p.api_stats()}


@app.get("/", include_in_schema=False)
def index() -> FileResponse:
    return FileResponse(FRONTEND_DIR / "index.html")


app.mount("/", StaticFiles(directory=FRONTEND_DIR), name="frontend")
