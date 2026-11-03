"""Check a built learning page in real Chrome, desktop and iPhone 13. Exit 1 on any failure.

    uvx --with playwright python check.py <page.html> [<screenshot-dir>]
"""
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

URL = Path(sys.argv[1]).resolve().as_uri()
SHOTS = Path(sys.argv[2]) if len(sys.argv) > 2 else None
fails = []


def check(name, ok, extra=""):
    print(("PASS " if ok else "FAIL ") + name + (" | " + str(extra) if extra and not ok else ""))
    if not ok:
        fails.append(name)


VISIBLE = "() => [...document.querySelectorAll('main > header.hero, main > section.topic')].filter(p => getComputedStyle(p).display !== 'none').map(p => p.id)"
TABS = "() => [...document.querySelectorAll('nav.toc a[href^=\"#\"]')].map(a => a.getAttribute('href').slice(1))"

with sync_playwright() as p:
    b = p.chromium.launch(channel="chrome")
    for mode in ["desktop", "phone"]:
        ctx = b.new_context(**p.devices["iPhone 13"]) if mode == "phone" else b.new_context(viewport={"width": 1400, "height": 900})
        pg = ctx.new_page()
        errs = []
        pg.on("pageerror", lambda e: errs.append(str(e)))
        pg.on("console", lambda m: errs.append(m.text) if m.type == "error" else None)
        pg.goto(URL)
        pg.wait_for_timeout(400)
        t = f"[{mode}] "
        tabs = pg.evaluate(TABS)
        check(t + "load shows only the first tab", pg.evaluate(VISIBLE) == tabs[:1], pg.evaluate(VISIBLE))
        if SHOTS:
            pg.screenshot(path=str(SHOTS / f"{mode}-start.png"))

        second = tabs[1]
        pg.click(f'nav.toc a[href="#{second}"]')
        pg.wait_for_timeout(200)
        check(t + f"nav opens #{second} only, marked on, at top",
              pg.evaluate(VISIBLE) == [second] and pg.evaluate("location.hash") == "#" + second
              and pg.evaluate("document.querySelector('nav.toc a.on').getAttribute('href')") == "#" + second and pg.evaluate("scrollY") == 0,
              (pg.evaluate(VISIBLE), pg.evaluate("scrollY")))
        pg.locator(f"#{second} .pager a.nx").click()
        pg.wait_for_timeout(200)
        check(t + "pager next opens the next tab", pg.evaluate(VISIBLE) == [tabs[2]], pg.evaluate(VISIBLE))
        pg.go_back()
        pg.wait_for_timeout(200)
        check(t + "browser back returns", pg.evaluate(VISIBLE) == [second], pg.evaluate(VISIBLE))

        # a cross-tab jump from the quiz offers a way back to the exact spot
        if pg.locator("#quiz-root .q").count():
            pg.goto(URL + "#quiz")
            pg.wait_for_timeout(300)
            link = pg.locator('#quiz-root .q-top a[href^="#"]').last
            link.scroll_into_view_if_needed()
            y0, dest = pg.evaluate("scrollY"), link.get_attribute("href")[1:]
            link.click()
            pg.wait_for_timeout(200)
            check(t + f"quiz revise link opens #{dest}", pg.evaluate(VISIBLE) == [dest], pg.evaluate(VISIBLE))
            bp = pg.locator(".backpill")
            check(t + "back pill shown", bp.is_visible())
            bp.click()
            pg.wait_for_timeout(200)
            check(t + "back pill returns to the same spot", pg.evaluate(VISIBLE) == ["quiz"] and abs(pg.evaluate("scrollY") - y0) < 3, (y0, pg.evaluate("scrollY")))
            # answers survive a reload
            pg.locator("#quiz-root .q input[type=checkbox], #quiz-root .q input[type=radio]").first.check()
            pg.reload()
            pg.wait_for_timeout(300)
            check(t + "quiz answer survives reload", pg.locator("#quiz-root .q input[type=checkbox], #quiz-root .q input[type=radio]").first.is_checked())
            check(t + "progress counts it", (pg.text_content("#quiz-progress") or "").startswith("1 /"), pg.text_content("#quiz-progress"))

        # a deep link to an id inside a section opens that section
        inner = pg.evaluate("(() => { const e = [...document.querySelectorAll('main section.topic [id]')].find(x => !x.closest('svg, #quiz-root')); return e ? [e.id, e.closest('section.topic').id] : null; })()")
        if inner:
            pg.goto(URL + "#" + inner[0])
            pg.wait_for_timeout(300)
            check(t + f"deep link #{inner[0]} opens #{inner[1]}", pg.evaluate(VISIBLE) == [inner[1]], pg.evaluate(VISIBLE))

        # a tapped box opens its card inline, right after its figure, in view
        sec = pg.evaluate("document.querySelector('main section.topic [data-k]').closest('section.topic').id")
        pg.goto(URL + "#" + sec)
        pg.wait_for_timeout(300)
        hot = pg.locator(f"#{sec} [data-k]").first
        hot.scroll_into_view_if_needed()
        hot.click()
        pg.wait_for_timeout(600)
        info = pg.evaluate("""() => { const d = document.getElementById('drawer'), r = d.getBoundingClientRect();
            return { open: d.classList.contains('open'), afterFig: !!d.previousElementSibling && d.previousElementSibling.tagName === 'FIGURE',
                     pos: getComputedStyle(d).position, top: r.top, vh: innerHeight }; }""")
        check(t + "card opens inline right under its diagram", info["open"] and info["afterFig"] and info["pos"] == "static", info)
        check(t + "card is in the viewport", 0 <= info["top"] < info["vh"], info)
        if SHOTS:
            pg.screenshot(path=str(SHOTS / f"{mode}-card.png"))
        pg.click("#dr-close")
        check(t + "close hides the card", not pg.evaluate("document.getElementById('drawer').classList.contains('open')"))

        # "reviewed" tick persists
        rv = pg.locator(f"#{sec} .revbtn")
        if rv.count():
            rv.click()
            pg.reload()
            pg.wait_for_timeout(300)
            check(t + "reviewed tick survives reload", pg.locator(f"#{sec} .revbtn").get_attribute("aria-pressed") == "true")

        # every clickable part opens its own card
        pg.goto(URL + "#selftest")
        pg.reload()
        pg.wait_for_timeout(500)
        st = pg.evaluate("document.body.dataset.selftest")
        check(t + f"selftest ({st})", st is not None and " 0 failed" in st and not st.startswith("0 parts"), st)
        check(t + "no horizontal page scroll", pg.evaluate("document.documentElement.scrollWidth <= innerWidth"), pg.evaluate("[document.documentElement.scrollWidth, innerWidth]"))
        check(t + "no console or page errors", not errs, errs[:3])
        ctx.close()
    b.close()
print("FAILED:", fails if fails else "none")
sys.exit(1 if fails else 0)
