# PromptZero

## Tagline

**Write less. Get more.** A Jac-powered context compiler that turns messy ideas into clearer, token-efficient AI prompts.

## Inspiration

AI is powerful, but communicating with it is still surprisingly inefficient. People repeat themselves, use vague wording, forget important constraints, and attach documents in formats that are difficult to reuse. Creative users face another problem: they may know exactly how a video should look without knowing terms such as *dolly-in*, *low-angle shot*, or *shallow depth of field*.

We wanted to build a layer between the user and the AI—not another chatbot. That layer should improve the request before it reaches a model, preserve the requirements that matter, expose every transformation, and avoid wasting tokens.

That became PromptZero: a context compiler for AI.

## What it does

PromptZero accepts a prompt through its web interface or Safari extension and runs it through a graph-based Jac pipeline.

It can:

- Remove greetings, repetition, speech-to-text fragments, and unnecessary wording.
- Clarify supported vague phrases without silently inventing requirements.
- Estimate tokens before and after optimization.
- Detect possible ambiguity and conflicting requirements.
- Extract prompt clauses into an inspectable intent and constraint graph.
- Protect detected numbers, exact values, and negative requirements through Meaning Lock.
- Show a Context Diff of preserved, compressed, and removed content.
- Display the Jac walkers that executed.
- Translate supported informal camera descriptions into filmmaking vocabulary.
- Convert complete text-based PDFs to Markdown locally using Microsoft MarkItDown.
- Download the converted document as a `.md` file named after the original PDF.

The Safari extension operates on the current unsent ChatGPT draft. Users can review, apply, copy, or undo an optimization. PromptZero never submits the message automatically.

## Example

Input:

```text
Make the camera slowly get closer to his face.
```

Output:

```text
Use a slow dolly-in toward his face.
```

For a constraint-heavy prompt such as:

```text
Hey so basically could you please explain photosynthesis. Include exactly 5 examples. Do not invent facts.
```

PromptZero removes the filler while protecting `exactly 5 examples` and `Do not invent facts`.

## How we built it

PromptZero’s core analysis is implemented in Jac. The compiler connects the request to intent nodes and processes the graph through six real walkers:

1. **IntentWalker** segments and classifies prompt clauses.
2. **AmbiguityWalker** identifies ambiguity and conflicts without guessing the answer.
3. **CompressionWalker** performs conservative wording transformations.
4. **MeaningLockWalker** checks protected literals and negation and restores unsafe clauses.
5. **BudgetWalker** calculates model-agnostic token estimates and budget status.
6. **GraphWalker** serializes the intent graph, source offsets, and Context Diff.

Additional Jac modules provide the FastAPI application, document pipeline, and extension API boundary. The web client renders the optimized prompt, metrics, graph, diff, and trace. The Safari extension connects only to the local PromptZero server.

The principal executable source is approximately 71% Jac: 946 lines of Jac compared with 382 lines of browser JavaScript, excluding tests, generated Xcode wrapper code, markup, styling, and assets.

For PDFs, PromptZero performs bounded local extraction and uses Microsoft MarkItDown for complete PDF-to-Markdown conversion. The PDF workflow is intentionally separate from prompt optimization: it does not summarize, rank, or discard document sections.

## Challenges we ran into

### Preserving meaning while shortening text

Removing words is easy; knowing which words must survive is harder. Early versions either preserved too much or risked removing constraints. We changed the pipeline so intent is segmented first, constraints are detected at the clause level, and failed Meaning Lock checks restore only the affected clause.

### Handling speech-like prompts

Real prompts are often dictated, unpunctuated, repetitive, and full of corrections. We added conservative segmentation and tested the system with long run-on prompts and stuttered speech instead of relying only on clean examples.

### Connecting a Safari extension to a local compiler

Safari required a packaged Xcode project, website permissions, Safari-compatible sender handling, and explicit CORS preflight support. Both wording repair and document conversion now use narrow, validated local endpoints.

### Keeping the PDF workflow honest

Token reduction is not guaranteed when converting a PDF to Markdown because Markdown adds structure. We therefore show before-and-after values as estimates and make the workflow’s real purpose explicit: complete, reusable Markdown—not fake compression.

## Accomplishments that we are proud of

- Built a complete prompt-to-Jac-to-graph-to-optimized-output vertical slice.
- Implemented meaningful Jac walkers rather than using Jac as a thin wrapper.
- Exceeded the 40% Jac requirement with approximately 71% Jac in the principal executable source.
- Made every prompt transformation inspectable through a graph, diff, and walker trace.
- Added a working local Safari extension that never auto-sends a message.
- Added complete PDF-to-Markdown conversion and real `.md` downloads.
- Connected camera vocabulary assistance to both the web app and extension.
- Created automated coverage for the compiler, Meaning Lock, document conversion, HTTP boundaries, Safari origins, and CORS preflight behavior.
- Kept the compilation path local and free of external model calls.

## What we learned

We learned that prompt optimization is closer to compilation than summarization. A useful system needs stages, intermediate representations, protected invariants, and traceable transformations.

Jac’s graph and walker model was a natural fit because each stage could operate on connected intent nodes instead of passing around an opaque block of text. We also learned that transparency matters: users are more likely to trust an optimization when they can see exactly what changed and why.

Finally, browser integration is part of the product—not an afterthought. A strong backend is not enough if the extension cannot reliably locate the current editor, respect stale drafts, and communicate safely with a local service.

## What’s next for PromptZero

- Expand the camera vocabulary catalog and add more tested phrase-to-term mappings.
- Add optional OCR for scanned PDFs.
- Build a larger evaluation dataset for meaning preservation and rewrite usefulness.
- Support optional model-specific tokenizers while keeping the current transparent estimate.
- Add more writing domains, such as photography, audio production, design, and software architecture.
- Complete production validation and deployment through JacHammer.

## Built with

- Jac
- Jac graph walkers
- Python
- FastAPI
- Uvicorn
- Microsoft MarkItDown
- pypdf
- HTML
- CSS
- JavaScript
- Safari Web Extensions
- Xcode

## Local setup

Start PromptZero with:

```bash
cd "/Users/shamsan/Documents/Codex/2026-09-27/i-x20/work/jachacks-project-fall-2026"
./run.sh
```

Then open:

```text
http://127.0.0.1:8000
```

For Safari, open the included Xcode project, run the macOS scheme, enable PromptZero under Safari Extensions, and allow access to `chatgpt.com`.

## Links

- **Source code:** https://github.com/ashamsan21/JACHACKS-PROJECT-FALL-2026
- **Demo video:** Add the final public video link before submission.

## Short project description

PromptZero is a local-first, Jac-powered context compiler that cleans messy AI prompts, protects critical requirements, estimates token savings, visualizes intent, suggests precise camera vocabulary, and converts PDFs to downloadable Markdown through a Safari extension and dark developer-tool interface.

## One-sentence pitch

PromptZero compiles human intent into clearer, smaller, inspectable AI context before the prompt reaches the model.

