"""Versioned extension boundary. Draft review and replacement eligibility stay in Jac."""
import re;
import hashlib;
import from engine { compile_prompt }

"""Offer precise domain words only when the draft signals a relevant topic."""
def vocabulary_suggestions(prompt: str) -> list[dict[str, str]] {
    text = prompt.lower();
    video = bool(re.search(r"\b(camera|video|film|shot|scene|angle|lens|cinematic)\b", text));
    vague = bool(re.search(r"\b(something|somehow|nice|good|better|position|move|angle|like this|kind of)\b", text));
    if not video or not vague { return []; }
    return [
        {"term": "low-angle shot", "meaning": "camera looks upward, making the subject feel powerful", "insert": "Use a low-angle shot to make the subject feel powerful."},
        {"term": "over-the-shoulder", "meaning": "frames the scene from behind one subject", "insert": "Frame it as an over-the-shoulder shot."},
        {"term": "dolly-in", "meaning": "camera physically moves toward the subject", "insert": "Use a slow dolly-in toward the subject."},
        {"term": "tracking shot", "meaning": "camera follows a moving subject", "insert": "Use a smooth tracking shot that follows the subject."},
        {"term": "bird's-eye view", "meaning": "camera looks straight down from above", "insert": "Show the scene from a bird's-eye view."},
        {"term": "shallow depth of field", "meaning": "subject sharp, background blurred", "insert": "Use a shallow depth of field with a softly blurred background."}
    ];
}

def extension_origin(origin: str) -> bool {
    # Chromium uses a fixed 32-character ID. Safari uses a bundle-derived ID.
    return bool(re.fullmatch(r"chrome-extension://[a-p]{32}", origin)) or bool(re.fullmatch(r"safari-web-extension://[A-Za-z0-9._-]{3,200}", origin));
}

def extension_request_allowed(origin: str, path: str, client: str) -> bool {
    # This grants only the stateless review route, never general cross-origin API access.
    return extension_origin(origin) and path in ["/api/extension/review", "/api/extension/document"] and client == "extension-v1";
}

def validate_review_request(body: any) -> tuple[str, int] {
    if not isinstance(body, dict) {
        raise ValueError("Expected a JSON object containing a draft.");
    }
    if set(body.keys()) - {"prompt", "budget", "protocol"} {
        raise ValueError("Unexpected fields. Only the current prompt, budget, and protocol are accepted.");
    }
    protocol = body.get("protocol");
    if isinstance(protocol, bool) or protocol != 1 {
        raise ValueError("Unsupported extension protocol. Update the backend and extension together.");
    }
    prompt = body.get("prompt");
    if not isinstance(prompt, str) {
        raise ValueError("The draft must be plain text.");
    }
    if not prompt.strip() {
        raise ValueError("Write a prompt in ChatGPT before analyzing it.");
    }
    if len(prompt) > 20000 {
        raise ValueError("Drafts must contain no more than 20,000 characters.");
    }
    budget = body.get("budget", 1024);
    if isinstance(budget, bool) or not isinstance(budget, int) {
        raise ValueError("Token target must be a whole number.");
    }
    if budget < 64 or budget > 32000 {
        raise ValueError("Token target must be between 64 and 32,000.");
    }
    return (prompt, budget);
}

def audit_replacement(result: dict[str, any]) -> tuple[bool, str] {
    # Recheck the serialized boundary; an extension must not apply a failed or incomplete review.
    original = str(result["original"]);
    optimized = str(result["optimized"]);
    if not optimized.strip() {
        return (False, "The compiler returned an empty draft. Keep your original.");
    }
    if not result["lock_ok"] {
        return (False, "Meaning Lock restored the original. Review the flagged requirements.");
    }
    for lock in result["locks"] {
        if not lock["passed"] or str(lock["text"]) not in optimized {
            return (False, "A protected clause did not survive verification. Keep the original draft.");
        }
    }
    # Ensure the diff is grounded in this specific request, not a stale response.
    for item in result["graph"]["nodes"] {
        if item["kind"] == "request" { continue; }
        start = int(item["start"]);
        end = int(item["end"]);
        if start < 0 or end > len(original) or start >= end {
            return (False, "Source positions could not be verified. Keep your original.");
        }
        if original[start:end] != str(item["text"]) {
            return (False, "The review does not match the source draft. Analyze again.");
        }
    }
    if optimized == original {
        return (False, "No conservative shortening was found. Your draft is already retained as written.");
    }
    return (True, "Review the proposed changes before replacing your draft.");
}

def lock_summary(result: dict[str, any]) -> str {
    locks: list[dict[str, any]] = result["locks"] as list[dict[str, any]];
    if not locks {
        return "Meaning Lock: no explicit constraints detected.";
    }
    passed = len([lock for lock in locks if lock["passed"]]);
    return "Meaning Lock: " + str(passed) + "/" + str(len(locks)) + " detected clauses retained verbatim.";
}

def review_draft(body: any) -> dict[str, any] {
    (prompt, budget) = validate_review_request(body);
    result = compile_prompt(prompt, budget);
    (can_apply, reason) = audit_replacement(result);
    # No graph IDs, history, files, or mutable session handles cross the browser boundary.
    # SHA-256 identifies this review; it is not an authentication credential.
    digest = hashlib.sha256(str(result["original"]).encode("utf-8")).hexdigest();
    return {
        "protocol": 1,
        "source_sha256": digest,
        "original": result["original"],
        "optimized": result["optimized"],
        "can_apply": can_apply,
        "apply_reason": reason,
        "lock_summary": lock_summary(result),
        "locks": result["locks"],
        "issues": result["issues"],
        "diff": result["diff"],
        "metrics": result["metrics"],
        "vocabulary": vocabulary_suggestions(prompt),
        "trace": result["trace"],
        "duration_ms": result["duration_ms"],
        "engine": result["engine"],
        "scope": "current draft only; excludes conversation history and attachments"
    };
}
