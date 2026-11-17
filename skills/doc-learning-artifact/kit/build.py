"""Build a learning page: head.html + the content's page.html + the inline card + engine.js, with the cards and quiz embedded.

    python3 build.py <content-dir> <out.html> [--fragment]

<content-dir> holds meta.json {title, key, lang, ui?}, page.html (the nav + main), cards.json and quiz.json,
and optionally extra.css and extra.js (page-specific widgets; extra.js runs after the engine).
meta.ui overrides any UI word (see the T table in engine.js, plus examAngle, close, hint, click, tap, correct).
--fragment leaves out <!doctype>/<html>/<meta charset>, for hosts that wrap the page themselves.
A diagram box becomes clickable when its <rect class="s-..."/> is followed by a <text> whose label is a key in cards.json.
"""
import html
import json
import re
import sys
from pathlib import Path

KIT = Path(__file__).resolve().parent
src, out, fragment = Path(sys.argv[1]), Path(sys.argv[2]), "--fragment" in sys.argv[3:]
meta = json.loads((src / "meta.json").read_text())
cards = json.loads((src / "cards.json").read_text())
quiz = json.loads((src / "quiz.json").read_text())
body = (src / "page.html").read_text()
for need in ('<nav class="toc"', "<main>", 'id="start"'):
    assert need in body, f"page.html is missing {need}"

used = set()
pat = re.compile(r'<rect class="(s-[a-z]+)([^"]*)"([^>]*)/>(\s*<text[^>]*>)([^<]*)(</text>)')


def tag(m):
    key = html.unescape(m.group(5)).strip()
    if key not in cards:
        return m.group(0)
    used.add(key)
    k = html.escape(key, quote=True)
    return (f'<rect class="{m.group(1)}{m.group(2)} hot"{m.group(3)} data-k="{k}" tabindex="0" role="button" '
            f'aria-label="Details: {html.escape(cards[key]["t"], quote=True)}"/>{m.group(4)}{m.group(5)}{m.group(6)}')


body = pat.sub(tag, body)
body = re.sub(r'<figure class="fig[^"]*">.*?</figure>',
              lambda m: m.group(0).replace('<figure class="fig', '<figure class="fig clickable', 1) if "data-k=" in m.group(0) else m.group(0),
              body, flags=re.S)
# keep each "Builds on / Leads to / Quiz" label on the same line as its chips
body = re.sub(r'<div class="links">(.*?)</div>',
              lambda m: '<div class="links">' + ''.join(f'<span class="lgrp">{p}</span>' if p.startswith('<span class="lab">') else p
                                                         for p in re.split(r'(?=<span class="lab">)', m.group(1))) + '</div>', body)
# keep a pair of recording timestamps together
body = re.sub(r'(?<!</a> )(<a class="ts"[^>]*>[^<]*</a>) (<a class="ts"[^>]*>[^<]*</a>)(?! <a class="ts")', r'<span class="tsg">\1 \2</span>', body)

head = (KIT / "head.html").read_text().replace("{{TITLE}}", html.escape(meta["title"]))
ui = {"examAngle": "Exam angle", "close": "Close ✕", "closeLabel": "Close details", "hint": "Esc closes · click another box to switch", **meta.get("ui", {})}
e = lambda k: html.escape(ui[k])
drawer = f'''<aside class="drawer" id="drawer" aria-hidden="true" aria-labelledby="dr-title" role="region" aria-live="polite">
  <div class="top"><span class="src" id="dr-src"></span><button type="button" id="dr-close" aria-label="{e("closeLabel")}">{e("close")}</button></div>
  <h3 id="dr-title"></h3>
  <p id="dr-body"></p>
  <div class="exam" id="dr-exam"><b>{e("examAngle")}</b><span></span></div>
  <a class="go" id="dr-go" href="#start"></a>
  <p class="hint">{e("hint")}</p>
</aside>'''
data = json.dumps({"key": meta["key"], "info": cards, "quiz": quiz, "ui": meta.get("ui", {})}, ensure_ascii=False).replace("</", "<\\/")
css_words = "".join(f'--t-{k}: {json.dumps(ui[k], ensure_ascii=False)}; ' for k in ("click", "tap", "correct") if k in ui)
extra_css = (src / "extra.css").read_text() if (src / "extra.css").exists() else ""
extra_js = (src / "extra.js").read_text() if (src / "extra.js").exists() else ""
if css_words or extra_css:
    head += f"\n<style>\n:root {{ {css_words}}}\n{extra_css}</style>"
shell = "" if fragment else f'<!doctype html>\n<html lang="{meta.get("lang", "en")}">\n<meta charset="utf-8">\n'
page = (f'{shell}{head}\n{body}\n{drawer}\n'
        f'<script>\nconst DATA = {data};\n{(KIT / "engine.js").read_text()}</script>\n'
        + (f'<script>\n{extra_js}</script>\n' if extra_js else ""))
out.write_text(page)
print(f"clickable parts: {len(used)} | cards never used: {sorted(set(cards) - used)} | "
      f"clickable figures: {body.count('fig clickable')} of {body.count('<figure')} | quiz: {len(quiz)}")
