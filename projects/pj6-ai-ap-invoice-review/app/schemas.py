"""Pydantic models shared by the rule engine, AI layer, review store and API."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field, field_validator

AI_REASON_CODES = {
    "SEMANTIC_DESCRIPTION_CONFLICT",
    "VAGUE_DESCRIPTION",
    "EXCEPTION_CONDITION_IN_NOTES",
    "UNREADABLE_OR_LOW_CONFIDENCE_EVIDENCE",
    "AI_OUTPUT_INVALID",
    "AI_UNAVAILABLE",
}
LOW_CONFIDENCE_THRESHOLD = 0.70

ReviewAction = Literal["approve_normal", "confirm_exception", "reject_ai_flag", "escalate", "add_note"]


class RuleFinding(BaseModel):
    code: str
    severity: Literal["high", "medium", "low"]
    message: str


class AIResult(BaseModel):
    """Structured output required from the semantic check (live or precomputed)."""

    invoice_id: str
    semantic_status: Literal["pass", "exception", "uncertain"]
    reason_codes: list[str] = Field(default_factory=list)
    explanation: str = Field(default="", max_length=800)
    confidence: float = Field(ge=0.0, le=1.0)
    needs_human_review: bool
    source: str = "precomputed_simulation"  # or "live_claude" / "fallback"

    @field_validator("reason_codes")
    @classmethod
    def _known_codes(cls, v: list[str]) -> list[str]:
        unknown = [c for c in v if c not in AI_REASON_CODES]
        if unknown:
            raise ValueError(f"unknown reason codes: {unknown}")
        return v

    def normalised(self) -> "AIResult":
        """Low confidence always means a human looks at it; a 'pass' can never be low confidence."""
        if self.confidence < LOW_CONFIDENCE_THRESHOLD:
            status = "uncertain" if self.semantic_status == "pass" else self.semantic_status
            return self.model_copy(update={"needs_human_review": True, "semantic_status": status})
        if self.semantic_status != "pass":
            return self.model_copy(update={"needs_human_review": True})
        return self


class ReviewRequest(BaseModel):
    action: ReviewAction
    note: str = Field(default="", max_length=1000)


class LiveRequest(BaseModel):
    invoice_ids: list[str] = Field(min_length=1)
