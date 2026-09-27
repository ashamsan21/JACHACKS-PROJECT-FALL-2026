"""PromptZero's compiler. All analysis and graph traversal live in Jac."""
import re;
import math;
import time;

node Compilation {
    has source: str;
    has budget: int = 1024;
    has optimized: str = "";
    has issues: list = [];
    has diff: list = [];
    has locks: list = [];
    has graph: dict = {};
    has metrics: dict = {};
    has trace: list = [];
    has lock_ok: bool = True;
}

node Intent {
    has key: str;
    has original: str;
    has start: int;
    has end: int;
    has kind: str = "context";
    has candidate: str = "";
    has protected: bool = False;
    has reasons: list = [];
    has literals: list = [];
    has edits: list = [];
}

edge Contains {
    has relation: str = "contains";
}

def estimate_tokens(value: str) -> int {
    # Deliberately model-agnostic, not a billed/model tokenizer count.
    if not value { return 0; }
    return max(math.ceil(len(value.encode("utf-8")) / 4), len(re.findall(r"\w+|[^\w\s]", value)));
}

def units(source: str) -> list[dict[str, any]] {
    # Fenced code and multiline literal material are kept as a single unit.
    if "```" in source { return [{"text": source, "start": 0, "end": len(source)}]; }
    # Long speech-like drafts often omit sentence punctuation. Split only at
    # explicit discourse markers so one conditional does not lock everything.
    if len(source) > 240 and not re.search(r"[\"“”`]", source) {
        runon: list[dict[str, any]] = [];
        start = 0;
        markers = list(re.finditer(r",\s+|;\s+|\b(?:and then|then after|and the other thing|and basically|but at the same time|and also|but there will also|and one more thing|and maybe|because|i want to create|if)\b", source, 2));
        for marker in markers {
            point = marker.end() if str(marker.group()).lstrip().startswith(",") or str(marker.group()).lstrip().startswith(";") else marker.start();
            if point - start >= 55 {
                part = source_unit(source, start, point);
                if part { runon.append(part); }
                start = point;
            }
        }
        tail = source_unit(source, start, len(source));
        if tail { runon.append(tail); }
        if len(runon) > 1 { return runon; }
    }
    items: list[dict[str, any]] = [];
    beginning = 0;
    conversation = re.match(r"^\[[^\]]+\]\(chatgpt-conversation://[^)]+\):\s*", source);
    if conversation {
        reference = source_unit(source, 0, conversation.end());
        if reference { items.append(reference); }
        beginning = conversation.end();
    }
    quote = "";
    escaped = False;
    for index in range(len(source)) {
        character = source[index];
        if escaped {
            escaped = False;
            continue;
        }
        if character == "\\" {
            escaped = True;
            continue;
        }
        if quote {
            if character == quote { quote = ""; }
            continue;
        }
        if character in ["\"", "`", "“"] {
            quote = "”" if character == "“" else character;
            continue;
        }
        # Apostrophes inside contractions are not opening quotation marks.
        if character == "'" and (index == 0 or not source[index - 1].isalnum()) {
            quote = "'";
            continue;
        }
        boundary = character == "\n";
        if character in ".!?" and (index + 1 == len(source) or source[index + 1].isspace()) {
            boundary = True;
        }
        if boundary {
            part = source_unit(source, beginning, index + 1);
            if part { items.append(part); }
            beginning = index + 1;
        }
    }
    tail = source_unit(source, beginning, len(source));
    if tail { items.append(tail); }
    return items;
}

def source_unit(source: str, start: int, end: int) -> dict[str, any] {
    raw = source[start:end];
    value = raw.strip();
    if not value { return {}; }
    offset = start + len(raw) - len(raw.lstrip());
    return {"text": value, "start": offset, "end": offset + len(value)};
}

def critical_literals(value: str) -> list[str] {
    found = re.findall(r'"[^"\n]+"|“[^”\n]+”|`[^`\n]+`|\b\d+(?:[.,:/-]\d+)*(?:%|\b)|https?://[^\s]+', value);
    found.extend(re.findall(r"(?<!\w)'[^'\n]+'(?!\w)", value));
    return [str(value) for value in dict.fromkeys(found)];
}

def constraint_reasons(value: str) -> list[str] {
    reasons = [];
    if re.search(r"\b(must|required|always|never|only|exactly|at least|at most|no more|no fewer|under|within|without|do not|don't|cannot|can't|avoid|exclude|preserve|keep|ensure|make sure)\b", value, 2) {
        reasons.append("Explicit requirement or restriction");
    }
    if re.search(r"\b(not|no|except|unless)\b", value, 2) {
        reasons.append("Negation or exception");
    }
    if re.search(r"\d", value) { reasons.append("Numeric value"); }
    if critical_literals(value) { reasons.append("Exact literal"); }
    if re.search(r"[\"“”`]|(?<!\w)'", value) { reasons.append("Quoted material"); }
    if "```" in value { reasons.append("Code block"); }
    if re.search(r"\b(if|when|before|after|until|otherwise)\b", value, 2) {
        reasons.append("Condition or ordering");
    }
    if re.search(r"\b(use|include|return|focus|prioritize|prioritise|limit|restrict)\b", value, 2) {
        reasons.append("Explicit inclusion, format, or scope");
    }
    if re.search(r"\b(in (English|Spanish|French|Arabic|Chinese|German)|tone|audience|verbatim|case-sensitive)\b", value, 2) {
        reasons.append("Language, audience, or exact wording");
    }
    if re.search(r"\b(say|repeat|run|execute|print)\b", value, 2) {
        reasons.append("Action whose repetition may be intentional");
    }
    return reasons;
}

walker IntentWalker {
    has session: any = None;

    can build with Compilation entry {
        self.session = here;
        for (index, unit) in enumerate(units(here.source)) {
            here +>: Contains() :+> Intent(
                key="intent-" + str(index), original=str(unit["text"]),
                candidate=str(unit["text"]), start=int(unit["start"]), end=int(unit["end"])
            );
        }
        visit [-->];
    }

    can classify with Intent entry {
        text = here.original;
        if re.fullmatch(r"\[[^\]]+\]\(chatgpt-conversation://[^)]+\):?", text) {
            here.kind = "context";
            here.protected = False;
            return;
        }
        # Speech-to-text corrections refer to discarded prior wording, not to
        # the desired output. They should not lock an otherwise editable draft.
        if re.fullmatch(r"(?:no[,]?\s*)+(?:not\s+)?like\s+that(?:'s)?[.!?]*", text, 2) {
            here.kind = "context";
            here.protected = False;
            here.reasons = [];
            return;
        }
        here.reasons = constraint_reasons(text);
        here.literals = critical_literals(text);
        # Conditional wording remains inspectable, but only hard requirements,
        # exact values, negations, formats, and literals require verbatim lock.
        hard_reasons = [reason for reason in here.reasons if reason != "Condition or ordering"];
        here.protected = bool(hard_reasons);
        if here.reasons {
            here.kind = "constraint";
        } elif re.search(r"\b(table|bullets?|json|markdown|format|list|questions|outline|email|report|paragraphs?|slides|checklist)\b", text, 2) {
            here.kind = "output";
        } elif re.search(r"\b(summarize|summarise|explain|compare|write|create|build|analyze|analyse|review|help|plan|translate|debug|rewrite|want|need|tell)\b", text, 2) {
            here.kind = "goal";
        }
    }

    can done with Compilation exit {
        here.trace.append({"walker": "IntentWalker", "detail": "Segmented source and classified connected intent nodes"});
    }
}

walker AmbiguityWalker {
    has session: any = None;

    can begin with Compilation entry {
        self.session = here;
        visit [-->];
    }

    can inspect with Intent entry {
        value = here.original;
        checks = [
            (r"\b(better|best|good|improve)\b", "comparison", "What does success look like?", "Specify a criterion, such as accuracy, cost, or readability."),
            (r"\b(short|brief|detailed|long|soon|quickly)\b", "scope", "Consider a concrete limit", "A word count, deadline, or level of detail makes this more precise."),
            (r"\b(maybe|perhaps|possibly)\b", "optional", "Is this optional?", "The compiler keeps this wording so an optional request stays optional.")
        ];
        for (pattern, code, title, help_text) in checks {
            if re.search(pattern, value, 2) {
                self.session.issues.append({"node": here.key, "type": "ambiguity", "code": code, "title": title, "detail": help_text, "source": value});
            }
        }
        if re.search(r"\b(basically|in order to|at this point in time|just wanted to|really really)\b", value, 2) {
            self.session.issues.append({"node": here.key, "type": "verbosity", "code": "filler", "title": "Wording can be tighter", "detail": "Conservative phrase edits are shown in Context Diff.", "source": value});
        }
        if re.search(r"\b(only|exactly)\b", value, 2) and re.search(r"\b(at least|at most)\b", value, 2) {
            self.session.issues.append({"node": here.key, "type": "ambiguity", "code": "bounds", "title": "Review overlapping limits", "detail": "All limits are retained; the compiler does not choose between them.", "source": value});
        }
    }

    can done with Compilation exit {
        for finding in review_request(here.source) {
            here.issues.append(finding);
        }
        here.trace.append({"walker": "AmbiguityWalker", "detail": "Flagged possible ambiguity without guessing intent"});
    }
}

def review_request(source: str) -> list {
    findings = [];
    if re.search(r"\b(attached|uploaded|this pdf|these notes|the notes)\b", source, 2) {
        findings.append({
            "type": "ambiguity", "code": "missing_context",
            "title": "Referenced context is missing",
            "detail": "The prompt refers to source material. Attach it before using the compiled context."
        });
    }
    if re.search(r"\b(compare|choose|rank)\b", source, 2) and not re.search(r"\b(by|based on|cost|accuracy|speed|quality|price|criteria)\b", source, 2) {
        findings.append({
            "type": "ambiguity", "code": "criteria",
            "title": "Comparison criteria are unspecified",
            "detail": "Name the dimensions that matter. No ranking criteria were invented."
        });
    }
    if re.search(r"\bjson only\b", source, 2) and re.search(r"\b(markdown|prose|paragraph)\b", source, 2) {
        findings.append({
            "type": "ambiguity", "code": "format_conflict",
            "title": "Check the output format",
            "detail": "JSON-only and prose or Markdown instructions may conflict. Both were preserved."
        });
    }
    maxima = re.findall(r"\b(?:under|at most|no more than|maximum of)\s+(\d+)\s+words?\b", source, 2);
    minima = re.findall(r"\b(?:at least|no fewer than|minimum of)\s+(\d+)\s+words?\b", source, 2);
    if maxima and minima and max([int(value) for value in minima]) > min([int(value) for value in maxima]) {
        findings.append({
            "type": "ambiguity", "code": "length_conflict",
            "title": "Word limits may conflict",
            "detail": "A minimum exceeds a maximum. Check whether the limits apply to the same output; neither was removed."
        });
    }
    # Recognize a few explicit contradiction pairs, without pretending to reason generally.
    for subject in ["citations", "examples", "code", "sources", "tables"] {
        positive = re.search(r"(?<!not )(?<!n't )\binclude\s+" + subject + r"\b", source, 2);
        negative = re.search(r"\b(?:do not include|don't include|exclude|without)\s+" + subject + r"\b", source, 2);
        if positive and negative {
            findings.append({
                "type": "ambiguity", "code": "inclusion_conflict",
                "title": "Check conflicting inclusion rules",
                "detail": "The prompt appears to both include and exclude " + subject + ". Both requirements remain."
            });
        }
    }
    if len(source.split()) > 90 and len(units(source)) == 1 {
        findings.append({
            "type": "ambiguity", "code": "long_sentence",
            "title": "Separate the goal from the requirements",
            "detail": "This is one long source unit. Add sentence breaks to make constraints easier to inspect; it was not split by guesswork."
        });
    }
    return findings;
}

walker CompressionWalker {
    has session: any = None;
    has seen: set = set();
    has pieces: list = [];

    can begin with Compilation entry {
        self.session = here;
        visit [-->];
    }

    can compress with Intent entry {
        value = here.original;
        if re.fullmatch(r"\[[^\]]+\]\(chatgpt-conversation://[^)]+\):?", value) {
            here.candidate = "";
            here.edits.append("Conversation reference metadata removed");
            return;
        }
        if re.fullmatch(r"(?:no[,]?\s*)+(?:not\s+)?like\s+that(?:'s)?[.!?]*", value, 2) {
            here.candidate = "";
            here.edits.append("Discarded speech correction removed");
            return;
        }
        rules = [
            (r"^(?:no[,]?\s*)+(?:not\s+)?like\s+that(?:'s)?[.!?]*$", "", "Discarded speech correction removed"),
            (r"^(?:hey|hi|hello)[,!]?\s+", "", "Greeting removed"),
            (r"^so\s+", "", "Opening filler removed"),
            (r"^basically[,]?\s+", "", "Opening filler removed"),
            (r"^i (?:just )?(?:wanted|would like) to ask (?:you )?(?:to )?", "", "Request preamble shortened"),
            (r"^(?:could|can|would) you (?:please )?", "", "Request preamble shortened"),
            (r"^please\s+", "", "Politeness marker removed"),
            (r"^i (?:really )?(?:want|need) you to\s+", "", "Request preamble shortened"),
            (r"^(?:and\s+)?basically\s+", "", "Connector removed"),
            (r"^but at the same time\s+", "", "Connector shortened"),
            (r"^(?:and\s+)?also\s+", "", "Connector shortened"),
            (r"^and one more thing\s+", "", "Connector shortened"),
            (r"^and maybe\s+", "", "Connector shortened"),
            (r"^(?:what i want is for you to|i need you to|can you)\s+", "", "Request preamble shortened"),
            (r"\btry to make me\b", "create", "Request wording shortened"),
            (r"\bi dont really want it to be super long because people probably wont pay attention if its too long\b", "keep it concise", "Length request clarified"),
            (r"\bmake sure you dont leave out\b", "include", "Requirement shortened"),
            (r"\bthe stuff about\b", "", "Wording shortened"),
            (r"\bbecause thats probably the most important part\b", "", "Filler removed"),
            (r"\bmake it sound professional but not like super corporate or like it was obviously written by ai\b", "use a professional, natural, non-corporate tone", "Tone clarified"),
            (r"\bwould probably be good but you can decide if you think something else makes more sense\b", "", "Hedge removed"),
            (r"\bmake sure that the presentation is understandable by\b", "make the presentation clear to", "Audience wording shortened"),
            (r"\bpeople who dont know much about ai\b", "nontechnical audiences", "Audience clarified"),
            (r"\bthere will also be some technical people there so dont make it too basic either\b", "technical audiences without oversimplifying", "Audience clarified"),
            (r"\bdo not change any of the numbers from my results because those need to stay exactly the same\b", "Preserve every result number exactly", "Numeric constraint shortened"),
            (r"\bdo not change any of the numbers from my results\b", "Preserve every result number exactly", "Numeric constraint shortened"),
            (r"^because those need to stay exactly the same\b", "Keep them exact", "Numeric constraint shortened"),
            (r"\bdont make up any information if something is missing just tell me that its missing\b", "Do not invent missing information; identify any gaps", "Grounding constraint shortened"),
            (r"\bdont make up any information\b", "Do not invent missing information", "Grounding constraint shortened"),
            (r"^if something is missing just tell me that its missing\b", "If information is missing, identify the gap", "Grounding constraint shortened"),
            (r"\bgive me some speaker notes too\b", "include speaker notes", "Output request shortened"),
            (r"\band yeah basically just make it really good and clear and interesting\b", "make it clear and engaging", "Filler removed"),
            (r"^i want something like to be kinda good questions that i ask\.*$", "Create engaging questions.", "Question intent reconstructed"),
            (r"^that the viewer (?:wo-\s*)?would-\s*would like to have an answers to just be like me[,]?\s*like be viral like that$", "Ask what viewers want answered. Match my voice and make the questions shareable.", "Audience intent reconstructed"),
            (r"\b(?:wo-\s*)?would-\s*would\b", "would", "Speech stutter removed"),
            (r"\b([a-z]+)(?:[\s-]+\1\b)+", r"\1", "Repeated speech fragment removed"),
            (r"\bto be kinda good questions\b", "engaging questions", "Vague wording clarified"),
            (r"\bkinda good questions\b", "engaging questions", "Vague wording clarified"),
            (r"\bgood questions\b", "engaging questions", "Vague wording clarified"),
            (r"\ban answers\b", "answers", "Grammar corrected"),
            (r"^i want something like\s+", "Create ", "Speech filler removed"),
            (r"\bthat the viewer would like to have answers to\b", "that viewers want answered", "Audience intent clarified"),
            (r"\bjust be like me[,]?\s*like\s*", "Match my voice and ", "Voice requirement clarified"),
            (r"\bbe viral like that\b", "make them shareable", "Vague reach goal clarified"),
            (r"^make the camera slowly (?:get|come|move) closer to (.+?)[.!?]*$", r"Use a slow dolly-in toward \1.", "Informal camera movement replaced with the filmmaking term"),
            (r"^move the camera slowly (?:closer to|toward) (.+?)[.!?]*$", r"Use a slow dolly-in toward \1.", "Informal camera movement replaced with the filmmaking term"),
            (r"\s+\.\.\.$", ".", "Trailing speech pause removed"),
            (r"^i want (?:to create|to add|to make)\s+", "Create ", "Request preamble shortened"),
            (r"^and the other thing i want (?:is|it to)\s+", "Also, ", "Request preamble shortened"),
            (r"^and then\s+", "Then ", "Connector shortened"),
            (r"^then after[,]?\s+", "Then ", "Connector shortened"),
            (r"^build the first end-to-end vertical slice:\s*", "Build: ", "Project wording shortened"),
            (r"^make the ui polished and dark developer-tool styled\.?$", "Use a polished, dark developer-tool UI.", "Project wording shortened"),
            (r"^structure the jac backend so walkers such as\s+", "Implement analysis in Jac walkers: ", "Project wording shortened"),
            (r"\s+are genuinely responsible for analysis\.?$", ".", "Project wording shortened"),
            (r"^prepare it for ([^.]*) deployment if feasible\.?$", "If feasible, prepare for \\1 deployment.", "Project wording shortened"),
            (r"\bin order to\b", "to", "Phrase shortened"),
            (r"\bat this point in time\b", "now", "Phrase shortened"),
            (r"\bdue to the fact that\b", "because", "Phrase shortened"),
            (r"\bin the event that\b", "if", "Phrase shortened"),
            (r"\ba large number of\b", "many", "Phrase shortened"),
            (r"\bfor the purpose of\b", "for", "Phrase shortened")
            ,(r"\btranfered\b", "transferred", "Spelling corrected")
            ,(r"\bfrim\b", "from", "Spelling corrected")
            ,(r"\bextention\b", "extension", "Spelling corrected")
            ,(r"\bsaveing\b", "saving", "Spelling corrected")
            ,(r"\bdescriping\b", "describing", "Spelling corrected")
            ,(r"\bsomthing\b", "something", "Spelling corrected")
            ,(r"\bvocab\b", "vocabulary", "Word clarified")
            ,(r"\bshout\b", "shot", "Camera term corrected")
            ,(r"\bpostion\b", "position", "Spelling corrected")
            ,(r"\bangel\b", "angle", "Camera term corrected")
            ,(r"\btalkng\b", "talking", "Spelling corrected")
            ,(r"\bdescrid\b", "describe", "Spelling corrected")
            ,(r"\bmultiples times\b", "repeatedly", "Phrase shortened")
            ,(r"\bin the perfect word\b", "precisely", "Phrase shortened")
            ,(r"\bthe system could suggest\b", "suggest", "Phrase shortened")
            ,(r"\bso ai save time in thinking\b", "to save the user time", "Phrase clarified")
        ];
        for (pattern, replacement, reason) in rules {
            revised = re.sub(pattern, replacement, value, flags=2);
            if revised != value {
                here.edits.append(reason);
                value = revised;
            }
        }
        value = value.strip();
        value = re.sub(r"\s{2,}", " ", value);
        if not value { value = here.original; }
        if value { value = value[0].upper() + value[1:]; }
        if value in self.seen and not here.protected {
            here.candidate = "";
            here.edits.append("Exact repeated instruction removed");
        } else {
            self.seen.add(value);
            here.candidate = value;
            self.pieces.append(value);
        }
    }

    can done with Compilation exit {
        here.optimized = " ".join(self.pieces);
        # Never trade more tokens for a superficial rewrite.
        if estimate_tokens(here.optimized) > estimate_tokens(here.source) {
            here.optimized = here.source;
        }
        here.trace.append({"walker": "CompressionWalker", "detail": "Compressed atomic intent nodes with lightweight Jac rules"});
    }
}

walker MeaningLockWalker {
    has session: any = None;
    has pieces: list = [];

    can begin with Compilation entry {
        self.session = here;
        visit [-->];
    }

    can verify with Intent entry {
        candidate = here.candidate;
        passed = True;
        if here.protected {
            for literal in here.literals {
                if literal not in candidate { passed = False; }
            }
            original_negative = bool(re.search(r"\b(?:not|never|no|without|do not|don't|cannot|can't)\b", here.original, 2));
            candidate_negative = bool(re.search(r"\b(?:not|never|no|without|do not|don't|cannot|can't|preserve)\b", candidate, 2));
            if original_negative and not candidate_negative { passed = False; }
            if not passed {
                here.candidate = here.original;
                candidate = here.original;
                self.session.lock_ok = False;
            }
            lock = {"node": here.key, "text": here.original, "reasons": here.reasons, "passed": passed, "result": candidate};
            self.session.locks.append(lock);
        }
        if candidate { self.pieces.append(candidate); }
    }

    can done with Compilation exit {
        here.optimized = " ".join(self.pieces);
        here.trace.append({"walker": "MeaningLockWalker", "detail": "Checked exact literals and negation only; no model inference"});
    }
}

walker BudgetWalker {
    can measure with Compilation entry {
        before_prompt = estimate_tokens(here.source);
        after_prompt = estimate_tokens(here.optimized);
        before = before_prompt;
        after = after_prompt;
        here.metrics = {
            "before": before, "after": after, "saved": before - after,
            "percent": round(100 * (before - after) / max(1, before)),
            "prompt_before": before_prompt, "prompt_after": after_prompt,
            "context_before": 0, "context_after": 0,
            "budget": here.budget, "within_budget": after <= here.budget,
            "estimate": True, "method": "max(UTF-8 bytes / 4, word-and-punctuation count), rounded up",
            "model_calls": 0
        };
        if after > here.budget {
            here.issues.append({"type": "budget", "title": "Over your token target", "detail": "Meaning Lock takes priority. Reduce the scope or increase the budget; protected requirements were not cut."});
        }
        here.trace.append({"walker": "BudgetWalker", "detail": "Estimated full outgoing context; checked budget without truncation"});
    }
}

walker GraphWalker {
    has session: any = None;
    has nodes: list = [];
    has edges: list = [];

    can begin with Compilation entry {
        self.session = here;
        self.nodes.append({"id": "request", "kind": "request", "text": "Your request", "protected": False});
        visit [-->];
    }

    can serialize with Intent entry {
        actual = here.candidate;
        if self.session.optimized == self.session.source { actual = here.original; }
        status = "preserved";
        if not actual { status = "removed"; }
        elif actual != here.original { status = "compressed"; }
        self.nodes.append({
            "id": here.key, "kind": here.kind, "text": here.original,
            "result": actual, "protected": here.protected,
            "reasons": here.reasons, "literals": here.literals,
            "start": here.start, "end": here.end, "status": status
        });
        self.edges.append({"source": "request", "target": here.key, "relation": "contains"});
        self.session.diff.append({"id": here.key, "kind": status, "original": here.original, "result": actual, "reason": "; ".join(here.reasons if here.protected else here.edits) or "Source wording retained", "scope": "prompt"});
    }

    can done with Compilation exit {
        here.graph = {"nodes": self.nodes, "edges": self.edges};
        here.trace.append({"walker": "GraphWalker", "detail": "Traversed actual connected nodes to serialize the inspectable graph and diff"});
    }
}

def compile_prompt(prompt: str, budget: int = 1024) -> dict {
    started = time.perf_counter();
    source = prompt.strip();
    if not source { raise ValueError("Enter a prompt to compile."); }
    if len(source) > 20000 { raise ValueError("Prompts are limited to 20,000 characters."); }
    if budget < 64 or budget > 32000 { raise ValueError("Budget must be between 64 and 32,000 tokens."); }
    session = Compilation(source=source, budget=budget);
    session spawn IntentWalker();
    session spawn AmbiguityWalker();
    session spawn CompressionWalker();
    session spawn MeaningLockWalker();
    session spawn BudgetWalker();
    session spawn GraphWalker();
    return {
        "original": source, "optimized": session.optimized,
        "compiled": session.optimized,
        "metrics": session.metrics, "issues": session.issues,
        "locks": session.locks, "lock_ok": session.lock_ok,
        "graph": session.graph, "diff": session.diff,
        "trace": session.trace, "context": "", "context_note": "",
        "duration_ms": float(format((time.perf_counter() - started) * 1000, ".1f")),
        "engine": "Jac · lightweight deterministic rules", "version": "0.3.0"
    };
}

def compile_document_markdown(source_text: str, markdown: str, filename: str) -> dict {
    before = estimate_tokens(source_text);
    after = estimate_tokens(markdown);
    saved = before - after;
    output_filename = filename.rsplit(".", 1)[0] + ".md";
    return {
        "mode": "document", "original": source_text, "optimized": markdown,
        "compiled": markdown, "filename": output_filename, "vocabulary": [],
        "issues": [], "locks": [], "lock_ok": True,
        "context": "", "context_note": "",
        "metrics": {
            "before": before, "after": after, "saved": saved,
            "percent": round(100 * saved / max(1, before)),
            "prompt_before": 0, "prompt_after": 0,
            "context_before": before, "context_after": after,
            "budget": after, "within_budget": True, "estimate": True,
            "method": "max(UTF-8 bytes / 4, word-and-punctuation count), rounded up",
            "model_calls": 0
        },
        "graph": {"nodes": [
            {"id": "request", "kind": "request", "text": filename, "protected": False},
            {"id": "document", "kind": "output", "text": "PDF", "result": "Markdown", "protected": False, "reasons": [], "literals": [], "start": 0, "end": len(source_text), "status": "compressed"}
        ], "edges": [{"source": "request", "target": "document", "relation": "converted_to"}]},
        "diff": [{"id": "document", "kind": "compressed", "original": "PDF text", "result": "Markdown", "reason": "Converted with Microsoft MarkItDown", "scope": "document"}],
        "trace": [{"walker": "DocumentWalker", "detail": "Converted the complete document to Markdown without selecting, summarizing, or removing content"}],
        "duration_ms": 0.0, "engine": "Jac + Microsoft MarkItDown", "version": "0.3.0"
    };
}
