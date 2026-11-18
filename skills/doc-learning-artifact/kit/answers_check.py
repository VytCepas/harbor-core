"""Prove every quiz question is answerable from the page: each one has a verbatim answer quote in the visible text or a card.

    python3 answers_check.py <content-dir> [--against <reference-content-dir>]

<content-dir>/answers.json holds one entry per quiz.json question, in order:
  {"index": 0, "source": "page" | "card:<card key>", "quote": "<= 160 chars, copied verbatim"}
"page" quotes must be a substring of page.html's visible text (SVGs, styles, scripts and comments removed, inline tags joined, entities decoded).
"card:<key>" quotes must be in that card's d or x field, and the card's label must appear in a diagram on the page.
--against: a condensed edition. Every SVG in page.html must be byte-identical to one in the reference page.html,
because card keys and the text-fit check depend on exact labels and geometry. Prints prose words, reference and here.
Exit 1 on any failure.
"""
import html
import json
import re
import sys
from pathlib import Path

INLINE = r'</?(b|i|em|strong|a|span|code|sub|sup|small|mark|abbr|kbd)\b[^>]*>'


def visible(s):
    s = re.sub(r'<!--.*?-->|<(svg|style|script)\b[^>]*/>|<(svg|style|script)\b[^>]*(?<!/)>.*?</\2>', ' ', s, flags=re.S | re.I)  # none of it is read on screen
    s = re.sub(INLINE, '', s)  # inline tags join words, block tags separate them
    return re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', s))).strip()


def norm(s):
    return re.sub(r'\s+', ' ', s).strip()


svgs = lambda s: re.findall(r'<svg\b.*?</svg>', s, flags=re.S | re.I)
args = sys.argv[1:]
src = Path(args[0])
ref = Path(args[args.index('--against') + 1]) if '--against' in args else None
page = (src / 'page.html').read_text()
cards = json.loads((src / 'cards.json').read_text())
quiz = json.loads((src / 'quiz.json').read_text())
answers = json.loads((src / 'answers.json').read_text())
text = norm(visible(page))
labels = {html.unescape(m).strip() for m in re.findall(r'<text[^>]*>([^<]*)</text>', page)}
bad = []

if [a.get('index') for a in answers] != list(range(len(quiz))):
    bad.append(f'answers.json must cover questions 0..{len(quiz) - 1} in order, got {[a.get("index") for a in answers]}')
for a in answers:
    q, s = norm(a.get('quote', '')), a.get('source', '')
    if not q or len(q) > 160:
        bad.append(f'Q{a.get("index")}: quote is empty or over 160 chars')
        continue
    if s == 'page':
        ok = q in text
    elif s.startswith('card:'):
        k = s[5:]
        ok = k in cards and k in labels and (q in norm(cards[k].get('d', '')) or q in norm(cards[k].get('x', '')))
    else:
        ok = False
    if not ok:
        bad.append(f'Q{a.get("index")}: quote not found ({s}): {q[:90]}')

if ref:
    rpage = (ref / 'page.html').read_text()
    known = set(svgs(rpage))
    bad += [f'SVG not byte-identical to any reference SVG: {sv[:80]}' for sv in svgs(page) if sv not in known]
    w = lambda p: len(visible(p).split())
    print(f'prose words {w(rpage)} -> {w(page)} ({w(page) * 100 // max(w(rpage), 1)} %) | diagrams {len(known)} -> {len(svgs(page))}')

print(f'questions {len(quiz)} | answers {len(answers)}')
print('\n'.join(bad) if bad else 'every question has its answer on the page')
sys.exit(1 if bad else 0)
