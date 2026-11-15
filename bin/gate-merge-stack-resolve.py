#!/usr/bin/env python3
"""Resolve conflict blocks where both sides only ADDED entries to a list, keeping both. harbor#1060 · merge-stack's
resolver. INTERPRETER EXCEPTION: python3, because the shapes below are regular expressions over multi-line blocks
and POSIX sh/awk would make each one a fragile parse; doc-graph-generate.sh and standard-rename.sh already run python3 from
bin/ and deploy-doctor.sh probes it. Without python3 a conflicted file is left for a person, which is the safe outcome.
Reads conflicts in git's diff3 style (the tool pins merge.conflictStyle=diff3): every block has ours, the BASE and theirs.
A block is resolved only if both sides are pure ADDITIONS relative to the base: nothing the base had is missing from either
side, so a deletion or an edit (a deletion plus an addition) is refused, never silently brought back. Shapes accepted:
  - a FILES="..." word list;            - a `case "$b" in a|b) continue ;; esac` line (alternatives unioned);
  - a closing word-list line ending in `"` (words unioned, ours' line breaks kept).
  - with --lines, in a .txt or .tsv the tool declares a line list: whole lines both sides added (ours, then theirs' new ones).
Exits 1, file untouched, on any other block, on a block with no base section, on a file that still has a marker, and on a
file with no conflict block at all: a delete/modify or a binary conflict leaves none, and "nothing to resolve" is not resolved (r5 #1).
No line is treated as a comment: whether a `#` line is one cannot be proved from the block (a here-doc or a string makes it
data, r4 #3), so a block holding one matches no shape and is refused, unless the file is a declared line list.
Only files whose syntax is known are resolved (by extension, name, or an sh/python shebang); any other file is refused whole."""
import os, re, sys
args = sys.argv[1:]; lines_mode = args[:1] == ['--lines']
if lines_mode: args = args[1:]
if len(args) != 1: sys.exit(2)
p = args[0]
try: s = open(p).read()
except (UnicodeDecodeError, OSError): sys.exit(1)   # a binary file is no list
pat = re.compile(r'<<<<<<< [^\n]*\n(.*?)\|\|\|\|\|\|\| [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', re.S)
HASH_EXT = {'.sh', '.bash', '.zsh', '.py', '.yml', '.yaml', '.tsv', '.txt', '.toml', '.conf', '.cfg', '.awk'}
HASH_NAME = {'Makefile', '.gitignore', '.gitattributes'}
def hash_syntax(path, text):
    base = os.path.basename(path)
    if base in HASH_NAME or os.path.splitext(base)[1] in HASH_EXT: return True
    m = re.match(r'#!\s*(\S+)(?:\s+(\S+))?', text)   # an extensionless script: its interpreter decides
    if not m: return False
    prog = os.path.basename(m.group(2) if os.path.basename(m.group(1)) == 'env' and m.group(2) else m.group(1))
    return re.fullmatch(r'(ba|da|z|k)?sh|python[0-9.]*', prog) is not None
if '<<<<<<<' not in s or not hash_syntax(p, s): sys.exit(1)
if lines_mode and os.path.splitext(p)[1] not in ('.txt', '.tsv'): sys.exit(1)   # a line list is data, never code
def words_union(a, b): return a + [w for w in b if w not in a]
def only_adds(base, *sides): return all(w in side for side in sides for w in base)   # nothing the base had is gone
def fix(m):
    o, b, t = (m.group(i).splitlines(True) for i in (1, 2, 3))
    if lines_mode:   # every line independent: keep ours, add theirs' new lines; a line either side lost is refused
        if not only_adds(b, o, t): raise SystemExit(1)
        return ''.join(o + [l for l in t if l not in o])
    if len(o) == 1 and len(t) == 1 and len(b) == 1:
        rf = r'(\s*FILES=")([^"]*)("\s*)$'
        mo, mb, mt = (re.match(rf, x[0]) for x in (o, b, t))
        if mo and mb and mt and mo.group(1) == mb.group(1) == mt.group(1) and mo.group(3) == mb.group(3) == mt.group(3):
            ow, bw, tw = mo.group(2).split(), mb.group(2).split(), mt.group(2).split()
            if not only_adds(bw, ow, tw): raise SystemExit(1)
            return mo.group(1) + ' '.join(words_union(ow, tw)) + mo.group(3)
        rc = r'(\s*case "\$b" in )([^)]*)(\) continue ;; esac\s*)$'
        mo, mb, mt = (re.match(rc, x[0]) for x in (o, b, t))
        if mo and mb and mt and mo.group(1) == mb.group(1) == mt.group(1) and mo.group(3) == mb.group(3) == mt.group(3):
            ow, bw, tw = mo.group(2).split('|'), mb.group(2).split('|'), mt.group(2).split('|')
            if not only_adds(bw, ow, tw): raise SystemExit(1)
            return mo.group(1) + '|'.join(words_union(ow, tw)) + mo.group(3)
    # a word list closing with a quote: every line plain words, the last ends `"`; the base is the list as it was
    plain = lambda ls: all(re.fullmatch(r'[\w./+-]+(?: [\w./+-]+)*"?\s*', l) for l in ls)
    if o and b and t and o[-1].rstrip().endswith('"') and t[-1].rstrip().endswith('"') and plain(o) and plain(b) and plain(t):
        words = lambda ls: ' '.join(l.strip().rstrip('"') for l in ls).split()
        ow, bw, tw = words(o), words(b), words(t)
        if not only_adds(bw, ow, tw): raise SystemExit(1)
        extra = [w for w in tw if w not in ow]
        if not extra: return ''.join(o)
        last = o[-1].rstrip('\n').rstrip(); body = last[:-1].rstrip()
        return ''.join(o[:-1]) + body + ' ' + ' '.join(extra) + '"\n'
    raise SystemExit(1)
n, blocks = pat.subn(fix, s)
if blocks == 0 or '<<<<<<<' in n: sys.exit(1)
open(p, 'w').write(n)
