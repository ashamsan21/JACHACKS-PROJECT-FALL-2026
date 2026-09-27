"""Same-origin HTTP adapter; compiler logic stays in the graph walkers."""
import os;
import asyncio;
import uvicorn;
import from pathlib { Path }
import from fastapi { FastAPI, Request, HTTPException }
import from fastapi.responses { FileResponse, JSONResponse }
import from fastapi.staticfiles { StaticFiles }
import from engine { compile_prompt, compile_document_markdown }
import from documents { extract_document, document_to_markdown }
import from extension_api { extension_request_allowed, review_draft, vocabulary_suggestions }

glob app = FastAPI(title="PromptZero", version="0.1.0", docs_url=None, redoc_url=None);
glob static_dir = Path(str(__file__)).parent / "static";

@app.middleware("http")
async def protect(request: Request, call_next: any) -> any {
    size = request.headers.get("content-length", "0");
    if not size.isdigit() or int(size) > 4200000 {
        return JSONResponse({"detail": "Request exceeds the 4 MB file limit."}, status_code=413);
    }
    # Browser requests are same-origin; no permissive CORS or prompt persistence.
    origin = request.headers.get("origin");
    extension_cors = bool(origin) and extension_request_allowed(origin or "", request.url.path, "extension-v1");
    if request.method == "OPTIONS" and extension_cors {
        return JSONResponse(
            {}, status_code=200,
            headers={
                "Access-Control-Allow-Origin": origin or "",
                "Access-Control-Allow-Methods": "POST, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type, X-PromptZero-Client",
                "Access-Control-Max-Age": "600",
                "Vary": "Origin"
            }
        );
    }
    if request.method == "POST" and origin and origin.rstrip("/") != str(request.base_url).rstrip("/") {
        if not extension_request_allowed(origin, request.url.path, request.headers.get("x-promptzero-client", "")) {
            return JSONResponse({"detail": "Cross-origin requests are not permitted."}, status_code=403);
        }
    }
    response = await call_next(request);
    response.headers["X-Content-Type-Options"] = "nosniff";
    response.headers["Referrer-Policy"] = "no-referrer";
    response.headers["Content-Security-Policy"] = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'";
    response.headers["Cache-Control"] = "no-store";
    if extension_cors {
        response.headers["Access-Control-Allow-Origin"] = origin or "";
        response.headers["Vary"] = "Origin";
    }
    return response;
}

@app.get("/api/health")
def health() -> dict {
    return {"status": "ok", "engine": "Jac", "version": "0.1.0"};
}

@app.post("/api/compile")
async def compile_api(request: Request) -> dict {
    try {
        if "application/json" in request.headers.get("content-type", "") {
            body = await request.json();
            if not isinstance(body, dict) { raise ValueError("Expected a JSON object."); }
            prompt = body.get("prompt", "");
            budget = body.get("budget", 1024);
        } else {
            form = await request.form(max_files=1, max_fields=3, max_part_size=4200000);
            prompt = form.get("prompt", "");
            budget = form.get("budget", 1024);
            upload = form.get("document");
            if upload and hasattr(upload, "read") {
                data = await upload.read(4000001);
                filename = upload.filename or "document.pdf";
                chunks = await asyncio.to_thread(extract_document, data, filename);
                markdown = await asyncio.to_thread(document_to_markdown, data, filename, chunks);
                await upload.close();
                plain_text = "\n\n".join([str(chunk["text"]) for chunk in chunks]);
                return compile_document_markdown(plain_text, markdown, filename);
            }
        }
        if not isinstance(prompt, str) { raise ValueError("Prompt must be text."); }
        if isinstance(budget, bool) or not re_integer(str(budget)) { raise ValueError("Token target must be a whole number."); }
        result = await asyncio.to_thread(compile_prompt, prompt, int(budget));
        result["vocabulary"] = vocabulary_suggestions(prompt);
        return result;
    } except ValueError as error {
        raise HTTPException(status_code=422, detail=str(error));
    } except HTTPException { raise; }
    except Exception {
        # No stack trace or uploaded text is exposed to the browser.
        raise HTTPException(status_code=500, detail="Compilation failed. Please try again with a smaller prompt or document.");
    }
}

def re_integer(value: str) -> bool {
    return value.isdigit();
}

@app.post("/api/extension/review")
async def extension_review(request: Request) -> dict {
    if request.headers.get("x-promptzero-client") != "extension-v1" {
        raise HTTPException(status_code=403, detail="Use the PromptZero extension to review a draft.");
    }
    if "application/json" not in request.headers.get("content-type", "") {
        raise HTTPException(status_code=415, detail="The review endpoint accepts JSON only.");
    }
    try {
        body = await request.json();
        return await asyncio.to_thread(review_draft, body);
    } except ValueError as failure {
        raise HTTPException(status_code=422, detail=str(failure));
    }
}

@app.post("/api/extension/document")
async def extension_document(request: Request) -> dict {
    if request.headers.get("x-promptzero-client") != "extension-v1" { raise HTTPException(status_code=403, detail="Use the PromptZero extension to convert a document."); }
    try {
        form = await request.form(max_files=1, max_fields=0, max_part_size=4200000);
        upload = form.get("document");
        if not upload or not hasattr(upload, "read") { raise ValueError("Choose a PDF, TXT, or Markdown file."); }
        data = await upload.read(4000001);
        filename = upload.filename or "document.pdf";
        chunks = await asyncio.to_thread(extract_document, data, filename);
        markdown = await asyncio.to_thread(document_to_markdown, data, filename, chunks);
        await upload.close();
        plain_text = "\n\n".join([str(chunk["text"]) for chunk in chunks]);
        result = compile_document_markdown(plain_text, markdown, filename);
        return {"protocol": 1, "filename": result["filename"], "markdown": markdown, "metrics": result["metrics"]};
    } except ValueError as failure { raise HTTPException(status_code=422, detail=str(failure)); }
}

@app.get("/")
def index() -> any {
    return FileResponse(static_dir / "index.html");
}

with entry {
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static"); # jac:ignore[E1053] -- Starlette ASGI callable protocol; covered by HTTP tests.
}

with entry:__main__ {
    uvicorn.run(app, host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "8000")));
}
