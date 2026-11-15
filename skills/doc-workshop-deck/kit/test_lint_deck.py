# test_lint_deck.py (harbor#1502) — a clean deck passes, each planted violation fails its rule
"""Usage: python test_lint_deck.py   (needs python-pptx). Exit 0 = every case behaved."""
import copy
import os
import sys
import tempfile

from pptx import Presentation
from pptx.enum.shapes import MSO_SHAPE
from pptx.util import Inches, Pt

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_deck  # noqa: E402

PLAN = {
    "duration_min": 10,
    "outcomes": [{"id": "O1", "verb": "order", "text": "put the DNS steps in order"}],
    "glossary": ["DNS"],
}
CLEAN = [
    # (headline, body, notes, add_shape)
    ("Workshop title", "", "[1 min] [title]\nWelcome everyone.", False),
    ("Your browser asks DNS where a name lives", "browser → resolver → IP",
     "[3 min] [content] [def DNS]\nThe resolver answers with an address.", True),
    ("Every request gets a response with a status", "GET /api → 200 OK",
     "[3 min] [content]\nPoint at the status code first.", True),
    ("Put these four steps in the right order", "name · resolver · IP · page",
     "[3 min] [activity] [O1]\nGive them two minutes in pairs.", True),
]


def build(slides, path, idx100=False, nav=False):
    prs = Presentation()
    layout = prs.slide_layouts[5]  # title only
    for head, body, notes, shape in slides:
        s = prs.slides.add_slide(layout)
        s.shapes.title.text = head
        if idx100:  # pptxgenjs writes its title placeholder at idx 100
            s.shapes.title.element.nvSpPr.nvPr.ph.set("idx", "100")
        if nav:  # navigation chips are named nav-* and carry no content words
            chip = s.shapes.add_textbox(Inches(9), Inches(0.2), Inches(1), Inches(0.3))
            chip.name = "nav-progress"
            chip.text_frame.text = " ".join(["1"] * 60)
        if body:
            tb = s.shapes.add_textbox(Inches(1), Inches(2), Inches(8), Inches(1))
            tb.text_frame.text = body
            tb.text_frame.paragraphs[0].runs[0].font.size = Pt(18)
        if shape:
            s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(1), Inches(4), Inches(2), Inches(1))
        s.notes_slide.notes_text_frame.text = notes
    prs.save(path)


def rules_for(slides, plan=PLAN, **kw):
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "deck.pptx")
        build(slides, p, **kw)
        findings, _, _ = lint_deck.lint(p, copy.deepcopy(plan))
    return {f["rule"] for f in findings}


def plant(i, field, value):
    s = [list(x) for x in CLEAN]
    s[i][field] = value
    return [tuple(x) for x in s]


CASES = [
    ("headline.topic-label", plant(1, 0, "DNS")),
    ("headline.period", plant(1, 0, "Your browser asks DNS where a name lives.")),
    ("body.words", plant(2, 1, " ".join(["word"] * 60))),
    ("slide.no-visual", plant(2, 3, False)),
    ("notes.timing", plant(2, 2, "[content]\nScript.")),
    ("notes.kind", plant(2, 2, "[3 min]\nScript.")),
    ("notes.script", plant(2, 2, "[3 min] [content]")),
    ("notes.reads-slide", plant(2, 2, "[3 min] [content]\nEvery request gets a response with a status, they said.")),
    ("outcome.untagged", plant(3, 2, "[3 min] [activity]\nPairs.")),
    ("outcome.no-check", plant(3, 2, "[3 min] [content]\nNo activity any more.")),
    ("glossary.undefined", plant(1, 2, "[3 min] [content]\nNo definition tag.")),
    ("glossary.used-before-defined", plant(0, 0, "A DNS workshop for everyone here")),
    ("timing.total", plant(2, 2, "[20 min] [content]\nLong.")),
]


def main():
    bad = 0
    clean = rules_for(CLEAN)
    if clean:
        print(f"FAIL clean deck raised {sorted(clean)}")
        bad += 1
    else:
        print("ok   clean deck passes")
    for rule, slides in CASES:
        got = rules_for(slides)
        if rule in got:
            print(f"ok   {rule}")
        else:
            print(f"FAIL {rule} not raised (got {sorted(got)})")
            bad += 1
    for kw in ({"idx100": True}, {"nav": True}):
        got = rules_for(CLEAN, **kw)
        print(("ok   " if not got else f"FAIL {sorted(got)} ") + f"clean deck with {kw} passes")
        bad += bool(got)
    gap_plan = dict(PLAN, duration_min=24)
    gap = CLEAN[:3] + [("Another long explanation slide here", "x → y",
                        "[8 min] [content]\nTalk.", True)] + CLEAN[3:]
    gap = [gap[0], gap[1], (gap[2][0], gap[2][1], "[8 min] [content]\nTalk.", True)] + gap[3:]
    got = rules_for(gap, gap_plan)
    print(("ok   " if "cadence.gap" in got else "FAIL ") + "cadence.gap")
    bad += "cadence.gap" not in got
    print(f"{len(CASES) + 4 - bad}/{len(CASES) + 4} cases behaved")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
