"""Bounded document extraction and whole-document Markdown conversion."""
import re;
import from io { BytesIO }
import from pypdf { PdfReader }
import from markitdown { MarkItDown }

def chunk_text(text: str, label: str) -> list[dict[str, str]] {
    chunks = [];
    pending_heading = "";
    section = "";
    chapter = "";
    # Keep complete paragraphs wherever possible; fixed slices bound long ones.
    for paragraph in re.split(r"\n\s*\n", text.strip()) {
        paragraph = str(paragraph).strip();
        if re.fullmatch(r"#{1,6}\s+[^\n]+", paragraph) {
            heading = re.sub(r"^#+\s*", "", paragraph);
            if re.search(r"(?i)\b(chapter|section)\s+\d+", heading) {
                chapter = heading;
            } elif paragraph.startswith("# ") {
                chapter = "";
            }
            section = (chapter + " / " + heading) if chapter and heading != chapter else heading;
            pending_heading += ("\n\n" if pending_heading else "") + paragraph;
            continue;
        }
        if pending_heading {
            paragraph = pending_heading + "\n\n" + paragraph;
            pending_heading = "";
        }
        for start in range(0, len(paragraph), 1800) {
            value = paragraph[start:start + 1800];
            if value {
                section_label = label + (" · " + section if section else "");
                chunks.append({"label": section_label + " · excerpt " + str(len(chunks) + 1), "text": value});
            }
        }
    }
    if pending_heading {
        chunks.append({"label": label + " · final heading", "text": pending_heading});
    }
    return chunks;
}

def extract_document(data: bytes, filename: str) -> list[dict[str, str]] {
    if len(data) > 4000000 { raise ValueError("Choose a file smaller than 4 MB."); }
    if not data { raise ValueError("The document is empty."); }
    name = filename.lower();
    chunks = [];
    if name.endswith(".pdf") {
        if not data.startswith(b"%PDF-") { raise ValueError("This file is not a valid PDF."); }
        try { reader = PdfReader(BytesIO(data)); }
        except Exception { raise ValueError("This PDF could not be read. Try a text-based PDF or a .txt file."); }
        if reader.is_encrypted { raise ValueError("Encrypted PDFs are not supported. Upload an unlocked copy."); }
        if len(reader.pages) > 50 { raise ValueError("Use a PDF with 50 pages or fewer for this demo."); }
        total = 0;
        for (index, page) in enumerate(reader.pages) {
            value = page.extract_text() or "";
            total += len(value);
            if total > 150000 { raise ValueError("Document text exceeds 150,000 characters."); }
            chunks.extend(chunk_text(value, "Page " + str(index + 1)));
        }
    } elif name.endswith(".txt") or name.endswith(".md") {
        try { value = data.decode("utf-8"); }
        except UnicodeDecodeError { raise ValueError("Text files must use UTF-8 encoding."); }
        if len(value) > 150000 { raise ValueError("Document text exceeds 150,000 characters."); }
        if "\x00" in value { raise ValueError("This appears to be a binary file, not plain text."); }
        chunks = chunk_text(value, "Document");
    } else {
        raise ValueError("Supported files: .pdf, .txt, and .md.");
    }
    if not chunks { raise ValueError("No readable text found. Scanned PDFs need OCR, which this demo does not provide."); }
    return chunks;
}

"""Convert a bounded text document into readable, page-attributed Markdown."""
def document_to_markdown(data: bytes, filename: str, chunks: list[dict[str, str]] | None = None) -> str {
    chunks = chunks or extract_document(data, filename);
    if filename.lower().endswith(".pdf") {
        try {
            converted = MarkItDown(enable_plugins=False).convert_stream(BytesIO(data), file_extension=".pdf");
            markdown = str(converted.markdown).strip();
            if markdown { return markdown; }
        } except Exception {
            # The validated local extractor below is a safe fallback for PDFs
            # whose structure MarkItDown cannot interpret.
        }
    }
    title: str = filename.rsplit(".", 1)[0].strip() or "Imported document";
    parts: list[str] = ["# " + title];
    current = "";
    for chunk in chunks {
        label = str(chunk["label"]);
        page = label.split(" · ")[0];
        if page != current { parts.append("\n## " + page); current = page; }
        parts.append(str(chunk["text"]).strip());
    }
    return "\n\n".join(parts).strip();
}
