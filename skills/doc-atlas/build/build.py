"""Build an architecture atlas from archify specs and a description file.

    python3 build.py atlas.config.json          # build
    python3 build.py atlas.config.json --check  # build, then prove it in a browser

One command does the whole chain — lift the drawings out of archify's rendered pages,
namespace their IDs, check the descriptions against the specs, assemble the page. It
re-extracts every time on purpose: the drawings are a cache of `just diagrams` output, and
a cache refreshed only when somebody remembers is how a page ends up showing last week's
topology under this week's descriptions, with the drift gate seeing nothing, because that
gate compares descriptions against the SPEC and not against the drawing.

Config (see atlas.config.example.json):

    specs       directory holding <name>.json specs and <name>.html renderings
    describe    the description file, keyed diagram -> component id
    out         where to write the page
    title       the <title>, which is the artifact's name
    brand       [line one, line two] for the bar
    diagrams    name -> {spec, parts, edges, tab, blurb}
    repo        optional base URL; component `sources` become links under it
"""

import contextlib
import html
import json
import re
import socket
import subprocess
import sys
import threading
import time
from pathlib import Path

# NO BYTECODE CACHE BESIDE THIS FILE. Installed, atlas lives under
# ~/.claude/skills/doc-atlas/, which B8 hashes as an INSTRUCTION SURFACE — so the two
# .pyc files CPython would drop here for the imports below register as
# instruction-surface drift at the next SessionStart, and the operator is asked to
# review a change that is nothing but this script having run. Measured 2026-09-04:
# `pin-instructions.sh --check` reported 8 changed paths, 2 of them exactly these.
# (Measured under the old ~/.claude/plugins/cache/ path, before the tier was
# retired on 2026-09-06 — same B8 surface, same hazard, different directory.)
#
# build.py itself is never cached (a script run as __main__ is not), so this is
# placed before the only two imports that would be: atlas_css and namespace. The
# stdlib imports above cache into the stdlib's own tree, not this one.
#
# Set here rather than as `python3 -B` in SKILL.md: the flag in a prompt holds only
# while every future caller remembers to type it, and a plugin that dirties the
# floor when invoked the obvious way is a plugin that dirties the floor.
sys.dont_write_bytecode = True

import atlas_css
import namespace

# ---------------------------------------------------------------- lifting the drawing

def stylesheet(doc: str) -> str:
    blocks = re.findall(r"<style[^>]*>(.*?)</style>", doc, re.S)
    assert len(blocks) == 1, f"expected one stylesheet, found {len(blocks)}"
    return blocks[0]


def drawing(doc: str) -> str:
    opens = doc.count("<svg")
    assert opens == 1, f"expected one svg, found {opens}"
    i = doc.index("<svg")
    return doc[i : doc.index("</svg>", i) + len("</svg>")]


def rules(css: str) -> list[tuple[str, str]]:
    """Every top-level `selector { body }`. At-rules are dropped first, so the brace
    counting below cannot be thrown by a nested block."""
    css = re.sub(r"/\*.*?\*/", "", css, flags=re.S)
    css = re.sub(r"@(media|supports|keyframes)[^{]*\{(?:[^{}]|\{[^{}]*\})*\}", "", css, flags=re.S)
    return [
        (" ".join(m.group(1).split()), " ".join(m.group(2).split()))
        for m in re.finditer(r"([^{}]+)\{([^{}]*)\}", css)
    ]


def wanted(selector: str, present: set[str]) -> bool:
    """Keep a rule the drawing can match, drop the viewer chrome.

    A selector naming classes is kept only if the drawing has all of them. One naming no
    class at all is kept only when it targets the SVG or an element inside it — the source
    stylesheet is ~186 KB and almost every byte of it styles a toolbar that is not coming.
    """
    named = set(re.findall(r"\.([A-Za-z][\w-]*)", selector))
    if named:
        return named <= present and "html" not in selector
    return any(
        part in {"svg", "svg text", "text", "marker", "polygon"}
        for part in selector.replace(",", " ").split()
    )


def palettes(css: str) -> tuple[str, str]:
    """archify's two classic-preset token blocks, returned as (light, dark).

    `:root` is archify's DARK. The artifact theme contract wants light on bare `:root`, so
    the inversion happens here, once, rather than being rediscovered at every call site.
    """
    found = {}
    for selector, decl in rules(css):
        flat = selector.replace(" ", "")
        if flat in (':root,[data-theme="dark"]', '[data-theme="light"]') and "--" in decl:
            found[flat] = decl
    assert len(found) == 2, f"expected two palettes, found {sorted(found)}"
    return found['[data-theme="light"]'], found[':root,[data-theme="dark"]']


def extract(cfg: dict) -> dict:
    specs = Path(cfg["specs"]).expanduser()
    out, shared = {}, None
    for name in cfg["diagrams"]:
        doc = specs.joinpath(f"{name}.html").read_text(encoding="utf-8")
        css = stylesheet(doc)
        svg = drawing(doc)
        present = {c for value in re.findall(r'class="([^"]+)"', svg) for c in value.split()}
        keep = [(s, d) for s, d in rules(css) if wanted(s, present)]
        svg = namespace.apply(svg, name)
        namespace.check(svg, name)
        out[name] = {"svg": svg, "rules": keep}
        shared = shared or css
        print(f"  {name:12} svg {len(svg) / 1024:>5.1f} KB  rules kept {len(keep)}")
    light, dark = palettes(shared)
    return {"diagrams": out, "light": light, "dark": dark}


# ---------------------------------------------------------------- the gates

CEILING = {"kind": 4, "role": 12, "why": 26}
FACT_LABEL, FACT_VALUE, FACT_ROWS = 3, 8, 4
SOURCE_FILES = 6

# THE DATA LAYER. `facts` says what a component IS in prose; `fields` says which named
# columns, parameters or keys actually move through it. They are different questions and
# folding them loses the one a reader chases hardest — "which column is this?" — so the
# ceilings differ too: a field NAME is an identifier, not a phrase, and a NOTE earns more
# words than a fact value because it has to say what the column means, not what it holds.
FIELD_ROWS, FIELD_NAME, FIELD_TYPE, FIELD_NOTE = 12, 3, 3, 12

# THE EXPOSURE LAYER. `facts` says what a part IS and `fields` says what moves through it.
# Neither answers the question an audit reader asks second: WAS ANYONE LOOKING. A defect
# that put a wrong number on a scorecard and a defect that left a tile reading zero are
# not the same incident — the first was seen and disbelieved, the second was seen and
# BELIEVED — and a page that renders both as "affected" has thrown away the distinction
# that decides who has to be told. So the state is a closed enum rather than prose: five
# values a reader can scan down a column, not five sentences they have to compare.
#
#   visible  a wrong number was displayed, and somebody could have read it
#   silent   displayed, but as a zero or a blank that reads as legitimate
#   absent   no surface renders this at all, so the defect had nowhere to show
#   clean    displayed and correct; the control that makes the others provable
#   unknown  nobody can say from here, and saying so beats guessing
EXPOSURE_ROWS, EXPOSURE_SURFACE, EXPOSURE_NOTE = 8, 4, 12
EXPOSURE_STATES = ("visible", "silent", "absent", "clean", "unknown")


def check(name: str, cid: str, d: dict) -> None:
    for field, limit in CEILING.items():
        n = len(d[field].split())
        if n > limit:
            raise SystemExit(
                f"{name}.{cid}.{field}: {n} words, ceiling {limit} — "
                f"a panel read like prose is a panel skipped\n    {d[field]!r}"
            )
    if not 1 <= len(d["facts"]) <= FACT_ROWS:
        raise SystemExit(f"{name}.{cid}.facts: {len(d['facts'])} rows, want 1..{FACT_ROWS}")
    # Sources are paths, not prose. A sentence here would render as a broken link.
    sources = d.get("sources", [])
    if len(sources) > SOURCE_FILES:
        raise SystemExit(f"{name}.{cid}.sources: {len(sources)} files, want at most {SOURCE_FILES}")
    for src in sources:
        if " " in src.strip() or not src.strip():
            raise SystemExit(f"{name}.{cid}.sources: {src!r} is not a path")
    for label, value in d["facts"]:
        if len(label.split()) > FACT_LABEL or len(value.split()) > FACT_VALUE:
            raise SystemExit(
                f"{name}.{cid}.facts: {label!r} / {value!r} exceeds "
                f"{FACT_LABEL}-word label, {FACT_VALUE}-word value"
            )
    for field in ("kind", "role", "why"):
        plain(f"{name}.{cid}.{field}", d[field])
    links(f"{name}.{cid}", d.get("links", []))
    fields(f"{name}.{cid}", d.get("fields", []))
    exposure(f"{name}.{cid}", d.get("exposure", []))


def exposure(where: str, rows: list) -> None:
    """Refuse an exposure claim that cannot be scanned or cannot be checked.

    A row is [surface, state, note]. The SURFACE is where a person would have been
    looking, so it is held as tight as a field name; the STATE is a closed enum because
    the whole value of this block is that a reader can run down one column and separate
    "we showed them a wrong number" from "we showed them nothing"; the NOTE gets the most
    words because it is the only place the difference can be explained.

    Optional, and absent it changes nothing — every atlas written before this existed
    still builds. That is deliberate: a required field here would have made this skill
    refuse the four atlases it was derived from.
    """
    if not rows:
        return
    if len(rows) > EXPOSURE_ROWS:
        raise SystemExit(
            f"{where}.exposure: {len(rows)} rows, ceiling {EXPOSURE_ROWS} — past this it "
            f"is an inventory of surfaces, and the inventory belongs in the repo"
        )
    seen = set()
    for row in rows:
        if not isinstance(row, (list, tuple)) or len(row) != 3:
            raise SystemExit(
                f"{where}.exposure: {row!r} is not [surface, state, note] — a surface "
                f"with no state does not say whether anybody saw the defect"
            )
        surface, state, note = (str(x) for x in row)
        if not surface.strip():
            raise SystemExit(f"{where}.exposure: a row has no surface")
        if surface in seen:
            raise SystemExit(
                f"{where}.exposure: {surface!r} listed twice — one surface cannot be in "
                f"two states, and a reader would not know which one to believe"
            )
        seen.add(surface)
        if state not in EXPOSURE_STATES:
            raise SystemExit(
                f"{where}.exposure[{surface}]: state {state!r} is not one of "
                f"{', '.join(EXPOSURE_STATES)} — free text here would let 'affected' back "
                f"in, which is the word this block exists to replace"
            )
        for val, limit, what in (
            (surface, EXPOSURE_SURFACE, "surface"),
            (note, EXPOSURE_NOTE, "note"),
        ):
            n = len(val.split())
            if n > limit:
                raise SystemExit(
                    f"{where}.exposure[{surface}].{what}: {n} words, ceiling {limit}\n"
                    f"    {val!r}"
                )
        for val in (surface, state, note):
            plain(f"{where}.exposure[{surface}]", val)


def fields(where: str, rows: list) -> None:
    """Refuse a data layer that has stopped being scannable.

    A `fields` row is [name, type, note]. The name and type are identifiers, so they are
    held tighter than any prose field on the panel; the note is the only place that can
    explain a column and gets the most words. Every one of these reaches the page through
    textContent, so `<` is refused here exactly as it is in a fact or a finding.
    """
    if not rows:
        return
    if len(rows) > FIELD_ROWS:
        raise SystemExit(
            f"{where}.fields: {len(rows)} rows, ceiling {FIELD_ROWS} — a column list "
            f"longer than this is a schema dump, and belongs in the repo"
        )
    seen = set()
    for row in rows:
        if not isinstance(row, (list, tuple)) or len(row) != 3:
            raise SystemExit(
                f"{where}.fields: {row!r} is not [name, type, note] — three strings, "
                f"because a column with no type or no meaning is a column nobody can use"
            )
        fname, ftype, fnote = (str(x) for x in row)
        if not fname.strip():
            raise SystemExit(f"{where}.fields: a row has no name")
        if fname in seen:
            raise SystemExit(
                f"{where}.fields: {fname!r} listed twice — a duplicated column reads as "
                f"two different things carrying one name"
            )
        seen.add(fname)
        for val, limit, what in (
            (fname, FIELD_NAME, "name"),
            (ftype, FIELD_TYPE, "type"),
            (fnote, FIELD_NOTE, "note"),
        ):
            n = len(val.split())
            if n > limit:
                raise SystemExit(
                    f"{where}.fields[{fname}].{what}: {n} words, ceiling {limit}\n"
                    f"    {val!r}"
                )
        for val in (fname, ftype, fnote):
            plain(f"{where}.fields[{fname}]", val)


# Every one of these reaches the page through `textContent`, so markup in them renders as
# the literal characters. Measured 2026-09-03: a finding's `what` was rewritten with `<b>`
# around the dates and shipped a paragraph reading `<b>one fourteen-day window</b>` to the
# reader, through a build that reported success and a --check suite that passed. Nothing in
# either could see it, because both ask whether an element EXISTS, never what it says.
PLAIN = ("what", "label", "cost", "owner", "fix", "ticket", "keysTitle")
WHAT_WORDS = 60

# WHY A FINDING CANNOT SHIP WITHOUT A GRADE AND A BASIS. An audit grades its findings —
# re-measured, narrowed, one-lane-only — and a page that drops the grade renders a lead
# and a confirmed fact at identical weight. Measured on a client atlas, 2026-09-04: three
# findings the audit marks "one lane only. Treat as a lead, not a fact" were rendered
# indistinguishably from the fifteen a critic had re-measured. The reader has no way back
# to that distinction, so it has to survive the build or it does not survive at all.
#
# `basis` is the second half and the one the audit itself calls decisive: configuration
# and traffic disagreed four times in that audit and traffic won every time. A claim read
# out of a config file is a different kind of claim from one seen on the wire.
STATUS = {
    "confirmed": "a critic re-measured it independently and it held",
    "understated": "real, and worse than first written",
    "overstated": "real, but narrower than first written — corrected here",
    "reframed": "real, but a different finding than first written",
    "lead": "ONE LANE ONLY — treat as a lead, not a fact",
}
BASIS = {
    "traffic": "observed on the wire",
    "query": "measured by query against the warehouse",
    "configuration": "read from configuration, not from traffic",
}
# WHAT THE EVIDENCE IS AND WHEN IT WAS TAKEN ARE TWO FIELDS, not one. Folding them into a
# single "inherited" value loses the kind — and the kind is what the audit says decides
# ties: configuration and traffic disagreed four times and traffic won every one. So the
# staleness is derived from this date instead, against the newest date on the page, which
# means nobody has to remember to relabel anything when a finding is re-measured.
ISO = re.compile(r"^20[0-9][0-9]-[01][0-9]-[0-3][0-9]$")

# A TAB NAME IS THREE THINGS AT ONCE, and only one of them is HTML. It is an attribute
# value, a URL fragment, and — in atlas.js `canvas()` and `plate()` — a CSS selector built
# by string concatenation: '.plate[data-name="' + name + '"]'. So escaping it is necessary
# and NOT sufficient: `e()` makes the markup well-formed, and a backslash still escapes to
# nothing inside a CSS string, `canvas()` returns null, and the whole IIFE dies at the
# first querySelectorAll — BEFORE tabs, search, theme, zoom, hash and findings are wired.
# Measured 2026-09-05 on a key of `bad\name`: the page rendered perfectly and did nothing,
# console-only, at exit 0. A `"` was caught, but by accident, and reported as
# `duplicate ids within one svg` — a message naming neither the cause nor the field.
#
# Hence a shape gate rather than only an escape. The vocabulary is what survives all three
# roles unchanged, which is also what a URL fragment can carry without encoding.
IDENT = re.compile(r"^[A-Za-z0-9_-]+$")


def ident(where: str, value: str) -> None:
    """Refuse a tab name that cannot be an attribute, a fragment and a CSS string at once."""
    if not IDENT.match(value or ""):
        raise SystemExit(
            f"{where}: {value!r} is not a usable tab name — a tab name is an attribute "
            f"value, a URL fragment AND a CSS selector string, so it must be letters, "
            f"digits, hyphen or underscore only"
        )


def plain(where: str, value: str) -> None:
    if "<" in value:
        raise SystemExit(
            f"{where}: contains '<'. This field renders as text, so markup arrives as "
            f"characters — put emphasis in a table row or a key, not in the prose.\n"
            f"    {value!r}"
        )


def finding_fields(fid: str, f: dict) -> None:
    """A finding is a claim plus the means to check it. The claim is capped so it cannot
    grow back into an essay; the means — the columns, the numbers, the links — are
    structured, because structure is what survives being skimmed."""
    for k in PLAIN:
        if f.get(k):
            plain(f"{fid}.{k}", f[k])
    st = f.get("status")
    if st not in STATUS:
        raise SystemExit(
            f"{fid}.status: {st!r} — a finding ships with its grade or not at all. "
            f"One of: {', '.join(sorted(STATUS))}"
        )
    ba = f.get("basis")
    if ba not in BASIS:
        raise SystemExit(
            f"{fid}.basis: {ba!r} — say what the claim rests on. "
            f"One of: {', '.join(sorted(BASIS))}"
        )
    if not ISO.match(f.get("measured") or ""):
        raise SystemExit(
            f"{fid}.measured: {f.get('measured')!r} — a claim with no date is a claim "
            f"with no shelf life. ISO, e.g. 2026-09-04"
        )
    n = len((f.get("what") or "").split())
    if n > WHAT_WORDS:
        raise SystemExit(
            f"{fid}.what: {n} words, ceiling {WHAT_WORDS} — a finding panel is read "
            f"standing up. Move the detail into `tables`, `keys` or `open`."
        )
    for i, (a, b) in enumerate(f.get("keys", [])):
        plain(f"{fid}.keys[{i}]", f"{a} {b}")
    for t in f.get("tables", []):
        # THE TITLE IS READER-FACING TEXT and was the only string in a finding that reached
        # the page without passing here — it is used below purely as an ERROR LABEL, which
        # reads like validation and is not. Measured 2026-09-05: a title of `<!--<script>`
        # defeated the payload's `</` escape (the tokenizer enters double-escaped state and
        # the real </script> stops closing), so the page shipped with ONE script element
        # instead of two — no inspector, no tabs, no search, no console error, exit 0.
        plain(f"{fid}.tables.title", t.get("title", ""))
        cols = t.get("cols", [])
        for r in t.get("rows", []):
            cells = r["cells"] if isinstance(r, dict) else r
            if cols and len(cells) != len(cols):
                raise SystemExit(
                    f"{fid}.tables[{t.get('title','?')!r}]: row has {len(cells)} cells, "
                    f"header has {len(cols)} — a table whose columns do not line up is "
                    f"worse than no table"
                )
            for c in cells:
                plain(f"{fid}.tables.{t.get('title','?')}", str(c))
        plain(f"{fid}.tables.note", t.get("note", ""))
    links(fid, f.get("open", []))


def links(where: str, items: list) -> None:
    """A link is the difference between an audit a reader can check and one they have to
    believe. An unopenable one is worse than none, so the scheme is checked here rather
    than discovered by the reader."""
    for i, o in enumerate(items):
        if not o.get("label"):
            raise SystemExit(f"{where}.open[{i}]: no label — a bare URL says nothing")
        href = o.get("href", "")
        if href and not href.startswith(("https://", "http://")):
            raise SystemExit(f"{where}.open[{i}]: {href!r} is not an http(s) URL")
        plain(f"{where}.open[{i}]", f"{o['label']} {o.get('note', '')}")


def assemble(cfg: dict, drawings: dict) -> dict:
    specs = Path(cfg["specs"]).expanduser()
    authored = json.loads(Path(cfg["describe"]).read_text(encoding="utf-8"))
    data = {"order": list(cfg["diagrams"]), "diagrams": {}}

    for name, d in cfg["diagrams"].items():
        spec = json.loads(specs.joinpath(d["spec"]).read_text(encoding="utf-8"))
        parts, edges = spec[d["parts"]], spec.get(d["edges"], [])
        label = {p["id"]: p["label"] for p in parts}
        described = authored[name]

        # Keys beginning with "_" are reserved for authored metadata that is NOT a
        # component — `_edges` carries the data layer for relationships. Without this
        # exemption the drift gate reads it as a description of a node that does not
        # exist, which is exactly the error it was built to catch, aimed at itself.
        ids = {p["id"] for p in parts}
        given = {k for k in described if not k.startswith("_")}
        if ids != given:
            raise SystemExit(
                f"{name}: description drift — undescribed {sorted(ids - given)}, "
                f"describing nothing {sorted(given - ids)}"
            )

        # AN EDGE WITH NO id IS AN EDGE NOBODY CAN CLICK, and this used to be a silent
        # fallback to `{from}~{to}~{i}`. archify emits `data-edge-id` ONLY for an edge
        # that declares one, and both atlas.js and check.mjs select edges by exactly that
        # attribute — so a synthesized id matches nothing in the drawing and the panel
        # never opens. Measured 2026-09-03: a four-diagram atlas built clean and reported
        # every count correctly while 0 of its 34 edges were reachable; --check caught it,
        # the build did not. A fallback whose only outcome is a broken page is not a
        # fallback, so the build now names the edge and stops.
        missing = [f"{e['from']} -> {e['to']}" for e in edges if not e.get("id")]
        if missing:
            raise SystemExit(
                f"{name}: {len(missing)} edge(s) declare no id, so archify emits no "
                f"data-edge-id and the atlas cannot select them:\n    "
                + "\n    ".join(missing[:8])
                + f"\n  Give each flow/connection/message an \"id\" in {d['spec']}."
            )

        # THE EDGE DATA LAYER, checked against the SPEC exactly like a node description.
        # An entry naming an edge the drawing no longer has would render nothing and read
        # as "this relationship carries no columns", which is the same expensive wrong
        # answer a dangling finding gives.
        edge_ids = {e["id"] for e in edges}
        edge_desc = described.get("_edges", {})
        stray = sorted(set(edge_desc) - edge_ids)
        if stray:
            raise SystemExit(
                f"{name}._edges: {stray} name no edge in {d['spec']} — "
                f"declared edges are {sorted(edge_ids)}"
            )
        edge_fields = {}
        for eid, ed in edge_desc.items():
            if not isinstance(ed, dict) or "fields" not in ed:
                raise SystemExit(f"{name}._edges.{eid}: want {{\"fields\": [[name, type, note], ...]}}")
            fields(f"{name}._edges.{eid}", ed["fields"])
            edge_fields[eid] = ed["fields"]

        nodes = {}
        for p in parts:
            desc = described[p["id"]]
            check(name, p["id"], desc)
            carries = [
                ["out", label[e["to"]], e.get("label", ""), e["id"], len(edge_fields.get(e["id"], []))]
                if e["from"] == p["id"]
                else ["in", label[e["from"]], e.get("label", ""), e["id"], len(edge_fields.get(e["id"], []))]
                for e in edges
                if p["id"] in (e["from"], e["to"])
            ]
            nodes[p["id"]] = {
                "label": p["label"],
                "sub": " · ".join(x for x in (p.get("sublabel"), p.get("tag")) if x),
                "type": p.get("type", ""),
                **{k: desc[k] for k in ("kind", "role", "facts", "why")},
                "sources": desc.get("sources", []),
                "links": desc.get("links", []),
                "fields": desc.get("fields", []),
                "exposure": desc.get("exposure", []),
                "carries": carries,
            }

        data["diagrams"][name] = {
            "tab": d["tab"],
            "blurb": d["blurb"],
            # The panel can open on a relationship as well as a box, so the edges travel
            # with their endpoints already resolved to labels — the page should never have
            # to re-derive what the spec already states.
            "wires": [
                {
                    "id": e["id"],
                    "from": e["from"],
                    "to": e["to"],
                    "fromLabel": label[e["from"]],
                    "toLabel": label[e["to"]],
                    "label": e.get("label", ""),
                    "note": e.get("classification", ""),
                    "variant": e.get("variant", ""),
                    "fields": edge_fields.get(e["id"], []),
                }
                for i, e in enumerate(edges)
            ],
            "title": spec["meta"]["title"],
            "svg": drawings["diagrams"][name]["svg"],
            "rules": drawings["diagrams"][name]["rules"],
            "views": [
                {
                    "label": v["label"],
                    "note": v.get("note", ""),
                    "focus": [label.get(f, f) for f in v["focus"]],
                    "ids": v["focus"],
                }
                for v in spec["meta"].get("views", [])
            ],
            "cards": spec.get("cards", []),
            "nodes": nodes,
            "edges": len(edges),
        }
    # The same component appears in several diagrams under the same label — warehouse-mcp
    # is in three. Matching on LABEL rather than id is deliberate: ids are per-spec and
    # already differ (`warehouse` is the resource server in one diagram and the whole
    # service in another), while the label is what the author asserted is the same thing.
    where = {}
    for name, g in data["diagrams"].items():
        for cid, n in g["nodes"].items():
            where.setdefault(n["label"], []).append([name, cid])
    for name, g in data["diagrams"].items():
        for cid, n in g["nodes"].items():
            n["also"] = [w for w in where[n["label"]] if w[0] != name]

    inside_views(cfg, data)

    # One flat index for search, built once here rather than walked on every keystroke.
    data["index"] = [
        {
            "d": name,
            "id": cid,
            "label": n["label"],
            "hay": " ".join([n["label"], n["sub"], n["kind"], n["role"], g["tab"]]).lower(),
            "kind": n["kind"],
            "tab": g["tab"],
        }
        for name, g in data["diagrams"].items()
        for cid, n in g["nodes"].items()
    ]

    # ---------------------------------------------------------------- findings
    # AN ATLAS OF A BROKEN SYSTEM HAS A SECOND SUBJECT. The drawing says what the system
    # IS; a reader handed one during an audit is asking where it FAILS, and that question
    # is answered by a PATH — some nodes and the arrows between them — not by a box. The
    # guided `views` in a spec are the closest existing thing and they cap at five per
    # diagram, are per-diagram, and carry no severity, so a nineteen-finding audit does
    # not fit in them.
    #
    # The ids are checked against the SPEC, not against the drawing, for the same reason
    # the description gate is: a finding naming a node that no longer exists would light
    # nothing and read as "not a problem any more", which is the most expensive wrong
    # answer this page can give.
    findings = cfg.get("findings", [])
    seen_fid = set()
    for f in findings:
        fid = f.get("id", "")
        if not fid or fid in seen_fid:
            raise SystemExit(f"findings: {fid!r} is missing or repeated — ids address a finding")
        seen_fid.add(fid)
        g = data["diagrams"].get(f.get("diagram"))
        if g is None:
            raise SystemExit(f"{fid}: diagram {f.get('diagram')!r} is not in this atlas")
        unknown = [n for n in f.get("nodes", []) if n not in g["nodes"]]
        if unknown:
            raise SystemExit(f"{fid}: names node(s) {unknown} that {f['diagram']} does not have")
        wire_ids = {w["id"] for w in g["wires"]}
        unknown = [x for x in f.get("edges", []) if x not in wire_ids]
        if unknown:
            raise SystemExit(f"{fid}: names edge(s) {unknown} that {f['diagram']} does not have")
        if not f.get("nodes") and not f.get("edges"):
            raise SystemExit(f"{fid}: lights nothing — a finding with no path is a sentence, not a finding")
        # A FINDING BELONGS TO ONE DRAWING AND USUALLY APPEARS ON ANOTHER. The detailed
        # diagram is where a fault is explained; a whole-estate map is where a reader
        # first meets it. Before `also`, adding an overview diagram left every finding
        # pointing at the detail views and none at the map — measured on a client atlas,
        # 2026-09-04: a 23-node pipeline map that not one of 22 findings could light, so
        # the states on it were a picture the evidence could not be reached from.
        for other, ids in (f.get("also") or {}).items():
            og = data["diagrams"].get(other)
            if og is None:
                raise SystemExit(f"{fid}.also: diagram {other!r} is not in this atlas")
            if other == f["diagram"]:
                raise SystemExit(
                    f"{fid}.also names {other!r}, which is its own diagram — put those "
                    f"ids in `nodes`/`edges` instead"
                )
            known = set(og["nodes"]) | {w["id"] for w in og["wires"]}
            unknown = [x for x in ids if x not in known]
            if unknown:
                raise SystemExit(f"{fid}.also[{other}]: names {unknown}, which {other} does not have")
            if not ids:
                raise SystemExit(f"{fid}.also[{other}]: empty — drop the key rather than declare nothing")
        finding_fields(fid, f)
    data["findings"] = findings
    data["diagnostics"] = diagnose(findings, data["diagrams"], cfg.get("blocked", []))

    # ---------------------------------------------------------------- the brief
    # WHY PROSE EARNS A TAB HERE, HAVING BEEN REFUSED EVERYWHERE ELSE. This skill's first
    # rule is that prose on the first screen means the page is a document and has failed.
    #
    # THIS COMMENT SAID "the brief is the LAST tab and never the default" AND WAS WRONG —
    # the emitter puts briefs ahead of the drawings and marks the first one selected, on
    # the reasoning set out where that happens. The stale half is not free: check.mjs read
    # it, assumed `[role=tab][0]` was a drawing, dereferenced a `.canvas` the brief plate
    # does not have, and failed the whole suite on every atlas that has findings. What
    # changed
    # is that the drawing answers "where" and cannot answer "what it means" — so the two
    # halves were living in two files, and a reader had to hold one open beside the other.
    # A brief item carries a finding id, so reading the explanation and seeing the path
    # light up are one click apart rather than two documents apart.
    # ONE ATLAS, MORE THAN ONE READER. `briefs` is a list because the same findings have to
    # be told twice: once to somebody who does not have our file paths, our probe commands
    # or our access, and once to somebody who wants exactly those. Writing one document and
    # asking the first reader to skip the parts that are not for them does not work — they
    # cannot tell which those are, and a reference they cannot follow reads as a reference
    # they are not trusted with. `brief` (singular) still works and becomes a list of one.
    briefs = cfg.get("briefs") or ([cfg["brief"]] if cfg.get("brief") else [])
    if briefs:
        known = {f["id"] for f in findings}
        seen_ids = set()
        for n, b in enumerate(briefs):
            bid = b.get("id") or ("brief" if n == 0 else f"brief{n + 1}")
            # Same three roles as a diagram key, and the same gate. Before it, an id of
            # `b" onfocus=alert(1) autofocus data-x="` built clean and produced a <button>
            # with a real onfocus handler and autofocus — script on load — while the only
            # check on this value was the collision test immediately below.
            ident(f"briefs[{n}].id", bid)
            if bid in seen_ids or bid in data["diagrams"] or bid == "gaps":
                raise SystemExit(
                    f"briefs[{n}].id {bid!r} collides with another tab — every tab is a "
                    f"URL fragment and a stored preference, so two cannot share a name"
                )
            seen_ids.add(bid)
            b["id"] = bid
            # A SECTION IS NUMBERED SO IT CAN BE CITED. An audit gets discussed in a room
            # where nobody is looking at the same screen, and "section 4" survives that
            # conversation while "the bit about the join" does not.
            for i, sec in enumerate(b.get("sections", []), 1):
                sec.setdefault("n", i)
                for it in sec.get("items", []):
                    fid = it.get("finding")
                    if fid and fid not in known:
                        raise SystemExit(
                            f"briefs[{n}]: item {it.get('h','?')!r} points at finding "
                            f"{fid!r}, which this atlas does not carry"
                        )
        data["briefs"] = briefs

    data["palette"] = {"light": drawings["light"], "dark": drawings["dark"]}
    if cfg.get("repo"):
        data["repo"] = cfg["repo"]
    return data


# ---------------------------------------------------------------- the page

SCRIPT = (Path(__file__).parent / "atlas.js").read_text(encoding="utf-8")


def e(t: str) -> str:
    return html.escape(str(t), quote=True)


# ---------------------------------------------------------------- what the page cannot say
# DERIVED, NEVER AUTHORED. A hand-written "what we did not cover" is a copy of a fact that
# lives in the findings list, and copies drift silently while still reading correctly — the
# client atlas shipped one claiming five open questions where its source carried eight. Every
# number below is counted from the findings at build time, so it cannot be stale and cannot
# be flattering. The only authored part is `blocked`: what nobody could measure is not
# derivable from what somebody did.


def diagnose(findings: list, diagrams: dict, blocked: list) -> dict:
    leads = [f["id"] for f in findings if f.get("status") == "lead"]
    fresh = max((f.get("measured", "") for f in findings), default="")
    stale = sorted(
        {f.get("measured") for f in findings if f.get("measured") and f["measured"] < fresh}
    )
    inherited = [f["id"] for f in findings if f.get("measured", "") < fresh]
    config_only = [f["id"] for f in findings if f.get("basis") == "configuration"]
    no_numbers = [f["id"] for f in findings if not f.get("tables")]
    no_probe = [f["id"] for f in findings if not f.get("open")]

    # A drawing whose boxes no finding names is not a defect — most of an estate is
    # working. It IS the honest answer to "what did you look at and find nothing wrong
    # with", which is the half of an audit nobody writes down.
    touched = {}
    for f in findings:
        touched.setdefault(f["diagram"], set()).update(f.get("nodes", []))
        # A node a finding reaches through `also` is covered. Counting only the home
        # diagram would report an overview map as entirely unexamined while every part
        # of it is named by a finding somewhere.
        for other, ids in (f.get("also") or {}).items():
            touched.setdefault(other, set()).update(ids)
    unnamed = {}
    for name, g in diagrams.items():
        hit = touched.get(name, set())
        rest = [g["nodes"][n]["label"] for n in g["nodes"] if n not in hit]
        if rest:
            unnamed[g["tab"]] = rest

    for i, b in enumerate(blocked):
        for k in ("what", "probe", "owner"):
            if not b.get(k):
                raise SystemExit(
                    f"blocked[{i}]: no {k!r}. A limit stated without the probe that would "
                    f"settle it and the person who can run it is an excuse, not a finding."
                )
            plain(f"blocked[{i}].{k}", b[k])

    return {
        "total": len(findings),
        "fresh": fresh,
        "stale": stale,
        "leads": leads,
        "inherited": inherited,
        "config_only": config_only,
        "no_numbers": no_numbers,
        "no_probe": no_probe,
        "unnamed": unnamed,
        "blocked": blocked,
    }


def diagnostics_html(d: dict) -> str:
    def ids(xs):
        return ", ".join(f"<code>{e(x)}</code>" for x in xs) if xs else "&mdash;"

    rows = [
        ("Findings on this page", str(d["total"]), "&mdash;"),
        ("Rest on one lane, never independently re-measured", str(len(d["leads"])), ids(d["leads"])),
        (f"Last measured before {e(d['fresh'])} &mdash; carried forward, not re-checked "
         f"for this build ({e(', '.join(d['stale'])) or '&mdash;'})",
         str(len(d["inherited"])), ids(d["inherited"])),
        ("Read from configuration rather than observed traffic",
         str(len(d["config_only"])), ids(d["config_only"])),
        ("Carry no table of numbers", str(len(d["no_numbers"])), ids(d["no_numbers"])),
        ("Carry no link a reader can open and check", str(len(d["no_probe"])), ids(d["no_probe"])),
    ]
    out = [
        "<h1>What this page cannot tell you</h1>",
        '<p class="stand">Counted from the findings themselves each time this page is '
        "built, so it cannot fall behind them. A page that states only what it found "
        "invites the reader to assume the rest was checked.</p>",
        '<h2 class="t-open">How much of this is measured</h2>',
        "<table><thead><tr><th>Confidence</th><th>Count</th><th>Which</th></tr></thead><tbody>",
    ]
    for label, n, which in rows:
        out.append(f"<tr><td>{label}</td><td>{n}</td><td>{which}</td></tr>")
    out.append("</tbody></table>")

    if d["blocked"]:
        out.append('<h2 class="t-open">What nobody could measure</h2>')
        out.append(
            '<p class="intro">Each row names the one probe that settles it and who can '
            "run it. A limit with no probe beside it is an excuse.</p>"
        )
        out.append(
            "<table><thead><tr><th>Blocked</th><th>One probe that settles it</th>"
            "<th>Who</th></tr></thead><tbody>"
        )
        for b in d["blocked"]:
            out.append(
                f"<tr><td>{e(b['what'])}</td><td>{e(b['probe'])}</td>"
                f"<td>{e(b['owner'])}</td></tr>"
            )
        out.append("</tbody></table>")

    if d["unnamed"]:
        out.append('<h2 class="t-good">Looked at, nothing found</h2>')
        out.append(
            '<p class="intro">Parts of the drawings that no finding points at. Not a '
            "clean bill of health — it is what the audit walked past without raising "
            "anything, which is worth knowing before somebody assumes it was never "
            "opened.</p>"
        )
        out.append("<table><thead><tr><th>View</th><th>Parts</th></tr></thead><tbody>")
        for tab, parts in d["unnamed"].items():
            out.append(f"<tr><td>{e(tab)}</td><td>{e(', '.join(parts))}</td></tr>")
        out.append("</tbody></table>")
    return "".join(out)


# ---------------------------------------------------------------- the text beside the picture
# A DIAGRAM IS THE ONLY ARTEFACT WHOSE DEFECTS ARE INVISIBLE IN ITS OWN OUTPUT. Every
# renderer defect this box has recorded was found by a person opening a picture and
# noticing an absence — two feeds merged into one box, thirty-four edges carrying no id, a
# chunk with no pipeline in it. None could be caught automatically, because the only
# description of what SHOULD have been drawn lived in the drawing.
#
# So the companion is written from the same `data` the page is built from, and the drawn
# connectivity is compared against the declared connectivity in BOTH directions: declared
# but not drawn is an omission, drawn but not declared is an invention with no source, and
# the second is worse. contracts/reports.md, property 6.

DRAWN_NODE = re.compile(r'data-node-id="([^"]+)"')
DRAWN_EDGE = re.compile(r'data-edge-id="([^"]+)"')


def connectivity(data: dict) -> list[str]:
    problems = []
    for name, g in data["diagrams"].items():
        drawn_n = set(DRAWN_NODE.findall(g["svg"]))
        drawn_e = set(DRAWN_EDGE.findall(g["svg"]))
        said_n = set(g["nodes"])
        said_e = {w["id"] for w in g["wires"]}
        for kind, said, drawn in (("part", said_n, drawn_n), ("connection", said_e, drawn_e)):
            for missing in sorted(said - drawn):
                problems.append(f"{name}: {kind} {missing!r} is declared and NOT DRAWN")
            for extra in sorted(drawn - said):
                problems.append(f"{name}: {kind} {extra!r} is DRAWN AND NOT DECLARED")
    return problems


def companion(cfg: dict, data: dict) -> str:
    d = data["diagnostics"]
    L = [
        f"# {cfg['title']} — the text beside the drawings",
        "",
        f"Generated by `build.py` from `{cfg['describe']}` and the specs in "
        f"`{cfg['specs']}`. Written **before** the page is rendered, so it survives a "
        f"renderer that refuses, and derived from the same parse, so it cannot drift "
        f"into a second hand-kept copy.",
        "",
        f"**As of {d['fresh']}.** The page is `{cfg['out']}`; when the two disagree, "
        f"this file was written first and the page is the projection.",
        "",
        "## What this does not cover",
        "",
        "Everything on the drawings is listed below. Nothing else in the estate is — a "
        "part with no box here was not examined and is not cleared. The blocked table at "
        "the end names what nobody could measure at all.",
        "",
        "## The drawings",
        "",
    ]
    for name, g in data["diagrams"].items():
        L += [f"### {g['tab']} (`{name}`) — {g['blurb']}", "",
              "| part | id | what it is | role |", "|---|---|---|---|"]
        for nid, n in g["nodes"].items():
            L.append(f"| {n['label']} | `{nid}` | {n['kind']} | {n['role']} |")
        L += ["", "| connection | from | to | carries |", "|---|---|---|---|"]
        for w in g["wires"]:
            L.append(f"| `{w['id']}` | {w.get('from','')} | {w.get('to','')} | "
                     f"{w.get('label','') or '—'} |")
        L.append("")

    L += ["## Findings", "",
          "| id | severity | grade | rests on | measured | on which drawing | claim |",
          "|---|---|---|---|---|---|---|"]
    for f in data["findings"]:
        L.append(
            f"| `{f['id']}` | {f['severity']} | {f['status']} | {f['basis']} | "
            f"{f['measured']} | {f['diagram']} | {f['label']} |"
        )
    L += ["", "## Confidence, counted from the findings above", "",
          "| | count | which |", "|---|---|---|",
          f"| on this page | {d['total']} | — |",
          f"| one lane only | {len(d['leads'])} | {', '.join(d['leads']) or '—'} |",
          f"| not re-measured for this build | {len(d['inherited'])} | "
          f"{', '.join(d['inherited']) or '—'} |",
          f"| configuration, not traffic | {len(d['config_only'])} | "
          f"{', '.join(d['config_only']) or '—'} |",
          f"| no table of numbers | {len(d['no_numbers'])} | "
          f"{', '.join(d['no_numbers']) or '—'} |",
          f"| no link to check | {len(d['no_probe'])} | {', '.join(d['no_probe']) or '—'} |",
          ""]
    if d["blocked"]:
        L += ["## What nobody could measure", "",
              "| blocked | one probe that settles it | who |", "|---|---|---|"]
        for b in d["blocked"]:
            L.append(f"| {b['what']} | {b['probe']} | {b['owner']} |")
        L.append("")
    return "\n".join(L)


TONE = {"good": "t-good", "bad": "t-bad", "open": "t-open", "": ""}


def brief_html(b: dict) -> str:
    """Authored sections into markup. Three shapes only — a lede, a list, a table — because
    a fourth would be an invitation to rebuild the whole document here, and the drawing is
    still the subject."""
    out = []
    if b.get("title"):
        out.append(f"<h1>{e(b['title'])}</h1>")
    if b.get("standfirst"):
        out.append(f'<p class="stand">{b["standfirst"]}</p>')
    for sec in b.get("sections", []):
        # ESCAPED ONCE, HERE, because this value lands in four places — an id attribute, a
        # styled span, and both halves of the item ref below. assemble() normally fills it
        # with `setdefault("n", i)`, so it is usually an int; an author MAY supply it, and
        # nothing checks what they supply. Measured 2026-09-05: a value of
        # `1"><script>alert(2)</script><span class="` put four executing <script> elements
        # inside .prose and fired four dialogs in Chrome — while sec["title"] and it["h"],
        # interpolated on the very same lines, were escaped correctly.
        sn = e(str(sec["n"])) if sec.get("n") else ""
        if sec.get("title"):
            # The number is markup, not text in the title, so it can be styled as a
            # reference mark and so a title never carries a number that drifts from
            # its position after a section is inserted above it.
            num = f'<span class="secn">{sn}</span>' if sn else ""
            out.append(
                f'<h2 id="s{sn}" class="{TONE.get(sec.get("tone", ""), "")}">'
                f'{num}{e(sec["title"])}</h2>'
            )
        if sec.get("intro"):
            out.append(f'<p class="intro">{sec["intro"]}</p>')
        if sec.get("body"):
            out.append(sec["body"])
        if sec.get("cols"):
            head = "".join(f"<th>{e(c)}</th>" for c in sec["cols"])
            body = "".join(
                "<tr>" + "".join(f"<td>{c}</td>" for c in row) + "</tr>" for row in sec.get("rows", [])
            )
            out.append(f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>")
        for j, it in enumerate(sec.get("items", []), 1):
            tone = TONE.get(it.get("tone", sec.get("tone", "")), "")
            fid = it.get("finding")
            # The link is the whole point of putting this in the atlas rather than a doc.
            jump = (
                f'<button class="tofind" type="button" data-finding="{e(fid)}">'
                f"Show me on the diagram &#8594;</button>"
                if fid else ""
            )
            # 4.2 rather than a bare bullet, and the finding id beside it. Two different
            # references because they answer two different questions: where this sits in
            # THIS document, and which finding on the drawings it is about.
            ref = f"{sn}.{j}" if sn else str(j)
            tag = f'<span class="itemf">{e(fid)}</span>' if fid else ""
            out.append(
                f'<div class="item {tone}" id="i{ref}">'
                f'<h3><span class="itemn">{ref}</span>{e(it["h"])}{tag}</h3>'
                f'<div class="p">{it["p"]}</div>{jump}</div>'
            )
    return "".join(out)


def page(cfg: dict, data: dict) -> str:
    seen, css_rules = set(), []
    for g in data["diagrams"].values():
        for sel, decl in g["rules"]:
            if (sel, decl) not in seen:
                seen.add((sel, decl))
                css_rules.append(f"{sel}{{{decl}}}")

    tabs, plates = [], []

    # THE DOCUMENT TAB COMES FIRST, and this reverses the rule the brief was added under.
    # That rule — prose on the first screen means the page is a document and has failed —
    # is right for an atlas somebody navigates repeatedly and wrong for an audit somebody
    # reads once: a reader who lands on a drawing they have never seen has to reconstruct
    # what it means before they can use it, and the brief is the only thing on the page
    # that answers "what am I looking at". The cost is one extra click for a returning
    # reader, and the brief's own "Show me on the diagram" buttons pay it back.
    for n, b in enumerate(data.get("briefs", [])):
        # e() as well as the ident() gate in assemble(). The gate is what CLOSES the defect;
        # this is so the markup assembly has one rule with no exceptions, because the four
        # injections found on 2026-09-05 were all in the third of these f-strings that had
        # quietly grown without it while their neighbours were escaped.
        bid, first = e(b["id"]), n == 0
        tabs.append(
            f'<button role="tab" id="tab-{bid}" data-name="{bid}" data-brief="1" '
            f'aria-controls="plate-{bid}" aria-selected="{"true" if first else "false"}" '
            f'tabindex="{0 if first else -1}">'
            f'<b>{e(b.get("tab", "Explained"))}</b><i>{e(b.get("blurb", ""))}</i></button>'
        )
        # A brief is authored HTML, so it is rendered into the markup rather than shipped
        # in the payload and built by script: it must be readable, selectable and printable
        # even if the script never runs.
        plates.append(
            f'<div class="plate brief{" on" if first else ""}" id="plate-{bid}" '
            f'data-name="{bid}" role="tabpanel" aria-labelledby="tab-{bid}">'
            f'<div class="prose">' + brief_html(b) + "</div></div>"
        )

    lead = bool(data.get("briefs"))
    for i, name in enumerate(data["order"]):
        g = data["diagrams"][name]
        on = i == 0 and not lead
        nm = e(name)   # see the note on bid above; ident() is the gate, this is the discipline
        sub = ' class="sub"' if g.get("parent") else ""
        tabs.append(
            f'<button role="tab"{sub} id="tab-{nm}" data-name="{nm}" '
            f'aria-controls="plate-{nm}" aria-selected="{"true" if on else "false"}" '
            f'tabindex="{0 if on else -1}">'
            f'<b>{e(g["tab"])}</b><i>{e(g["blurb"])}</i></button>'
        )
        plates.append(
            f'<div class="plate{" on" if on else ""}" id="plate-{nm}" '
            f'data-name="{nm}" role="tabpanel" aria-labelledby="tab-{nm}">'
            f'<div class="canvas">{g["svg"]}</div>'
            f'<div class="zoombar" role="group" aria-label="Zoom">'
            f'<button class="zout" type="button" aria-label="Zoom out" title="Zoom out ( - )">&#8722;</button>'
            f'<span class="level" aria-live="off">100%</span>'
            f'<button class="zin" type="button" aria-label="Zoom in" title="Zoom in ( + )">+</button>'
            f'<button class="zfit" type="button" aria-label="Fit the diagram" title="Fit ( 0 )">&#8862;</button>'
            f"</div></div>"
        )

    # Diagnostics go last, after the drawings, because they are what the page is NOT
    # telling you and that only means something once you have seen what it is.
    diag = data.get("diagnostics")
    if diag:
        tabs.append(
            '<button role="tab" id="tab-gaps" data-name="gaps" data-brief="1" '
            'aria-controls="plate-gaps" aria-selected="false" tabindex="-1">'
            "<b>What we cannot see</b><i>Confidence, blind spots, and who can lift them"
            "</i></button>"
        )
        plates.append(
            '<div class="plate brief" id="plate-gaps" data-name="gaps" role="tabpanel" '
            'aria-labelledby="tab-gaps"><div class="prose">'
            + diagnostics_html(diag) + "</div></div>"
        )

    # The SVGs are already in the markup; shipping them again in the payload would double
    # the page for nothing.
    slim = {
        "order": data["order"],
        "repo": data.get("repo"),
        "index": data["index"],
        "findings": data.get("findings", []),
        # One vocabulary, defined in the gate that enforces it. A second copy in the
        # script would be free to drift from the one the build refuses to violate.
        "vocab": {"status": STATUS, "basis": BASIS},
        "briefs": [b["id"] for b in data.get("briefs", [])],
        "diagrams": {
            n: {k: v for k, v in g.items() if k not in ("svg", "rules")}
            for n, g in data["diagrams"].items()
        },
    }
    payload = json.dumps(slim, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
    brand = cfg["brand"]

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(cfg["title"])}</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Spectral:wght@600&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>{atlas_css.css(data["palette"]["light"], data["palette"]["dark"])}</style>
</head>
<body>

<div class="app">
  <header class="bar">
    <span class="brand"><b>{e(brand[0])}</b><span>{e(brand[1])}</span></span>
    <div class="tabnav">
      <button class="tabtrig" type="button" aria-haspopup="true" aria-expanded="false"
              aria-controls="tabpop" title="Switch view — arrow keys move, Esc closes"><b></b><i></i></button>
      <nav class="tabpop" id="tabpop" role="tablist" aria-label="Diagram" hidden>{"".join(tabs)}</nav>
    </div>
    <div class="baraux" id="baraux">
      <span class="find">
        <input class="q" type="search" placeholder="Find a component  /"
               aria-label="Find a component across every diagram" autocomplete="off" spellcheck="false">
        <ul class="hits" role="listbox" hidden></ul>
      </span>
      <span class="issues"{"" if cfg.get("findings") else " hidden"}>
        <label class="sr" for="fsel">Show a finding</label>
        <select class="fsel" id="fsel"><option value="">Findings — show one</option></select>
        <button class="fclear" type="button" title="Clear the finding ( Esc )" hidden>&#10005;</button>
      </span>
    </div>
    <span class="tools">
      <button class="barmore" type="button" aria-expanded="false" aria-controls="baraux"
              aria-label="Search and findings" title="Search and findings">&#9906;</button>
      <button class="panner" type="button" aria-pressed="false"
              title="Hide the panel and give the drawing the width">&#9707;</button>
      <button class="themer" type="button" title="Theme">Auto</button>
    </span>
  </header>
  <main>
    <div class="stage">{"".join(plates)}</div>
    <aside class="inspect" aria-live="polite">
      <div class="ins-head">
        <span class="t"><h2>—</h2><p></p></span>
        <button class="x" type="button" aria-label="Clear selection">&#10005;</button>
      </div>
      <div class="ins-body"></div>
    </aside>
  </main>
</div>

<style>{chr(10).join(css_rules)}</style>
<script>window.__ATLAS__={payload};</script>
<script>{SCRIPT}</script>
</body>
</html>
"""


# ---------------------------------------------------------------- proving it

CHECK = Path(__file__).with_name("check.mjs")


def free_port() -> int:
    with contextlib.closing(socket.socket()) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def verify(page: Path) -> int:
    """Serve the built page and run check.mjs against it.

    A gate nobody runs is documentation, and the suite needs three things a build does not
    have — a server, a browser and node — so it stays unrun unless the build starts them.
    The page is served rather than opened as a file because check.mjs drives a real Chrome,
    and a file:// origin changes what the browser will do with it.

    Returns the suite's exit code; 127 when the pieces are not on this box, which is a
    deferral and not a pass — it says so, loudly.
    """
    from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

    root = page.parent
    port = free_port()

    class Quiet(SimpleHTTPRequestHandler):
        def __init__(self, *a, **kw):
            super().__init__(*a, directory=str(root), **kw)

        def log_message(self, *a):
            pass

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Quiet)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    time.sleep(0.3)
    url = f"http://127.0.0.1:{port}/{page.name}"
    print(f"\nchecking {url}")
    try:
        # check.mjs imports playwright, and ESM resolution follows the FILE's directory,
        # not the working directory — so pointing node at the skill's copy cannot find a
        # playwright that lives with the probe harness. Run a copy from beside it instead.
        probes = Path.home() / ".local/lib/browser-probes"
        script = CHECK
        if (probes / "node_modules" / "playwright").exists():
            script = probes / "atlas-check.mjs"
            script.write_text(CHECK.read_text(encoding="utf-8"), encoding="utf-8")
        run = subprocess.run(
            ["node", str(script), url], text=True, capture_output=True
        )
        print(run.stdout.rstrip())
        if run.stderr.strip():
            print(run.stderr.rstrip(), file=sys.stderr)
        return run.returncode
    except FileNotFoundError:
        print("\nNOT CHECKED — node is not on this box. This is a deferral, not a pass.",
              file=sys.stderr)
        return 127
    finally:
        httpd.shutdown()


# Inside views (SKILL.md § Inside views): a diagram declaring `inside` is the deeper
# drawing of one part in another diagram. That part links down, the child links back up,
# and the child's tab sits under its parent's.
def inside_views(cfg: dict, data: dict) -> None:
    kids: dict[str, list[str]] = {}
    for name, d in cfg["diagrams"].items():
        ins = d.get("inside")
        if not ins:
            continue
        pd, pn = ins.get("diagram"), ins.get("node")
        if pd == name or pd not in data["diagrams"]:
            raise SystemExit(f"{name}.inside: {pd!r} is not another diagram in this atlas")
        part = data["diagrams"][pd]["nodes"].get(pn)
        if part is None:
            raise SystemExit(f"{name}.inside: {pd} has no part {pn!r}")
        if part.get("inside"):
            raise SystemExit(f"{name}.inside: {pd}/{pn} already opens {part['inside'][0]!r}; one inside view per part")
        part["inside"] = [name, data["diagrams"][name]["tab"]]
        data["diagrams"][name]["parent"] = [pd, pn, part["label"], data["diagrams"][pd]["tab"]]
        kids.setdefault(pd, []).append(name)
    order: list[str] = []

    def place(n: str) -> None:
        order.append(n)
        for k in kids.get(n, []):
            place(k)
    for n in data["order"]:
        if not cfg["diagrams"][n].get("inside"):
            place(n)
    if len(order) != len(data["order"]):
        lost = sorted(set(data["order"]) - set(order))
        raise SystemExit(f"inside views form a cycle; never reachable from a top-level tab: {lost}")
    data["order"] = order


# Zones (SKILL.md § Zones): 8+ parts with no archify `boundaries` read as one field.
# A warning, not a gate; `zones_waived` on the diagram entry records why not.
ZONE_MIN = 8


def unzoned(cfg: dict) -> list[str]:
    specs = Path(cfg["specs"]).expanduser()
    out = []
    for name, d in cfg["diagrams"].items():
        spec = json.loads(specs.joinpath(d["spec"]).read_text(encoding="utf-8"))
        n = len(spec.get(d["parts"], []))
        if spec.get("diagram_type") == "architecture" and n >= ZONE_MIN \
                and not spec.get("boundaries") and not d.get("zones_waived"):
            out.append(f"{name}: {n} parts, no zones")
    return out


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    cfg = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))

    # TAB NAMES ARE GATED BEFORE ANY FILE IS OPENED, and the placement is the whole point.
    # This check first lived inside assemble()'s diagram loop, where it could never fire:
    # extract() runs first and looks for a RENDERED `<key>.html` beside the specs, so any
    # key an author actually mistypes dies on FileNotFoundError long before reaching a gate
    # that could name the real problem. Proven 2026-09-05 by running the fix against its own
    # hostile input and watching pristine and patched give the identical error — a gate that
    # cannot be reached is not a gate, and only a differential run shows it.
    for _n in cfg.get("diagrams", {}):
        ident("diagrams key", _n)

    print("lifting drawings:")
    data = assemble(cfg, extract(cfg))
    out = Path(cfg["out"])

    # The companion goes to disk BEFORE the page, so a renderer that refuses still leaves
    # the reader something to look things up in.
    doc = out.with_suffix(".md")
    doc.write_text(companion(cfg, data), encoding="utf-8")
    print(f"\ncompanion {doc} — {doc.stat().st_size / 1024:.0f} KB")

    bad = connectivity(data)
    if bad:
        raise SystemExit(
            "the drawing and the spec disagree — "
            + f"{len(bad)} problem(s):\n    " + "\n    ".join(bad)
        )
    print(f"connectivity   declared == drawn on all {len(data['diagrams'])} drawings")
    flat = unzoned(cfg)
    if flat:
        print(f"zones          WARNING {len(flat)} drawing(s) of {ZONE_MIN}+ parts have no labelled zones;"
              " add archify `boundaries` (SKILL.md § Zones) or set `zones_waived`:\n    " + "\n    ".join(flat))
    else:
        print(f"zones          every drawing of {ZONE_MIN}+ parts is zoned or waived")

    out.write_text(page(cfg, data), encoding="utf-8")
    print(f"built {out} — {out.stat().st_size / 1024:.0f} KB")
    for name, g in data["diagrams"].items():
        print(f"  {name:12} {len(g['nodes'])} parts · {g['edges']} connections")

    if "--check" in sys.argv:
        raise SystemExit(verify(out))


if __name__ == "__main__":
    main()
