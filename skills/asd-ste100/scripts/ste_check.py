#!/usr/bin/env python3
"""Check Markdown or plain text against the mechanical rules of ASD-STE100.

This finds what a machine can find: sentence length, paragraph length, contractions,
perfect tenses, modal verbs, and a short list of words that STE does not approve.
It also warns about possible passive voice and -ing words. It has no dictionary and
no grammar: a clean result means "no mechanical fault found", not "this is STE".

    ste_check.py FILE...             # list items = procedure (20), prose = description (25)
    ste_check.py --mode procedure F  # every sentence gets the 20-word limit
    ste_check.py --allow logging,caching F   # technical names / verbs of this project
    cat text.md | ste_check.py -

Exit status: 0 clean, 1 errors found (or warnings with --strict), 2 bad usage.
"""

import argparse
import re
import sys

PROCEDURE_MAX = 20
DESCRIPTION_MAX = 25
PARAGRAPH_MAX = 6

# Words STE does not approve (or approves only in another meaning) -> what to write.
# A memory aid for the frequent ones. The STE dictionary is the authority.
UNAPPROVED = {
    r"utili[sz]\w*": "use",
    r"leverag\w*": "use",
    r"perform(?:s|ed|ing)?": "do",
    r"carr(?:y|ies|ied|ying) out": "do",
    r"accomplish\w*": "do",
    r"ensur\w*": "make sure",
    r"verif(?:y|ies|ied|ying)": "make sure / do a check",
    r"begin(?:s|ning)?|began|begun": "start",
    r"commenc\w*": "start",
    r"initiat\w*": "start",
    r"terminat\w*": "stop",
    r"indicat(?:e|es|ed|ing)": "show",
    r"demonstrat(?:e|es|ed|ing)": "show",
    r"inform(?:s|ed|ing)?": "tell",
    r"obtain\w*": "get",
    r"provid(?:e|es|ed|ing)": "give / supply",
    r"requir(?:e|es|ed|ing)": "it is necessary / must",
    r"need(?:s|ed|ing)? to": "must",
    r"ha(?:ve|s|d) to": "must",
    r"allow(?:s|ed|ing)?": "let",
    r"permit(?:s|ted|ting)?": "let",
    r"enabl(?:e|es|ed|ing)": "let / make possible",
    r"facilitat\w*": "help",
    r"assist(?:s|ed|ing)?": "help",
    r"attempt(?:s|ed|ing)?": "try",
    r"locat(?:e|es|ed|ing)": "find",
    r"modif(?:y|ies|ied|ying)": "change",
    r"alter(?:s|ed|ing)?": "change",
    r"retain(?:s|ed|ing)?": "keep",
    r"rotat(?:e|es|ed|ing)": "turn",
    r"plac(?:e|es|ed|ing) (?:the|a|an|it|them)": "put",
    r"additional": "more",
    r"numerous": "many",
    r"proper(?:ly)?": "correct / correctly",
    r"appropriate(?:ly)?": "applicable / correct",
    r"prior to": "before",
    r"in order to": "to",
    r"due to": "because of",
    r"as well as": "and",
    r"via": "through / with",
    r"upon": "on / when",
    r"whilst": "while",
    r"e\.g\.": "for example",
    r"i\.e\.": "say it directly, without the abbreviation",
    r"etc\.?": "give the full list, or say 'and other ...'",
}

MODALS = {
    "should": "must, or the imperative",
    "shall": "must",
    "may": "can (ability) / it is possible that",
    "might": "it is possible that",
    "could": "can / it is possible that",
    "would": "simple present or simple future",
    "ought": "must",
}

IRREGULAR = (
    "done|made|shown|given|taken|found|set|put|kept|held|built|sent|written|run|seen|"
    "known|left|lost|read|sold|told|broken|chosen|driven|drawn|hidden|cut|shut|bent|"
    "fed|thrown|worn|torn|gone|been"
)
PARTICIPLE = rf"(?:\w+ed|{IRREGULAR})"
PASSIVE = re.compile(
    rf"\b(?:am|is|are|was|were|be|been|being|gets?|got)\s+(?:not\s+)?(?:\w+ly\s+)?({PARTICIPLE})\b"
)
PERFECT = re.compile(rf"\b(?:has|have|had|having)\s+(?:not\s+)?(?:\w+ly\s+)?({PARTICIPLE})\b")
CONTRACTION = re.compile(
    r"\b\w+(?:n['’]t|['’](?:re|ve|ll|d|m))\b|\b(?:it|that|there|here|what|who|let)['’]s\b"
)
ING = re.compile(r"\b[a-z]{2,}ing\b")
# Not verbs, or nouns that are usual technical names.
ING_OK = set(
    "meaning spelling writing during thing nothing something anything everything string bring ring spring wing "
    "opening wiring lighting servicing setting warning bearing housing casing fitting "
    "mounting coating training building heading spacing timing".split()
)

FENCE = re.compile(r"^\s*(```|~~~)")
LIST_ITEM = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(?:\[[ xX]\]\s+)?")
SENTENCE_END = re.compile(r"(?<=[.!?])\s+(?=[\"'(\[]?[A-Z0-9])|:\s+|\s+[—–]\s+")
PAREN = re.compile(r"\(([^()]*)\)")
WORD = re.compile(r"[A-Za-z0-9][A-Za-z0-9'’_./-]*")


def blocks(lines):
    """Yield (kind, first_line_number, text) for each paragraph and list item."""
    kind, start, buf = None, 0, []
    in_fence = False
    in_front = bool(lines) and lines[0].strip() == "---"

    def flush():
        nonlocal kind, buf
        if buf:
            yield kind, start, "\n".join(buf)
        kind, buf = None, []

    for number, raw in enumerate(lines, 1):
        line = raw.rstrip("\n")
        if in_front:
            if number > 1 and line.strip() == "---":
                in_front = False
            continue
        if FENCE.match(line):
            in_fence = not in_fence
            yield from flush()
            continue
        if in_fence:
            continue
        line = re.sub(r"^\s*(?:>\s?)+", "", line)
        stripped = line.strip()
        if not stripped or stripped.startswith(("#", "|", "<!--")) or set(stripped) <= set("-=*_ "):
            yield from flush()
            continue
        item = LIST_ITEM.match(line)
        if item:
            yield from flush()
            kind, start, buf = "list", number, [line[item.end():]]
        elif buf:
            buf.append(stripped)
        else:
            kind, start, buf = "para", number, [stripped]
    yield from flush()


def clean(text):
    """Drop Markdown syntax. Code and URLs become one word each. Newlines stay."""
    text = re.sub(r"`[^`\n]*`", "CODE", text)
    text = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"https?://\S+", "URL", text)
    return text.replace("*", "")


def sentences(text):
    """Yield (offset, sentence). A colon or a dash ends a sentence for the word count."""
    pos = 0
    for sep in SENTENCE_END.finditer(text):
        yield pos, text[pos:sep.start()]
        pos = sep.end()
    yield pos, text[pos:]


def check_block(kind, start, raw, mode, allow):
    text = clean(raw)
    procedure = mode == "procedure" or (mode == "auto" and kind == "list")
    limit = PROCEDURE_MAX if procedure else DESCRIPTION_MAX
    count = 0
    for offset, sentence in sentences(text):
        line = start + text.count("\n", 0, offset)
        # Text in parentheses counts as a sentence of its own.
        parts = [PAREN.sub(" ", sentence)] + PAREN.findall(sentence)
        for part in parts:
            flat = " ".join(part.split())
            words = WORD.findall(flat)
            if not words:
                continue
            count += 1
            excerpt = flat if len(flat) <= 70 else flat[:67] + "..."
            if len(words) > limit:
                what = "procedure" if procedure else "description"
                yield line, "E", "length", f"{len(words)} words, {what} limit is {limit}", excerpt
            yield from ((line, *found, excerpt) for found in check_words(flat.lower(), allow))
    if kind == "para" and count > PARAGRAPH_MAX:
        yield start, "E", "paragraph", f"{count} sentences, limit is {PARAGRAPH_MAX}", ""


def check_words(low, allow):
    for match in CONTRACTION.finditer(low):
        yield "E", "contraction", f"'{match.group()}': write the full words"
    for match in PERFECT.finditer(low):
        yield "E", "tense", f"'{match.group()}': use the simple past or the simple present"
    for word, instead in MODALS.items():
        if word not in allow and re.search(rf"\b{word}\b", low):
            yield "E", "modal", f"'{word}': write: {instead}"
    for pattern, instead in UNAPPROVED.items():
        for match in re.finditer(rf"(?<![\w-])(?:{pattern})(?![\w-])", low):
            if match.group().split()[0] not in allow:
                yield "E", "word", f"'{match.group()}': write: {instead}"
    for match in PASSIVE.finditer(low):
        if match.group(1) not in allow:
            yield "W", "passive", f"'{match.group()}': active voice, unless this is an adjective"
    for match in ING.finditer(low):
        if match.group() not in ING_OK and match.group() not in allow:
            yield "W", "ing", f"'{match.group()}': -ing form, unless this is a technical name"


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("files", nargs="+", help="files to check, or - for stdin")
    parser.add_argument("--mode", choices=("auto", "procedure", "description"), default="auto")
    parser.add_argument("--allow", default="", help="comma-separated technical names and verbs")
    parser.add_argument("--strict", action="store_true", help="warnings also fail")
    args = parser.parse_args()
    allow = {word.strip().lower() for word in args.allow.split(",") if word.strip()}

    errors = warnings = 0
    for path in args.files:
        try:
            lines = sys.stdin.readlines() if path == "-" else open(path, encoding="utf-8").readlines()
        except OSError as error:
            print(f"ste_check: {error}", file=sys.stderr)
            return 2
        for kind, start, raw in blocks(lines):
            for line, level, rule, message, excerpt in check_block(kind, start, raw, args.mode, allow):
                errors += level == "E"
                warnings += level == "W"
                tail = f"  | {excerpt}" if excerpt else ""
                print(f"{path}:{line}: {level} {rule}: {message}{tail}")
    print(f"ste_check: {errors} errors, {warnings} warnings", file=sys.stderr)
    return 1 if errors or (args.strict and warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
