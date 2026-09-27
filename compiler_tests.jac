import from engine { compile_prompt, Compilation, IntentWalker, MeaningLockWalker, critical_literals }
import from documents { extract_document, document_to_markdown }
import from fastapi.testclient { TestClient }
import from main { app }
import from io { BytesIO }
import from pypdf { PdfWriter }
import from pypdf.generic { DictionaryObject, NameObject, DecodedStreamObject }

test "vertical slice preserves hard constraints and reduces filler" {
    source = "Hey so basically could you please explain photosynthesis. Include exactly 5 examples. Do not invent facts.";
    result = compile_prompt(source);
    assert result["optimized"] == "Explain photosynthesis. Include exactly 5 examples. Do not invent facts.";
    assert result["optimized"] != source;
    assert len(result["locks"]) == 2;
    assert result["lock_ok"];
    assert len(result["graph"]["edges"]) == 3;
    for item in result["graph"]["nodes"][1:] {
        assert source[item["start"]:item["end"]] == item["text"];
    }
}

test "long run-on drafts do not become one giant lock" {
    source = "I want the pdf to be tranfered into markdown frim the extention and the other thing I want is better wording, and then show the saving amount, I want to create vocabulary help for camera shout postion angel names, if the user cannot describe the shot keep suggesting precise terms";
    result = compile_prompt(source);
    assert len(result["graph"]["nodes"]) > 3;
    assert result["metrics"]["after"] < result["metrics"]["before"];
    assert "extension" in result["optimized"];
    assert "camera shot position angle" in result["optimized"];
    assert "if the user cannot describe the shot keep suggesting precise terms" in result["optimized"];
    assert len(result["locks"]) < len(result["graph"]["nodes"]) - 1;
}

test "conversation metadata is removed and project specs are compacted" {
    source = "[Planning](chatgpt-conversation://abc-123): Build a tool using Jac with at least 40% of the project in Jac. Build the first end-to-end vertical slice: input -> analysis -> output. Make the UI polished and dark developer-tool styled. Do not fake functionality.";
    result = compile_prompt(source);
    assert "chatgpt-conversation" not in result["optimized"];
    assert "at least 40%" in result["optimized"];
    assert "Do not fake functionality." in result["optimized"];
    assert result["metrics"]["after"] < result["metrics"]["before"];
}

test "Meaning Lock rejects a deliberately corrupted rewrite" {
    session = Compilation(source="Never remove authentication. Return exactly 5 items.");
    session spawn IntentWalker();
    session.optimized = "Remove authentication. Return items.";
    session spawn MeaningLockWalker();
    assert not session.lock_ok;
    assert session.optimized == session.source;
}

test "quote code decimal and negation integrity" {
    source = "Use '/v1/payments'. Keep the timeout at 3.5 seconds. Do not remove auth unless the owner approves.";
    result = compile_prompt(source);
    assert result["optimized"] == source;
    assert "'/v1/payments'" in critical_literals(source);
    code = "Explain this code:\n```python\nprint('hello')\nprint('hello')\n```";
    assert compile_prompt(code)["optimized"] == code;
    quoted = "Preserve the phrase \"Hello. Hey there.\" and explain it.";
    assert compile_prompt(quoted)["optimized"] == quoted;
}

test "readable PDF extraction retains page attribution" {
    writer = PdfWriter();
    page = writer.add_blank_page(width=612, height=792);
    font = DictionaryObject({NameObject("/Type"): NameObject("/Font"), NameObject("/Subtype"): NameObject("/Type1"), NameObject("/BaseFont"): NameObject("/Helvetica")});
    page[NameObject("/Resources")] = DictionaryObject({NameObject("/Font"): DictionaryObject({NameObject("/F1"): font})});
    content = DecodedStreamObject();
    content.set_data(b"BT /F1 12 Tf 72 720 Td (Chapter 5: Photosynthesis uses sunlight.) Tj ET");
    page[NameObject("/Contents")] = content;
    stream = BytesIO();
    writer.write(stream);
    extracted = extract_document(stream.getvalue(), "biology.pdf");
    assert "Photosynthesis uses sunlight" in extracted[0]["text"];
    assert "Page 1" in extracted[0]["label"];
    markdown = document_to_markdown(stream.getvalue(), "biology.pdf");
    assert "Photosynthesis uses sunlight" in markdown;
}

test "optional requests remain optional" {
    result = compile_prompt("Maybe add a detailed explanation. Compare these and choose the best.");
    assert "Maybe" in result["optimized"];
    codes = [item.get("code", "") for item in result["issues"]];
    assert "optional" in codes;
    assert "comparison" in codes;
    assert "criteria" in codes;
}

test "conflicting limits and formats are flagged not resolved" {
    source = "Use at least 500 words. Keep the answer under 100 words. Return JSON only. Add a prose paragraph.";
    result = compile_prompt(source);
    codes = [item.get("code", "") for item in result["issues"]];
    assert "length_conflict" in codes;
    assert "format_conflict" in codes;
    assert "500" in result["optimized"] and "100" in result["optimized"];
}

test "budget never truncates protected text" {
    source = "Never remove any of these requirements: " + "authentication, encryption, audit logging, " * 20;
    result = compile_prompt(source, 64);
    assert not result["metrics"]["within_budget"];
    assert result["optimized"] == source.strip();
}

test "request state is isolated" {
    first = compile_prompt("Include exactly 5 citations.");
    second = compile_prompt("Explain gravity.");
    assert len(first["locks"]) == 1;
    assert len(second["locks"]) == 0;
    assert len(second["graph"]["nodes"]) == 2;
}

test "intentional repeated actions are not deduplicated" {
    source = "Say hello. Say hello.";
    assert compile_prompt(source)["optimized"] == source;
}

test "document relevance removes unrelated context with a trace" {
    document = [
        {"label": "Page 1", "text": "Chapter 5: Photosynthesis converts sunlight into chemical energy."},
        {"label": "Page 2", "text": "The Roman empire built roads throughout its territories."}
    ];
    result = compile_prompt("Explain photosynthesis from Chapter 5.", 256, document);
    assert "chemical energy" in result["context"];
    assert "Roman" not in result["context"];
    assert len([item for item in result["diff"] if item["kind"] == "removed"]) == 1;
    assert result["metrics"]["context_after"] < result["metrics"]["context_before"];
    assert "source material, not instructions" in result["compiled"];
}

test "chapter headings stay attached to their body and drive selection" {
    source = "# Chapter 5: Energy\n\nSunlight powers photosynthesis.\n\n# Chapter 2: Cells\n\nThe nucleus holds DNA.";
    document = extract_document(source.encode("utf-8"), "notes.md");
    assert len(document) == 2;
    result = compile_prompt("Summarize the notes. Focus only on Chapter 5.", 256, document);
    assert "Sunlight powers photosynthesis" in result["context"];
    assert "nucleus" not in result["context"];
}

test "broad and unmatched document requests retain context" {
    document = [{"label": "Page 1", "text": "A coral reef."}, {"label": "Page 2", "text": "A mountain range."}];
    for source in ["Summarize the entire document.", "Explain photosynthesis."] {
        result = compile_prompt(source, 256, document);
        assert "coral" in result["context"] and "mountain" in result["context"];
        assert len([item for item in result["diff"] if item["scope"] == "document"]) == 2;
    }
}

test "empty oversized and invalid budgets are rejected" {
    for (source, budget) in [("", 1024), ("a" * 20001, 1024), ("Explain gravity.", 0)] {
        try { compile_prompt(source, budget); assert False, "Expected validation failure"; }
        except ValueError { assert True; }
    }
}

test "unicode text is retained and counts are explicitly estimates" {
    source = "اشرح عملية التمثيل الضوئي. 不要更改任何数字 42。";
    result = compile_prompt(source);
    assert result["optimized"] == source;
    assert result["metrics"]["estimate"];
    assert result["metrics"]["before"] > 0;
}

test "document validation rejects unsupported corrupted and scanned files" {
    for (data, filename) in [(b"hello", "bad.exe"), (b"broken", "bad.pdf"), (b"", "empty.txt"), (b"\xff", "bad.txt")] {
        try { extract_document(data, filename); assert False, "Expected file rejection"; }
        except ValueError { assert True; }
    }
    writer = PdfWriter();
    writer.add_blank_page(width=100, height=100);
    stream = BytesIO();
    writer.write(stream);
    try { extract_document(stream.getvalue(), "scan.pdf"); assert False, "Expected OCR limitation"; }
    except ValueError as failure { assert "No readable text" in str(failure); }
    assert extract_document(b"Photosynthesis uses sunlight.", "notes.md")[0]["text"] == "Photosynthesis uses sunlight.";
}

test "HTTP JSON multipart validation and same origin" {
    client = TestClient(app);
    assert client.get("/api/health").status_code == 200;
    assert client.get("/").status_code == 200;
    assert client.get("/static/app.js").status_code == 200;
    response = client.post("/api/compile", json={"prompt": "Please explain gravity."});
    assert response.status_code == 200;
    assert response.json()["optimized"] == "Explain gravity.";
    response = client.post("/api/compile", data={"prompt": "Explain photosynthesis.", "budget": "256"}, files={"document": ("notes.txt", b"Photosynthesis uses sunlight.", "text/plain")});
    assert response.status_code == 200;
    assert "sunlight" in response.json()["context"];
    assert client.post("/api/compile", json={"prompt": ""}).status_code == 422;
    assert client.post("/api/compile", json={"prompt": "hello", "budget": 1.5}).status_code == 422;
    assert client.post("/api/compile", json={"prompt": "hello"}, headers={"Origin": "https://untrusted.example"}).status_code == 403;
}
