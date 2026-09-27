# Changelog

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
