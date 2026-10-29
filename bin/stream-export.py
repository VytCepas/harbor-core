#!/usr/bin/env python3
"""stream-export.py (harbor#1181 lane 8) — one registered stream, made releasable. INTERPRETER EXCEPTION: python3,
because re-keying every row with an HMAC is one fork per value in sh; stdlib only, run with python3 -I.

  python3 -I bin/stream-export.py <stream> --out DIR --key-file FILE [--from DAY] [--to DAY] [--cfg DIR]
                                  [--registry FILE] [--drop-free-text]

Reads every generation of a CONTRACTS/streams.tsv stream under the config dir, and writes DIR/<stream>.jsonl and
DIR/MANIFEST.tsv where every identifier (h, sk, sess, id, repo, cause, prev) is re-keyed with an HMAC under the
release key, so rows still join with each other and with nothing local, and every timestamp is coarsened to the hour.
A free-text stream is refused unless --drop-free-text removes its text fields. Last, a scrub gate scans the output
for this machine's user name, home path and host token, any /Users/ or /home/ path and any e-mail address; one hit
deletes the output and exits 1, naming the class, never the value. The release key never goes in DIR.
Exit 0 written, 1 refused by the scrub gate, 2 usage or policy.
"""
import argparse, glob, getpass, hashlib, hmac, json, os, re, secrets, socket, sys

IDENT = ("h", "sk", "sess", "id", "repo", "cause", "prev")
FREE_TEXT = ("subject", "detail", "data", "attrs", "msg", "reason", "k")
PLACEHOLDER = re.compile(r"<[a-z]+>|YYYY-MM-DD")


def die(code, msg):
    print(f"  FAIL: {msg}", file=sys.stderr)
    sys.exit(code)


def registry_row(path, stream):
    with open(path, encoding="utf-8") as f:
        rows = [l.rstrip("\n").split("\t") for l in f if l.strip() and not l.startswith("#")]
    head, body = rows[0], rows[1:]
    for r in body:
        if r[0] == stream:
            return dict(zip(head, r))
    die(2, f"{stream} is not a row of {path}")


def sources(row, cfg):
    p = row["path"]
    base = os.path.expanduser(p) if p.startswith("~/") else p if p.startswith("/") else os.path.join(cfg, p)
    pat = PLACEHOLDER.sub("*", base)
    found = set(glob.glob(pat)) | set(glob.glob(pat + ".*"))          # rotated generations: x.jsonl.1
    d, name = os.path.split(pat)
    stem = name[:-len(".jsonl")] if name.endswith(".jsonl") else name
    found |= set(glob.glob(os.path.join(d, "archive", stem + ".*.jsonl")))   # archived generations
    return sorted(f for f in found if os.path.isfile(f))


def main():
    ap = argparse.ArgumentParser(add_help=True, description=__doc__.split("\n\n")[0])
    ap.add_argument("stream"); ap.add_argument("--out", required=True); ap.add_argument("--key-file", required=True)
    ap.add_argument("--from", dest="since", default=""); ap.add_argument("--to", dest="until", default="")
    ap.add_argument("--cfg", default=os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude")))
    ap.add_argument("--registry", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CONTRACTS", "streams.tsv"))
    ap.add_argument("--drop-free-text", action="store_true")
    a = ap.parse_args()

    out = os.path.abspath(a.out); key_file = os.path.abspath(a.key_file)
    if os.path.commonpath([out, key_file]) == out:
        die(2, "the release key may not live inside the output dir: it would ship with the data")
    row = registry_row(a.registry, a.stream)
    if row["sensitivity"] == "free-text" and not a.drop_free_text:
        die(2, f"{a.stream} is a free-text stream: pass --drop-free-text to release it without its text fields")
    if row["sensitivity"] == "secret-adjacent":
        die(2, f"{a.stream} is secret-adjacent and is never released")
    if not os.path.exists(key_file):
        os.makedirs(os.path.dirname(key_file), exist_ok=True)
        fd = os.open(key_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.write(fd, secrets.token_hex(32).encode()); os.close(fd)
    with open(key_file, encoding="utf-8") as f:
        key = f.read().strip().encode()
    if len(key) < 32:
        die(2, f"{key_file} is not a release key (want 64 hex characters)")

    def rekey(v):
        return hmac.new(key, str(v).encode(), hashlib.sha256).hexdigest()[:16]

    files = sources(row, a.cfg)
    if not files:
        die(2, f"no files for {a.stream} under {a.cfg}")
    os.makedirs(out, exist_ok=True)
    dst = os.path.join(out, f"{a.stream}.jsonl"); n = bad = 0
    with open(dst, "w", encoding="utf-8") as w:
        for src in files:
            with open(src, encoding="utf-8", errors="replace") as f:
                for line in f:
                    try:
                        r = json.loads(line)
                    except ValueError:
                        bad += 1; continue
                    if not isinstance(r, dict):
                        bad += 1; continue
                    ts = str(r.get("ts", ""))
                    day = ts[:10]
                    if (a.since and day < a.since) or (a.until and day > a.until):
                        continue
                    for k in IDENT:
                        if r.get(k) not in (None, "", "-"):
                            r[k] = rekey(r[k])
                    if len(ts) >= 13:
                        r["ts"] = ts[:13] + ":00:00Z"
                    if a.drop_free_text:
                        for k in FREE_TEXT:
                            r.pop(k, None)
                    w.write(json.dumps(r, sort_keys=True, separators=(",", ":")) + "\n"); n += 1

    # The scrub gate: the output is judged as text, so a field this code never heard of is judged too.
    text = open(dst, encoding="utf-8").read()
    host = ""
    try:
        host = open(os.path.join(a.cfg, ".helm-obs-host"), encoding="utf-8").read().strip()
    except OSError:
        pass
    classes = {"user name": getpass.getuser(), "home path": os.path.expanduser("~"),
               "host name": socket.gethostname().split(".")[0], "host token": host}
    hits = [c for c, v in classes.items() if len(v) >= 3 and v.lower() in text.lower()]
    if re.search(r"/(Users|home)/[A-Za-z0-9._-]+", text):
        hits.append("a home-directory path")
    if re.search(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}", text):
        hits.append("an e-mail address")
    if hits:
        os.remove(dst)
        die(1, f"scrub gate: the output named {', '.join(hits)}; nothing was written")
    digest = hashlib.sha256(text.encode()).hexdigest()
    with open(os.path.join(out, "MANIFEST.tsv"), "w", encoding="utf-8") as m:
        m.write("file\trows\tsha256\tsources\tunparseable\n")
        m.write(f"{a.stream}.jsonl\t{n}\t{digest}\t{len(files)}\t{bad}\n")
    print(f"  ok: {a.stream}: {n} row(s) from {len(files)} file(s), {bad} unparseable, scrub gate clean")


if __name__ == "__main__":
    main()
