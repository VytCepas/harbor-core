"""Every widget mounts, every slider and button visibly changes it, every ▶ starts motion (and again on a second press,
and a play/pause toggle really pauses), no errors, no horizontal page scroll on any tab.
Four modes: desktop, iPhone 13, Reduce Motion on, and a ~250 Hz screen. Exit 1 on any failure.
Measured 2026-10-03: the old fizmat-9 build passed the earlier, weaker version of this test while 15 ▶ buttons were dead.

    uvx --with playwright python wgtest.py <page.html> [--shots DIR] [--only u01,u02]
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

page_path = Path(sys.argv[1]).resolve()
URL = page_path.as_uri()
args = sys.argv[2:]
SHOTS = Path(args[args.index("--shots") + 1]) if "--shots" in args else None
ONLY = set(args[args.index("--only") + 1].split(",")) if "--only" in args else None
fails = []


def check(name, ok, extra=""):
    if not ok:
        print("FAIL " + name + (" | " + str(extra) if extra else ""))
        fails.append(name)


SNAP = "r => [...r.querySelectorAll('.wg-out, .wg-stage, .wg-react')].map(e => e.innerHTML).join('|')"  # the slider's own value label does not count

with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome")
    # "reduce": a desktop with the OS accessibility setting Reduce Motion on, as many Macs and iPhones have it
    # "fast": a ~250 Hz screen (requestAnimationFrame every 4 ms); tiny per-frame steps that get rounded away freeze there first
    for mode in ["desktop", "phone", "reduce", "fast"]:
        ctx = b.new_context(**p.devices["iPhone 13"]) if mode == "phone" else b.new_context(viewport={"width": 1400, "height": 900}, reduced_motion="reduce" if mode == "reduce" else "no-preference")
        if mode == "fast":
            ctx.add_init_script("(() => { let id = 0; const m = new Map(); window.requestAnimationFrame = cb => { const i = ++id; m.set(i, setTimeout(() => { m.delete(i); cb(performance.now()); }, 4)); return i; }; window.cancelAnimationFrame = i => { clearTimeout(m.get(i)); m.delete(i); }; })()")
        pg = ctx.new_page()
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.on("console", lambda m: errs.append(m.text) if m.type == "error" else None)
        pg.goto(URL)
        pg.wait_for_timeout(500)
        secs = pg.evaluate("[...document.querySelectorAll('main > section.topic, main > header.hero')].map(s => s.id)")
        n_wg = n_ctl = 0
        for sid in secs:
            if ONLY and sid not in ONLY:
                continue
            pg.evaluate(f"history.pushState(null, '', '#{sid}'); dispatchEvent(new PopStateEvent('popstate'))")
            pg.wait_for_timeout(150)
            sw = pg.evaluate("[document.documentElement.scrollWidth, innerWidth]")
            check(f"[{mode}] #{sid} no horizontal page scroll", sw[0] <= sw[1], sw)
            wgs = pg.locator(f"#{sid} .wg[data-wg]")
            for i in range(wgs.count()):
                w = wgs.nth(i)
                name = w.get_attribute("data-wg")
                n_wg += 1
                check(f"[{mode}] {name} mounted", w.get_attribute("data-ready") == "1", w.get_attribute("data-ready"))
                if w.get_attribute("data-ready") != "1":
                    continue
                before = w.evaluate(SNAP)
                changed = False
                sliders = w.locator("input[type=range]")
                for j in range(sliders.count()):
                    s = sliders.nth(j)
                    n_ctl += 1
                    seen = {w.evaluate(SNAP)}
                    for frac in (0.0, 1.0, 0.37):
                        s.evaluate("(e, f) => { const lo = +e.min, hi = +e.max, st = +e.step || 1; e.value = lo + Math.round((hi - lo) * f / st) * st; e.dispatchEvent(new Event('input', { bubbles: true })); e.dispatchEvent(new Event('change', { bubbles: true })); }", frac)
                        pg.wait_for_timeout(40)
                        seen.add(w.evaluate(SNAP))
                    moved = len(seen) > 1
                    check(f"[{mode}] {name}: slider {j + 1} ({s.get_attribute('id')}) changes what is shown", moved)
                    changed |= moved
                for sel in w.locator("select").all():
                    opts = sel.evaluate("e => [...e.options].map(o => o.value)")
                    for v in opts[1:] + opts[:1]:
                        sel.select_option(v)
                    n_ctl += 1
                btn = w.locator("button")
                for j in range(btn.count()):
                    bj = btn.nth(j)
                    if not bj.is_visible() or bj.is_disabled():
                        continue
                    n_ctl += 1
                    label = (bj.inner_text() or "").strip()
                    already = bj.evaluate("e => e.classList.contains('on') || e.getAttribute('aria-pressed') === 'true'")
                    s0 = w.evaluate(SNAP)
                    bj.click()
                    pg.wait_for_timeout(150)
                    s1 = w.evaluate(SNAP)
                    pg.wait_for_timeout(700)
                    s2 = w.evaluate(SNAP)
                    pause = label.startswith("⏸") or "Sustabd" in label or "Pauzė" in label
                    # every button must visibly do something, unless it is a pause or was already the selected option
                    if not pause and not already:
                        check(f"[{mode}] {name}: button '{label}' visibly changes the widget", s1 != s0 or s2 != s0)
                    changed |= s2 != s0
                    if label.startswith("▶"):
                        # a play button must start MOTION (frames keep changing)
                        check(f"[{mode}] {name}: '{label}' animates", s1 != s2)
                        toggle = (bj.inner_text() or "").strip() != label
                        if toggle:
                            # play/pause in one button: the next press must stop the motion, the one after must restart it
                            bj.click(); pg.wait_for_timeout(150); a1 = w.evaluate(SNAP); pg.wait_for_timeout(500)
                            check(f"[{mode}] {name}: '{label}' pauses on the next press", a1 == w.evaluate(SNAP))
                            bj.click(); pg.wait_for_timeout(150); a1 = w.evaluate(SNAP); pg.wait_for_timeout(600)
                            check(f"[{mode}] {name}: '{label}' resumes on the press after", a1 != w.evaluate(SNAP))
                            bj.click()
                        else:
                            # pressed again after the run ended, it must play again (a dead second press reads as broken)
                            for _ in range(40):  # wait until the first run has really stopped (two equal frames), max ~16 s
                                q1 = w.evaluate(SNAP); pg.wait_for_timeout(400)
                                if q1 == w.evaluate(SNAP):
                                    break
                            bj.click()
                            pg.wait_for_timeout(150)
                            r1 = w.evaluate(SNAP)
                            pg.wait_for_timeout(700)
                            check(f"[{mode}] {name}: '{label}' animates again on a second press", r1 != w.evaluate(SNAP))
                pg.wait_for_timeout(300)
                changed |= w.evaluate(SNAP) != before
                check(f"[{mode}] {name} reacts to its controls", changed or (sliders.count() == 0 and btn.count() == 0))
                if SHOTS and mode == "phone" or (SHOTS and mode == "desktop" and "--desk" in args):
                    w.scroll_into_view_if_needed()
                    w.screenshot(path=str(SHOTS / f"{mode}-{name}.png"))
        check(f"[{mode}] no console or page errors", not errs, errs[:5])
        print(f"[{mode}] widgets: {n_wg} | controls exercised: {n_ctl}")
        ctx.close()
    b.close()
print("FAILED:", fails if fails else "none")
sys.exit(1 if fails else 0)
