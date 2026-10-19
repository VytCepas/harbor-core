"""Give each diagram its own ID space, and prove every internal reference still resolves.

Four archify documents inlined into one page put four `id="arrowhead"` markers in one
document. `url(#arrowhead)` binds to the first, which lives in whichever tab panel happens
to come first — and a `<marker>` inside a `display:none` subtree paints nothing. That is
why every diagram after the first lost its arrowheads: not a missing rule, a collision.

`data-node-id` and the other `data-*` hooks are deliberately NOT rewritten. They are the
lookup keys the inspector uses against the spec, they are scoped to their own SVG by the
DOM, and prefixing them would mean decoding the prefix back off on every click.
"""

import re

# `id=` but never the tail of `data-node-id=` / `data-edge-id=` / `data-composition-frame-id=`.
ID_ATTR = re.compile(r'(?<![-\w])id="([^"]+)"')
URL_REF = re.compile(r"url\(#([^)]+)\)")
HASH_REF = re.compile(r'((?:xlink:)?href)="#([^"]+)"')
LABELLEDBY = re.compile(r'aria-(labelledby|describedby|controls)="([^"]+)"')


def apply(svg: str, prefix: str) -> str:
    svg = ID_ATTR.sub(lambda m: f'id="{prefix}-{m.group(1)}"', svg)
    svg = URL_REF.sub(lambda m: f"url(#{prefix}-{m.group(1)})", svg)
    svg = HASH_REF.sub(lambda m: f'{m.group(1)}="#{prefix}-{m.group(2)}"', svg)
    svg = LABELLEDBY.sub(
        lambda m: f'aria-{m.group(1)}="'
        + " ".join(f"{prefix}-{t}" for t in m.group(2).split())
        + '"',
        svg,
    )
    return svg


def check(svg: str, name: str) -> None:
    """Every reference must land on an ID this SVG defines, and no ID may repeat."""
    ids = ID_ATTR.findall(svg)
    dupes = {i for i in ids if ids.count(i) > 1}
    assert not dupes, f"{name}: duplicate ids within one svg: {sorted(dupes)}"
    defined = set(ids)
    refs = set(URL_REF.findall(svg)) | {m[1] for m in HASH_REF.findall(svg)}
    for m in LABELLEDBY.finditer(svg):
        refs |= set(m.group(2).split())
    dangling = refs - defined
    assert not dangling, f"{name}: {len(dangling)} references resolve to nothing: {sorted(dangling)}"
