import from extension_api { review_draft, audit_replacement, extension_request_allowed, vocabulary_suggestions }
import from engine { compile_prompt }
import from main { app }
import from fastapi.testclient { TestClient }

test "extension review uses real walkers and gates replacement" {
    result = review_draft({"protocol": 1, "prompt": "Could you please explain gravity. Include exactly 3 examples.", "budget": 1024});
    assert result["can_apply"];
    assert result["optimized"] == "Explain gravity. Include exactly 3 examples.";
    assert len(result["source_sha256"]) == 64;
    assert len(result["trace"]) >= 5;
    assert result["metrics"]["estimate"];
    assert not review_draft({"protocol": 1, "prompt": "Never remove authentication."})["can_apply"];
}

test "extension audit rejects corrupted protections and stale offsets" {
    result = compile_prompt("Please explain gravity. Include exactly 3 examples.");
    result["optimized"] = "Explain gravity.";
    assert not audit_replacement(result)[0];
    result = compile_prompt("Please explain gravity.");
    result["graph"]["nodes"][1]["text"] = "Unrelated source";
    assert not audit_replacement(result)[0];
}

test "extension accepts only a bounded current draft" {
    invalid = [
        {"protocol": 2, "prompt": "hello"},
        {"protocol": True, "prompt": "hello"},
        {"protocol": 1, "prompt": ""},
        {"protocol": 1, "prompt": "x" * 20001},
        {"protocol": 1, "prompt": "hello", "budget": True},
        {"protocol": 1, "prompt": "hello", "history": []},
        {"protocol": 1, "prompt": "hello", "budget": 1}
    ];
    for body in invalid {
        try { review_draft(body); assert False, "Invalid contract should fail"; }
        except ValueError { assert True; }
    }
}

test "extension origin exception is narrow" {
    origin = "chrome-extension://" + "a" * 32;
    assert extension_request_allowed(origin, "/api/extension/review", "extension-v1");
    assert not extension_request_allowed(origin, "/api/compile", "extension-v1");
    assert extension_request_allowed(origin, "/api/extension/document", "extension-v1");
    assert not extension_request_allowed("https://chatgpt.com", "/api/extension/review", "extension-v1");
    assert not extension_request_allowed(origin + ".evil.test", "/api/extension/review", "extension-v1");
    assert not extension_request_allowed(origin, "/api/extension/review", "");
    assert extension_request_allowed("safari-web-extension://com.promptzero.local", "/api/extension/review", "extension-v1");
    assert not extension_request_allowed("safari-web-extension://", "/api/extension/review", "extension-v1");
    assert not extension_request_allowed("safari-web-extension://com.promptzero.local/evil", "/api/extension/review", "extension-v1");
}

test "camera vocabulary is contextual and actionable" {
    items = vocabulary_suggestions("Make a video with a good camera angle and move toward the actor.");
    assert len(items) >= 5;
    assert "dolly-in" in [item["term"] for item in items];
    assert not vocabulary_suggestions("Explain gravity in three paragraphs.");
}

test "extension HTTP boundary preserves web origin rejection" {
    client = TestClient(app);
    headers = {"Origin": "chrome-extension://" + "a" * 32, "X-PromptZero-Client": "extension-v1"};
    body = {"protocol": 1, "prompt": "Please explain gravity."};
    response = client.post("/api/extension/review", headers=headers, json=body);
    assert response.status_code == 200;
    assert response.json()["can_apply"];
    assert client.post("/api/extension/review", json=body).status_code == 403;
    assert client.post("/api/compile", headers=headers, json=body).status_code == 403;
    headers["Origin"] = "https://chatgpt.com";
    assert client.post("/api/extension/review", headers=headers, json=body).status_code == 403;
}
