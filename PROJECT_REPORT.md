# PromptZero Project Report

## Executive summary

PromptZero is a local-first context compiler for AI prompts. It cleans repetitive or unclear wording, estimates before-and-after token usage, identifies ambiguity, extracts inspectable intent, protects critical requirements, and exposes every change through an intent graph and Context Diff. It also converts complete text-based PDFs to downloadable Markdown and provides filmmaking vocabulary for users creating AI video prompts.

The project prioritizes a working end-to-end demonstration over broad but incomplete functionality. No external language model is called during compilation.

## Problem

People often communicate with AI using speech-like, repetitive, or ambiguous text. This creates three problems:

1. Unnecessary context increases token usage.
2. Vague wording reduces output quality.
3. Users may know the result they want without knowing the precise professional vocabulary needed to describe it.

Documents create a related problem: useful PDF content is difficult to reuse as structured prompt context. PromptZero addresses this with a separate whole-document PDF-to-Markdown workflow.

## Implemented solution

### Prompt compiler

The user enters a prompt in the web application or reviews an unsent ChatGPT draft through the Safari extension. PromptZero returns:

- A clearer, shorter prompt when a safe deterministic rewrite is available.
- Model-agnostic before-and-after token estimates.
- Ambiguity and verbosity observations.
- An inspectable intent and constraint graph.
- A Context Diff marking content as preserved, compressed, or removed.
- A walker trace showing the Jac execution stages.

### Meaning Lock

Meaning Lock protects detected hard requirements using lightweight deterministic checks. It preserves critical literals such as numbers and exact values and checks that negative requirements do not lose their negation. If a protected clause fails these checks, the original clause is restored.

This MVP deliberately does not claim complete semantic equivalence. It provides transparent, testable protection without an expensive external model call.

### Camera Vocabulary Assistant

PromptZero recognizes selected informal camera descriptions and replaces them with precise filmmaking terminology. For example:

```text
Make the camera slowly get closer to his face.
```

becomes:

```text
Use a slow dolly-in toward his face.
```

The interface can also present related terms with short explanations, such as the difference between a dolly-in and a zoom-in.

### PDF-to-Markdown workflow

PDF conversion is intentionally independent from prompt compilation:

1. The complete text-based PDF is extracted locally.
2. Microsoft MarkItDown converts it to Markdown.
3. PromptZero displays estimated tokens before and after conversion.
4. The user can copy the Markdown or download a `.md` file named after the source PDF.

The workflow does not summarize, rank, select, or remove PDF sections. Scanned PDFs require OCR and are outside the MVP scope.

### Safari extension

The Safari Web Extension operates on the current unsent ChatGPT draft. It supports:

- Fix wording.
- Token savings display.
- Meaning Lock status.
- Context Diff.
- Camera vocabulary suggestions.
- Apply optimized wording.
- Copy optimized wording.
- Undo replacement.
- PDF-to-Markdown conversion, copying, insertion, and download.

The extension never sends the ChatGPT message automatically. It connects only to the local PromptZero server at `127.0.0.1:8000`.

## Jac architecture

The core pipeline is implemented through real Jac walkers:

- **IntentWalker** segments the source and creates connected intent nodes.
- **AmbiguityWalker** flags possible ambiguity without inventing missing intent.
- **CompressionWalker** applies conservative wording and domain-specific transformations.
- **MeaningLockWalker** checks protected literals and negation and restores unsafe clauses.
- **BudgetWalker** calculates token estimates and budget status.
- **GraphWalker** serializes the traversed graph and Context Diff.

Supporting Jac modules handle the HTTP application, document extraction and conversion, and extension API boundary.

### Jac code share

The principal executable source contains approximately:

- 946 lines of Jac across `engine.jac`, `main.jac`, `documents.jac`, and `extension_api.jac`.
- 382 lines of browser JavaScript across the main interface and extension.

Using those principal application sources, Jac represents approximately **71%** of the implementation. Tests, generated Xcode wrapper files, images, styles, and markup are excluded from this calculation. This exceeds the requirement that at least 40% of the project code be meaningfully implemented in Jac.

## Data flow

### Text

```text
Prompt or unsent draft
        ↓
IntentWalker → AmbiguityWalker → CompressionWalker
        ↓
MeaningLockWalker → BudgetWalker → GraphWalker
        ↓
Optimized text + estimates + graph + diff + trace
```

### PDF

```text
Text-based PDF
      ↓
Bounded local extraction
      ↓
Microsoft MarkItDown
      ↓
Markdown preview + token estimates + downloadable .md
```

## Technology

- Jac and Jac graph walkers for core analysis.
- FastAPI and Uvicorn for the local HTTP boundary.
- Microsoft MarkItDown and pypdf for document conversion and extraction.
- HTML, CSS, and JavaScript for the web interface.
- Safari Web Extension packaged through Xcode.

## Privacy and safety

- Prompt and document processing runs locally.
- No external language-model API is used.
- Uploaded content is not persisted by the server.
- Cross-origin access is restricted to the extension’s review and document routes.
- Safari preflight requests are explicitly validated.
- Extension replacements require user action and are never automatically submitted.
- File type, size, prompt length, and request structure are validated.

## Verification

The automated suites cover:

- Prompt cleanup and token reduction.
- Hard constraints, literals, numbers, and negation.
- Long run-on and speech-to-text prompts.
- Camera terminology conversion.
- Intent graph and diff source grounding.
- PDF extraction and complete Markdown conversion.
- Download filename generation.
- Invalid, encrypted, unsupported, and scanned-file behavior.
- Web and extension HTTP boundaries.
- Safari origins and CORS preflight handling.
- Extension replacement gating and stale-draft protection.

At the time of this report, 25 Jac application and extension tests pass.

## Requirement coverage

| Original requirement | Status |
|---|---|
| Jac as core language | Implemented |
| At least 40% meaningful Jac | Implemented; approximately 71% of principal executable source |
| Prompt input to Jac analysis | Implemented |
| Intent and constraint graph | Implemented |
| Optimized prompt | Implemented |
| Before-and-after token comparison | Implemented as clearly marked estimates |
| Meaning Lock | Implemented with deterministic literal and negation protection |
| Context Diff | Implemented |
| Dark developer-tool interface | Implemented |
| Document/PDF optimization | Implemented as complete PDF-to-Markdown conversion |
| Browser extension | Implemented and packaged for Safari |
| Camera vocabulary assistance | Implemented for supported descriptions with suggestions |
| JacHammer readiness | Local ASGI service and Docker structure are present; production deployment still requires environment-specific validation |

## Current limitations

- Token values are model-agnostic estimates, not billing counts from a specific tokenizer.
- The rule-based compiler cannot safely rewrite every possible sentence.
- Camera vocabulary coverage is curated and should be expanded with more tested phrase mappings.
- Scanned PDFs require OCR.
- Safari may require the user to allow website access and rebuild the extension after source updates.
- JacHammer production deployment has not been completed as part of the local MVP.

## Future work

1. Expand the camera vocabulary catalog and intent-to-term mappings.
2. Add optional OCR for scanned documents.
3. Add evaluation datasets for meaning preservation and rewrite usefulness.
4. Add model-specific tokenizer plugins while retaining the current transparent estimate.
5. Complete and validate JacHammer deployment.

## Conclusion

PromptZero demonstrates a practical context-compilation layer between users and AI. Its main contribution is not simply shortening text; it makes prompt transformation visible and inspectable while protecting explicit requirements. The Jac walker architecture provides a strong fit for this staged, graph-oriented workflow, and the web application plus Safari extension make the concept immediately demonstrable.

