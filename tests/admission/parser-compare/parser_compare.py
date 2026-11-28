#!/usr/bin/env python3
"""parser_compare.py - offline differential of the Bash guards' tokenizer against a real parser.

For every command in the corpus it extracts (a) the segments harbor's tokenizer builds
(admission-normalize.awk, the SEG rows; the first word of each segment) and (b) the
simple commands in shfmt's AST (shfmt --to-json; the first word of every CallExpr, nested ones
included), and reports where the two multisets of command words disagree. It reads and parses;
it never executes a corpus command and changes no guard.

Corpus: every `cmd` / `tool_input.command` / `input.command` string in the repo's JSONL fixtures
(tests/**, fixtures/**, hooks/**), plus any file named with --extra (one command per file).

Usage: python3 -I parser_compare.py [--repo DIR] [--extra FILE ...] [--json OUT.json] [--examples N]
Needs shfmt (mvdan.cc/sh) on PATH or in /opt/homebrew/bin.
"""
import argparse, collections, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SUBST = {"{home}": "/home/someone", "{cfg}": "/home/someone/.claude", "{tmp}": "/tmp/t", "{root}": "/repo", "{j}": ""}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*\+?=")


def subst(s):
    for k, v in SUBST.items():
        s = s.replace(k, v)
    return s


def corpus(repo, extras):
    rows, seen = [], set()
    for top in ("tests", "fixtures", "hooks"):
        for dp, _dn, fn in os.walk(os.path.join(repo, top)):
            for f in sorted(fn):
                if not f.endswith(".jsonl"):
                    continue
                path = os.path.join(dp, f)
                with open(path, encoding="utf-8", errors="replace") as fh:
                    for n, line in enumerate(fh, 1):
                        try:
                            r = json.loads(line)
                        except ValueError:
                            continue
                        if not isinstance(r, dict):
                            continue
                        cmd = None
                        if isinstance(r.get("cmd"), str):
                            cmd = r["cmd"]
                        for k in ("tool_input", "input"):
                            v = r.get(k)
                            if isinstance(v, dict) and isinstance(v.get("command"), str) and r.get("tool", r.get("tool_name", "Bash")) == "Bash":
                                cmd = v["command"]
                        if cmd is None:
                            continue
                        cmd = subst(cmd)
                        rows.append((os.path.relpath(path, repo) + ":" + str(n), cmd))
    for p in extras:
        with open(p, encoding="utf-8", errors="replace") as fh:
            rows.append((os.path.basename(p), fh.read().rstrip("\n")))
    uniq = collections.OrderedDict()
    for src, cmd in rows:
        uniq.setdefault(cmd, []).append(src)
    return len(rows), uniq


def word_text(w):
    """shfmt Word node -> text with quotes removed; any expansion becomes the wildcard $V."""
    out = []
    for p in w.get("Parts", []):
        t = p.get("Type")
        if t == "Lit":
            out.append(p.get("Value", ""))
        elif t == "SglQuoted":
            out.append(p.get("Value", ""))
        elif t == "DblQuoted":
            out.append(word_text(p))
        else:
            out.append("$V")
    return "".join(out)


def simple_commands(node, acc):
    if isinstance(node, dict):
        if node.get("Type") == "CallExpr" and node.get("Args"):
            acc.append(word_text(node["Args"][0]))
        for v in node.values():
            simple_commands(v, acc)
    elif isinstance(node, list):
        for v in node:
            simple_commands(v, acc)


def norm(w):
    w = w.replace("@SUB@", "$V")
    w = re.sub(r"\$\{[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*|\$[0-9@#?*!$-]", "$V", w)
    w = re.sub(r"[\"'\\]", "", w)
    return w


def match_key(w):
    return norm(w)


def shfmt_words(shfmt, cmd):
    p = subprocess.run([shfmt, "-ln", "bash", "--to-json"], input=cmd.encode(), capture_output=True)
    if p.returncode != 0:
        return None, p.stderr.decode(errors="replace").strip().splitlines()[:1]
    acc = []
    simple_commands(json.loads(p.stdout), acc)
    return [norm(w) for w in acc if not ASSIGN.match(w)], None


KEYWORDS = ("", "!", "{", "}", "(", ")", "then", "do", "done", "fi", "else", "elif", "esac", "if", "while", "until", "for", "case", "in", "time", "function", "coproc")


def harbor_words(segs):
    """The command word of each segment: SEGW (the raw first word), or SEGC (wrappers peeled) when
    SEGW is only an assignment or a keyword (`FOO=1 curl`, `then curl`, `time sh`)."""
    syn, W, C = set(), {}, {}
    for line in segs.splitlines():
        m = re.match(r"SEG[FEI]:(\d+):", line)
        if m:
            syn.add(m.group(1))
        m = re.match(r"SEG([WC]):(\d+):(.*)$", line)
        if m:
            (W if m.group(1) == "W" else C)[m.group(2)] = m.group(3)
    words = []
    for i in sorted(W, key=int):
        if i in syn:
            continue
        w = W[i]
        if ASSIGN.match(w) or w in KEYWORDS:
            w = C.get(i, "")
            if ASSIGN.match(w) or w in KEYWORDS:
                continue
        words.append(norm(w))
    return words, len(syn)


def words_equal(a, b):
    """multiset equality where a word holding $V matches on its literal fragments only."""
    ca, cb = collections.Counter(a), collections.Counter(b)
    only_a, only_b = ca - cb, cb - ca
    # a wildcard word on one side absorbs one unmatched word on the other
    for w in list(only_a):
        if "$V" in w:
            pat = re.compile("^" + ".*".join(re.escape(x) for x in w.split("$V")) + "$")
            for v in list(only_b):
                while only_a[w] > 0 and only_b[v] > 0 and pat.match(v):
                    only_a[w] -= 1
                    only_b[v] -= 1
    for v in list(only_b):
        if "$V" in v:
            pat = re.compile("^" + ".*".join(re.escape(x) for x in v.split("$V")) + "$")
            for w in list(only_a):
                while only_b[v] > 0 and only_a[w] > 0 and pat.match(w):
                    only_b[v] -= 1
                    only_a[w] -= 1
    return +only_a, +only_b


ZSH = re.compile(r"\([:a-z.]+\)|=\(|\$\{\(|\*\*/|\bsetopt\b|\bautoload\b|\bprint\s+-[a-zA-Z]*\b|\bemulate\b|\bzmodload\b|\^[a-z]|\(\.\)|\(/\)|\(N\)|\(om\[")


def classify(cmd, harbor_only, shfmt_only):
    """Primary class by which construct the command carries; first match wins."""
    if any(("$V" in w or "{" in w) for w in shfmt_only) or "$'" in cmd and harbor_only:
        return "command word built by expansion (brace, $IFS, ANSI-C)"
    if re.search(r"<<-?\s*['\"\\]?[A-Za-z_]", cmd.replace("<<<", "")):
        return "heredoc body"
    if "$((" in cmd or re.search(r"(^|[;&|(\s])\(\(", cmd):
        return "arithmetic"
    if re.search(r"[<>]\(", cmd):
        return "process substitution"
    if "$(" in cmd or "`" in cmd:
        return "command substitution"
    if "$'" in cmd or '$"' in cmd:
        return "ANSI-C / locale quoting"
    if "'" in cmd and '"' in cmd or re.search(r"\\['\"]", cmd):
        return "nested quoting / escapes"
    if re.search(r"(^|[;&|])\s*[({]|\)\s*[|;&]|\bfunction\b|\(\)\s*\{", cmd):
        return "group / subshell / function"
    if re.search(r"\b(for|while|until|if|case|select)\b", cmd):
        return "compound keyword"
    return "other"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.abspath(os.path.join(HERE, "..", "..", "..")))
    ap.add_argument("--extra", nargs="*", default=[])
    ap.add_argument("--json")
    ap.add_argument("--examples", type=int, default=3)
    a = ap.parse_args()
    shfmt = shutil.which("shfmt") or "/opt/homebrew/bin/shfmt"
    nrows, uniq = corpus(a.repo, a.extra)
    cmds = list(uniq)
    tmp = tempfile.mkdtemp(prefix="parser-compare.")
    ind, outd = os.path.join(tmp, "in"), os.path.join(tmp, "out")
    os.mkdir(ind)
    os.mkdir(outd)
    for i, c in enumerate(cmds):
        with open(os.path.join(ind, "%d.cmd" % i), "w", encoding="utf-8") as fh:
            fh.write(c)
    subprocess.run(["sh", os.path.join(HERE, "segment-table.sh"), ind, outd], check=True, env=dict(os.environ, HOME=os.environ.get("HOME", "/")))
    res = collections.OrderedDict()
    stats = collections.Counter()
    for i, c in enumerate(cmds):
        with open(os.path.join(outd, "%d.segs" % i), encoding="utf-8", errors="replace") as fh:
            segs = fh.read()
        hw, nsyn = harbor_words(segs)
        sw, err = shfmt_words(shfmt, c)
        stats["synthesized_children"] += nsyn
        if not segs.strip():
            stats["harbor_no_table"] += 1
            res[c] = {"class": "harbor builds no table (oversize payload: flat fallback)", "harbor_only": [], "shfmt_only": sw or []}
            continue
        if sw is None:
            stats["shfmt_parse_error"] += 1
            cls = "shfmt rejects: zsh-only syntax" if ZSH.search(c) else "shfmt rejects: not valid bash (incomplete or other)"
            res[c] = {"class": cls, "harbor_only": hw, "shfmt_only": [], "err": err}
            continue
        ho, so = words_equal(hw, sw)
        if not ho and not so:
            stats["agree"] += 1
            continue
        res[c] = {"class": classify(c, ho, so), "harbor_only": sorted(ho.elements()), "shfmt_only": sorted(so.elements())}
    stats["compared"] = len(cmds)
    stats["rows"] = nrows
    stats["disagree"] = len(res)
    by = collections.OrderedDict()
    for c, r in res.items():
        by.setdefault(r["class"], []).append(c)
    print("rows in corpus: %d; unique commands compared: %d; agree: %d; disagree (incl. shfmt parse errors): %d" % (nrows, len(cmds), stats["agree"], len(res)))
    print("harbor table empty for %d; synthesized child segments (sh -c, eval, find -exec) set aside: %d" % (stats["harbor_no_table"], stats["synthesized_children"]))
    for cls in sorted(by, key=lambda k: -len(by[k])):
        L = by[cls]
        ho = sum(1 for c in L if res[c]["harbor_only"])
        so = sum(1 for c in L if res[c]["shfmt_only"])
        print("\n== %s: %d commands (harbor reads extra words in %d; shfmt reads extra words in %d)" % (cls, len(L), ho, so))
        for c in L[: a.examples]:
            r = res[c]
            print("  e.g. [%s] %s" % (uniq[c][0], c.replace("\n", "\\n")[:160]))
            print("       harbor-only=%s shfmt-only=%s%s" % (r["harbor_only"][:6], r["shfmt_only"][:6], (" err=%s" % r["err"]) if r.get("err") else ""))
    if a.json:
        with open(a.json, "w", encoding="utf-8") as fh:
            json.dump({"stats": dict(stats), "classes": {k: len(v) for k, v in by.items()},
                       "rows": [dict(cmd=c, src=uniq[c][:3], **r) for c, r in res.items()]}, fh, indent=1)
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
