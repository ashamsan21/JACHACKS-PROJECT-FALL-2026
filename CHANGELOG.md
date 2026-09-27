# Changelog

## 0.5.0 — 2026-09-27

### Changed

- PDF upload now performs one job only: convert the complete file to Markdown
- PDF results show estimated tokens before and after conversion in both the app and extension
- PDF conversion creates a downloadable `.md` file named after the source document
- Prompt cleanup uses lightweight Jac rules without a language model or per-clause inference
- PDF conversion no longer selects excerpts, interprets the prompt, or removes document sections

### Removed

- Sentence Transformers, ONNX semantic inference, and DeepEval dependencies
- The document relevance-selection walker and its unused context-ranking code

## 0.4.0 — 2026-09-27

### Added

- Local Sentence Transformers NLI verification for Meaning Lock
- Bidirectional entailment and contradiction checks for rewritten requirements
- ARM-optimized ONNX inference with no external model API calls
- DeepEval development dependency for future prompt-alignment evaluation
- Regression coverage for the long presentation prompt that previously saved zero tokens

### Changed

- Long unpunctuated prompts are split into atomic intent nodes before constraints are locked
- Meaning Lock protects exact literals and negation without freezing an entire paragraph
- Failed semantic rewrites restore only the affected clause
- The interface reports local semantic checks separately from external model calls
- PromptZero now uses a hybrid Jac rules and local NLI compiler
- Speech-to-text drafts now remove stutters, correction fragments, repeated filler, and common grammar errors
- Vague audience-question requests are reconstructed into concise voice and engagement requirements

## 0.3.0 — 2026-09-27

### Added

- Safari Web Extension compatibility and local installation instructions
- Validation for Safari extension origins at the local API boundary
- Microsoft MarkItDown 0.1.8 as the local PDF-to-Markdown engine
- PDF-to-Markdown conversion in the browser extension
- Copy Markdown and Add to draft actions
- Estimated token-savings indicator and extension badge
- Contextual vocabulary suggestions for camera and AI-video prompts
- Click-to-add vocabulary suggestions

### Changed

- Renamed the extension action from Analyze draft to Fix wording
- Simplified the public README
- Updated public-facing product labeling
- Expanded the extension’s local API contract for document conversion
- Improved long run-on prompt segmentation so one conditional phrase no longer locks the entire draft
- Added conservative corrections for common spelling mistakes and camera terminology
- Meaning Lock now distinguishes conditional wording from hard verbatim requirements
- Conversation-reference metadata is removed before optimization
- Common project-specification wording is compacted without changing hard requirements
- Removed the token-estimate disclaimer and generic reference ambiguity message from the interface

### Removed

- Internal code-share measurement document
- One-time validation report
- Workspace-specific setup notes and detailed internal implementation commentary from the README
- Generated Jac cache and macOS metadata from the project folder
- All prewritten prompts and the example selector from the web interface
- The bundled biology-notes example document
- The sample prompt from the extension documentation
- The visible Token Target control; document selection now uses an automatic internal budget
- The optional native Jac service entry point
- The raw OpenAPI link from the product header
- Generated Jac session state from the project folder

### Safety

- The extension still never submits a message automatically
- Draft and document processing remain local
- File size and document type validation remain enforced
- MarkItDown plugins, Azure services, and external AI integrations are disabled
- The existing bounded extractor remains as a fallback for empty or failed conversions
