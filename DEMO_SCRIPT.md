# PromptZero Hackathon Demo Script

## Before presenting

1. Start the local server:

   ```bash
   cd "/Users/shamsan/Documents/Codex/2026-09-27/i-x20/work/jachacks-project-fall-2026"
   ./run.sh
   ```

2. Open `http://127.0.0.1:8000`.
3. In Xcode, run the PromptZero macOS scheme.
4. In Safari, confirm PromptZero is enabled and allowed on `chatgpt.com`.
5. Keep one small, text-based PDF ready. Scanned PDFs require OCR and are not supported in this MVP.

## Five-minute presentation

### 0:00–0:30 — Problem and promise

Say:

> AI users waste tokens because their prompts are often repetitive, vague, or poorly worded. They may also know the visual result they want without knowing professional terms such as “dolly-in” or “low-angle shot.” PromptZero is a Jac-powered context compiler that improves the request before it reaches the AI. The promise is: Write less. Get more.

### 0:30–1:40 — Prompt cleanup and Meaning Lock

Paste:

```text
Hey so basically could you please explain photosynthesis. Include exactly 5 examples. Do not invent facts.
```

Click **Clean prompt**.

Say:

> PromptZero removes filler, produces a shorter instruction, and estimates the token difference. It does not call an external AI model. Jac walkers classify the intent, detect ambiguity, compress the wording, protect critical requirements, calculate the budget, and build the graph.

Point out:

- The before-and-after estimated token counts.
- `exactly 5 examples` and `Do not invent facts` remain protected.
- The Intent Graph exposes the request structure.
- Context Diff shows what was preserved, compressed, or removed.
- Walker Trace proves which Jac walkers executed.

### 1:40–2:30 — Camera Vocabulary Assistant

Clear the input and paste:

```text
Make the camera slowly get closer to his face.
```

Click **Clean prompt**.

Say:

> A video creator may understand the desired motion but not know the filmmaking term. PromptZero converts this into “Use a slow dolly-in toward his face.” It also suggests related vocabulary and explains the difference between physically moving the camera and zooming the lens.

Expected output:

```text
Use a slow dolly-in toward his face.
```

### 2:30–3:25 — PDF to Markdown

Click **Convert document**, select the prepared PDF, and click **Convert to Markdown**.

Say:

> The PDF workflow intentionally performs one clear job. Microsoft MarkItDown converts the complete text-based PDF to Markdown locally. PromptZero does not summarize it, select excerpts, or send it to an external service.

Point out:

- Estimated PDF-text tokens before conversion.
- Estimated Markdown tokens after conversion.
- The complete Markdown preview.
- **Download .md**, which creates a Markdown file named after the PDF.

### 3:25–4:20 — Safari extension

Open ChatGPT in Safari and type—but do not send:

```text
Could you please make the camera slowly get closer to the actor and make the background kind of blurry.
```

Open PromptZero and click **Fix wording**.

Say:

> The extension reviews only the current unsent draft. It shows token savings, an optimized version, Meaning Lock results, vocabulary suggestions, and a Context Diff. It never presses Send. The user remains in control and can apply, copy, or undo the replacement.

Demonstrate **Use optimized**, then **Undo replacement**.

### 4:20–5:00 — Architecture and close

Say:

> The core is implemented in Jac. IntentWalker, AmbiguityWalker, CompressionWalker, MeaningLockWalker, BudgetWalker, and GraphWalker are responsible for real stages of the compilation. FastAPI is only the local transport layer, and the browser code presents the results. The application is local-first, makes zero external model calls, and includes automated tests for the compiler, PDF workflow, extension boundary, Safari CORS, and Meaning Lock.

Finish with:

> PromptZero is not another chatbot. It is the layer that helps people communicate with AI more clearly, with less wasted context: Write less. Get more.

## Backup plan

- If Safari permissions interrupt the extension demo, demonstrate the same prompt in the web app and show the tested extension source and Safari Xcode project.
- If a PDF is scanned, use the prepared text-based PDF.
- If port 8000 is busy, stop the older server with `Control+C`, then run `./run.sh` again.

