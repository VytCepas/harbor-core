# test_kit.py (harbor#1558): the example passes every kit gate, and each planted fault fails its gate
"""Usage: python3 test_kit.py [--browser]   Exit 0 = every case behaved.
--browser also runs check.py in real Chrome (needs playwright: uvx --with playwright python test_kit.py --browser)."""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

KIT = Path(__file__).resolve().parent
EX = KIT / "example"
fails = []


def run(*args):
    p = subprocess.run([sys.executable, "-I", *map(str, args)], capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def case(name, want_rc, rc, out, must=None):
    ok = rc == want_rc and (must is None or must in out)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else f" | rc {rc}, want {want_rc} | {out.strip()[-200:]}"))
    if not ok:
        fails.append(name)


def copy_example(tmp, name):
    d = Path(tmp) / name
    shutil.copytree(EX, d)
    return d


def edit(path, old, new):
    s = path.read_text()
    assert old in s, (path, old)
    path.write_text(s.replace(old, new, 1))


with tempfile.TemporaryDirectory() as tmp:
    case("answers: the example passes", 0, *run(KIT / "answers_check.py", EX))
    case("answers: an edition identical to its reference passes", 0, *run(KIT / "answers_check.py", EX, "--against", EX))

    d = copy_example(tmp, "wrong-quote")
    edit(d / "answers.json", "÷ all reads", "÷ every read")
    case("answers: a quote not on the page fails", 1, *run(KIT / "answers_check.py", d), "quote not found")

    d = copy_example(tmp, "hidden-quote")
    edit(d / "page.html", "<p><b>Hit rate</b> = reads served from a cache ÷ all reads.</p>",
         "<style>/* Hit rate = reads served from a cache ÷ all reads. */</style>")
    case("answers: a quote only inside <style> fails", 1, *run(KIT / "answers_check.py", d), "quote not found")

    d = copy_example(tmp, "card-not-drawn")
    edit(d / "answers.json", '"card:Origin"', '"card:Nowhere"')
    case("answers: a card whose box is in no diagram fails", 1, *run(KIT / "answers_check.py", d), "quote not found")

    d = copy_example(tmp, "missing-answer")
    a = json.loads((d / "answers.json").read_text())
    (d / "answers.json").write_text(json.dumps(a[:-1]))
    case("answers: a question with no answer fails", 1, *run(KIT / "answers_check.py", d), "must cover questions")

    d = copy_example(tmp, "svg-changed")
    edit(d / "page.html", 'width="200" height="56" rx="8"/><text class="s-t" x="34" y="56">Browser',
         'width="190" height="56" rx="8"/><text class="s-t" x="34" y="56">Browser')
    case("answers: an edition diagram not byte-identical fails", 1, *run(KIT / "answers_check.py", d, "--against", EX), "not byte-identical")

    rc, out = run(KIT / "build.py", EX, Path(tmp) / "example.html")
    case("build: the example builds with no warning", 0, rc, out)
    if "WARNING" in out:
        fails.append("build: the example printed a WARNING")

    d = copy_example(tmp, "keys-first")
    q = {"topic": "Cache layers", "sec": "u01", "type": "single", "conf": "sure", "q": "Pick one.", "why": "x",
         "opts": [["right", True], ["wrong", False]]}
    (d / "quiz.json").write_text(json.dumps([q] * 4))
    (d / "answers.json").write_text("[]")
    case("build: four choice questions keyed first print the warning", 0, *run(KIT / "build.py", d, Path(tmp) / "k.html"), "WARNING: the first option")

    if "--browser" in sys.argv[1:]:
        page = Path(tmp) / "example.html"
        rc, out = run(KIT / "check.py", page)
        case("check: the example passes in Chrome", 0, rc, out)

        d = copy_example(tmp, "overflow")
        edit(d / "page.html", ">many users nearby<", ">many many many users nearby, very far away<")
        run(KIT / "build.py", d, Path(tmp) / "overflow.html")
        case("check: text past its box fails", 1, *run(KIT / "check.py", Path(tmp) / "overflow.html"), "px past its box")

        d = copy_example(tmp, "transformed")
        # drawn below the viewBox, but its local box covers the start of "Browser" and is narrower than it
        edit(d / "page.html", '<line class="s-line" x1="220"', '<g transform="translate(0,300)"><rect x="20" y="40" width="30" height="40"/></g><line class="s-line" x1="220"')
        run(KIT / "build.py", d, Path(tmp) / "transformed.html")
        case("check: a rect under a transform causes no false spill", 0, *run(KIT / "check.py", Path(tmp) / "transformed.html"))

print("FAILED:", fails if fails else "none")
sys.exit(1 if fails else 0)
