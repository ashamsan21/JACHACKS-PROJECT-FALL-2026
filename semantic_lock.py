"""Local semantic-equivalence checks used by Jac's MeaningLockWalker."""
from __future__ import annotations

import os
from functools import lru_cache

MODEL_NAME = os.getenv(
    "PROMPTZERO_NLI_MODEL", "cross-encoder/nli-MiniLM2-L6-H768"
)


@lru_cache(maxsize=1)
def _model():
    from sentence_transformers import CrossEncoder

    return CrossEncoder(
        MODEL_NAME,
        backend="onnx",
        model_kwargs={
            "file_name": "onnx/model_qint8_arm64.onnx",
            "provider": "CPUExecutionProvider",
        },
    )


def _probabilities(scores) -> list[float]:
    import numpy as np

    values = np.asarray(scores, dtype=float)
    values = values - values.max()
    probabilities = np.exp(values)
    return (probabilities / probabilities.sum()).tolist()


def semantic_equivalence(original: str, rewritten: str) -> dict:
    """Check entailment in both directions; never silently claim unavailable checks ran."""
    if original.strip() == rewritten.strip():
        return {
            "available": True,
            "passed": True,
            "forward": 1.0,
            "reverse": 1.0,
            "model": "exact-match",
        }
    if os.getenv("PROMPTZERO_SEMANTIC_LOCK", "1").lower() in {"0", "false", "off"}:
        return {"available": False, "passed": None, "reason": "disabled"}
    try:
        model = _model()
        scores = model.predict([(original, rewritten), (rewritten, original)])
        labels = {str(value).lower(): int(key) for key, value in model.model.config.id2label.items()}
        entailment = labels.get("entailment", 1)
        contradiction = labels.get("contradiction", 0)
        forward = _probabilities(scores[0])
        reverse = _probabilities(scores[1])
        forward_score = float(forward[entailment])
        reverse_score = float(reverse[entailment])
        contradicted = max(float(forward[contradiction]), float(reverse[contradiction])) >= 0.45
        return {
            "available": True,
            "passed": not contradicted and forward_score >= 0.50 and reverse_score >= 0.50,
            "forward": round(forward_score, 4),
            "reverse": round(reverse_score, 4),
            "model": MODEL_NAME,
        }
    except Exception as exc:  # deterministic checks remain active and visible
        return {
            "available": False,
            "passed": None,
            "reason": f"{type(exc).__name__}: {exc}",
            "model": MODEL_NAME,
        }
