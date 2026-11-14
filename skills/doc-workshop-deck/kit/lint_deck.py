# lint_deck.py (harbor#1502) — fail a teaching deck that breaks the decidable rules
"""Usage: python lint_deck.py <deck.pptx> <plan.json> [--json]

Reads the deck's slide text and speaker notes (first notes line = tags, see SKILL.md)
and checks it against plan.json. Exit 0 = no FAIL, 1 = at least one FAIL, 2 = bad input.
"""
import json
import re
import sys

from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE_TYPE, PP_PLACEHOLDER
from pptx.util import Pt

DEFAULTS = {
    "headline_min_words": 4,      # a topic label is 1-3 words; an assertion is longer
    "headline_max_words": 16,
    "body_max_words": 45,         # on-slide words outside the headline
    "max_gap_min": 10,            # minutes between activity/check slides
    "duration_tolerance": 0.10,   # planned minutes vs plan duration
    "font_floor_pt": 12,          # projected text below this is unreadable at the back
    "redundancy_run": 8,          # this many consecutive slide words read aloud in notes = FAIL
    "slides_per_min": 1.0,
}
KINDS = {"title", "content", "activity", "check"}
EXEMPT_HEADLINE = {"title"}
TAG = re.compile(r"\[([^\]]+)\]")
WORD = re.compile(r"[^\W_]+(?:[-'][^\W_]+)*", re.UNICODE)


def words(text):
    return WORD.findall(text.lower())


def is_title(shp):
    # pptxgenjs writes its title placeholder with idx="100", which python-pptx's
    # shapes.title (idx 0 only) never finds — match on the placeholder TYPE instead.
    if not shp.is_placeholder:
        return shp.name.lower().startswith("headline")
    return shp.placeholder_format.type in (PP_PLACEHOLDER.TITLE, PP_PLACEHOLDER.CENTER_TITLE)


def slide_parts(slide, floor_pt):
    """Return (headline, body_text, has_visual, small_runs). Shapes named nav-* are skipped."""
    headline, body, has_visual, small = "", [], False, []
    for shp in slide.shapes:
        if shp.name.lower().startswith("nav-"):
            continue
        if shp.shape_type in (MSO_SHAPE_TYPE.PICTURE, MSO_SHAPE_TYPE.CHART, MSO_SHAPE_TYPE.TABLE,
                              MSO_SHAPE_TYPE.GROUP, MSO_SHAPE_TYPE.LINE, MSO_SHAPE_TYPE.AUTO_SHAPE):
            has_visual = True
        if getattr(shp, "is_connector", False):
            has_visual = True
        if getattr(shp, "has_text_frame", False) and shp.has_text_frame:
            text = shp.text_frame.text.strip()
            for para in shp.text_frame.paragraphs:
                for run in para.runs:
                    if run.font.size is not None and run.font.size < Pt(floor_pt) and run.text.strip():
                        small.append((run.text.strip()[:30], run.font.size.pt))
            if not text:
                continue
            if is_title(shp) and not headline:
                headline = text
            else:
                body.append(text)
        if getattr(shp, "has_table", False) and shp.has_table:
            for row in shp.table.rows:
                for cell in row.cells:
                    body.append(cell.text)
    return headline, " ".join(body), has_visual, small


def parse_tags(notes):
    first = notes.strip().splitlines()[0] if notes.strip() else ""
    tags = TAG.findall(first)
    out = {"min": None, "kind": None, "outcomes": [], "defs": []}
    for t in tags:
        t = t.strip()
        m = re.fullmatch(r"(\d+(?:[.,]\d+)?)\s*min", t)
        if m:
            out["min"] = float(m.group(1).replace(",", "."))
        elif t.lower() in KINDS:
            out["kind"] = t.lower()
        elif re.fullmatch(r"O\d+", t):
            out["outcomes"].append(t)
        elif t.lower().startswith("def "):
            out["defs"].append(t[4:].strip().lower())
    script = "\n".join(notes.strip().splitlines()[1:])
    return out, script


def longest_shared_run(a, b):
    """Longest run of consecutive words of a that also appears consecutively in b."""
    if not a or not b:
        return 0
    bs = " " + " ".join(b) + " "
    best, i = 0, 0
    while i < len(a):
        j = i + best + 1
        while j <= len(a) and (" " + " ".join(a[i:j]) + " ") in bs:
            best = j - i
            j += 1
        i += 1
    return best


def lint(deck_path, plan):
    lim = dict(DEFAULTS, **plan.get("limits", {}))
    prs = Presentation(deck_path)
    findings = []

    def fail(rule, n, msg):
        findings.append({"level": "FAIL", "rule": rule, "slide": n, "msg": msg})

    slides, total, clock = [], 0.0, 0.0
    first_use, def_at = {}, {}
    glossary = [g.lower() for g in plan.get("glossary", [])]
    outcome_ids = [o["id"] for o in plan.get("outcomes", [])]
    checked = set()

    for n, slide in enumerate(prs.slides, 1):
        notes = slide.notes_slide.notes_text_frame.text if slide.has_notes_slide else ""
        tags, script = parse_tags(notes)
        headline, body, has_visual, small = slide_parts(slide, lim["font_floor_pt"])
        slides.append(n)

        if tags["min"] is None:
            fail("notes.timing", n, "first notes line has no [N min] tag")
        if tags["kind"] is None:
            fail("notes.kind", n, "first notes line has no kind tag " + "/".join(sorted(KINDS)))
        if not script.strip():
            fail("notes.script", n, "speaker notes carry tags but no script")
        kind = tags["kind"] or "content"

        if kind not in EXEMPT_HEADLINE:
            hw = len(words(headline))
            if hw == 0:
                fail("headline.missing", n, "no headline (title placeholder or shape named 'headline')")
            elif hw < lim["headline_min_words"]:
                fail("headline.topic-label", n, f"headline '{headline}' has {hw} words; an assertion needs >= {lim['headline_min_words']}")
            elif hw > lim["headline_max_words"]:
                fail("headline.too-long", n, f"headline has {hw} words (> {lim['headline_max_words']})")
            if headline.rstrip().endswith("."):
                fail("headline.period", n, "headline ends with a period")
            bw = len(words(body))
            if bw > lim["body_max_words"]:
                fail("body.words", n, f"{bw} on-slide words outside the headline (> {lim['body_max_words']})")
            if not has_visual:
                fail("slide.no-visual", n, "no picture, chart, table, shape or line on the slide")
        for txt, pt in small:
            fail("font.floor", n, f"'{txt}' at {pt}pt (< {lim['font_floor_pt']}pt)")

        run = longest_shared_run(words(headline + " " + body), words(script))
        if run >= lim["redundancy_run"]:
            fail("notes.reads-slide", n, f"notes repeat {run} consecutive slide words: the speaker would read the slide aloud")

        if kind in ("activity", "check"):
            if not tags["outcomes"]:
                fail("outcome.untagged", n, f"{kind} slide serves no outcome [O#]")
            for o in tags["outcomes"]:
                if o not in outcome_ids:
                    fail("outcome.unknown", n, f"{o} is not in plan.json outcomes")
                checked.add(o)
            clock = 0.0
        else:
            clock += tags["min"] or 0.0
            if clock > lim["max_gap_min"]:
                fail("cadence.gap", n, f"{clock:g} min since the last activity/check (> {lim['max_gap_min']})")
                clock = 0.0
        total += tags["min"] or 0.0

        for d in tags["defs"]:
            def_at.setdefault(d, n)
        visible = " " + " ".join(words(headline + " " + body)) + " "
        for g in glossary:
            if g not in first_use and (" " + " ".join(words(g)) + " ") in visible:
                first_use[g] = n

    for o in outcome_ids:
        if o not in checked:
            fail("outcome.no-check", 0, f"outcome {o} has no activity or check slide")
    for g in glossary:
        if g not in def_at:
            fail("glossary.undefined", 0, f"glossary term '{g}' has no [def {g}] slide")
        elif g in first_use and first_use[g] < def_at[g]:
            fail("glossary.used-before-defined", first_use[g], f"'{g}' appears before its definition on slide {def_at[g]}")

    dur = float(plan.get("duration_min", 0))
    if dur:
        if abs(total - dur) > dur * lim["duration_tolerance"]:
            fail("timing.total", 0, f"planned {total:g} min against a {dur:g} min session (±{lim['duration_tolerance']:.0%})")
        if len(slides) > dur * lim["slides_per_min"]:
            fail("timing.slide-count", 0, f"{len(slides)} slides for {dur:g} min (> {lim['slides_per_min']:g}/min)")
    return findings, total, len(slides)


def main(argv):
    if len(argv) < 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    with open(argv[2], encoding="utf-8") as fh:
        plan = json.load(fh)
    findings, total, count = lint(argv[1], plan)
    if "--json" in argv:
        print(json.dumps({"findings": findings, "minutes": total, "slides": count}, ensure_ascii=False, indent=1))
    else:
        for f in findings:
            where = f"slide {f['slide']}" if f["slide"] else "deck"
            print(f"FAIL {f['rule']:28} {where:9} {f['msg']}")
        print(f"{count} slides, {total:g} planned min, {len(findings)} FAIL")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
