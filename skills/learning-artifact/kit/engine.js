(function () {
  // DATA = { key, info, quiz } is injected above this line by build.py.
  // UI words; a page in another language overrides any of them in meta.json "ui"
  const T = Object.assign({ question: "Question", revise: "revise", sure: "sure", unsure: "unsure", choose: "Choose…", answer: "Answer",
    check: "Check", show: "Show answer", wrongTicks: " (wrong ticks subtract)", answered: "answered", allAnswered: "all answered: press Check all", score: "Score",
    swipe: "↔ swipe sideways, or turn the phone", fit: "Fit whole", actual: "Actual size", pinch: "pinch to zoom in",
    mark: "Mark {x} as reviewed", reviewed: "✓ {x} reviewed", reviewedCount: "{n} of {m} reviewed", onlyStressed: "Only the {n} stressed", showAll: "Show all points",
    source: "Source", sourceDefault: "course material", readSection: "Read the full section →", back: "↩ Back to", pager: "Previous and next section" }, DATA.ui || {});
  const fill = (s, o) => s.replace(/\{(\w+)\}/g, (m, k) => o[k]);
  const nav = document.querySelector("nav.toc"), ol = nav && nav.querySelector("ol");
  const store = {
    get(k, d) { try { const v = JSON.parse(localStorage.getItem(DATA.key + "-" + k)); return v == null ? d : v; } catch (e) { return d; } },
    set(k, v) { try { localStorage.setItem(DATA.key + "-" + k, JSON.stringify(v)); } catch (e) {} }
  };
  const tabOf = id => nav && nav.querySelector('a[href="#' + id + '"]');
  const label = (id, short) => { const s = tabOf(id) ? tabOf(id).querySelectorAll("span") : []; return s.length < 2 ? id : short ? s[1].textContent : s[0].textContent + " " + s[1].textContent; };

  // ---------- quiz: built from DATA.quiz, answers saved per viewer ----------
  const Q = DATA.quiz, root = document.getElementById("quiz-root");
  if (root) {
    let current = "";
    Q.forEach((q, i) => {
      if (q.topic !== current) { current = q.topic; const h = document.createElement("h3"); h.textContent = q.topic; root.appendChild(h); }
      const el = document.createElement("div"); el.className = "q"; el.id = "q" + (i + 1);
      const rev = q.sec ? '<a href="#' + q.sec + '">' + T.revise + ' ' + label(q.sec, true) + ' →</a> ' : "";
      let body = '<div class="q-top"><span>' + T.question + ' ' + (i + 1) + ' · ' + q.topic + '</span><span>' + rev + '<span class="pill ' + (q.conf === "sure" ? "ok" : "warn") + '">' + (q.conf === "sure" ? T.sure : T.unsure) + '</span></span></div>';
      body += '<div class="q-text">' + q.q + '</div>' + (q.q2 ? '<div class="q-lt">' + q.q2 + '</div>' : "");
      if (q.yours) body += '<div class="yours">' + q.yours + '</div>';
      if (q.type === "multi" || q.type === "single") {
        body += '<div class="opts">';
        q.opts.forEach((o, j) => { const id = "q" + i + "o" + j; body += '<label class="opt" for="' + id + '"><input id="' + id + '" type="' + (q.type === "single" ? "radio" : "checkbox") + '" name="q' + i + '"><span>' + o[0] + '</span></label>'; });
        body += '</div>';
      } else if (q.type === "match") {
        body += '<div class="match">';
        q.items.forEach((it, j) => { const id = "q" + i + "m" + j; body += '<label class="item" for="' + id + '">' + it[0] + '</label><select id="' + id + '"><option value="">' + T.choose + '</option>' + q.choices.map(c => '<option>' + c + '</option>').join("") + '</select><div class="key" hidden>' + T.answer + ': ' + it[1] + '</div>'; });
        body += '</div>';
      } else if (q.type === "number") {
        body += '<div class="numrow"><label for="q' + i + 'n">' + T.answer + (q.unit ? ", " + q.unit : "") + '</label><input id="q' + i + 'n" inputmode="decimal"></div>';
      }
      body += '<div class="q-actions"><button type="button" class="primary" data-act="check">' + T.check + '</button><button type="button" data-act="show">' + T.show + '</button><span class="result" aria-live="polite"></span></div>';
      body += '<div class="expl" hidden><p>' + q.why + '</p></div>';
      el.innerHTML = body; root.appendChild(el); q.el = el;
      el.querySelector('[data-act="check"]').addEventListener("click", () => check(q));
      el.querySelector('[data-act="show"]').addEventListener("click", () => reveal(q));
    });
    function check(q) {
      const el = q.el; let pts = 0, max = 0;
      if (q.type === "multi" || q.type === "single") {
        el.querySelectorAll(".opt").forEach((lab, j) => {
          const on = lab.querySelector("input").checked, right = q.opts[j][1];
          lab.classList.remove("right", "wrong", "missed", "key");
          if (right) max++;
          if (on && right) { lab.classList.add("right"); pts++; } else if (on && !right) { lab.classList.add("wrong"); pts--; } else if (!on && right) lab.classList.add("missed");
        });
        pts = Math.max(0, pts);
      } else if (q.type === "match") {
        el.querySelectorAll(".match select").forEach((s, j) => { max++; s.classList.remove("right", "wrong"); if (!s.value) return; if (s.value === q.items[j][1]) { s.classList.add("right"); pts++; } else s.classList.add("wrong"); });
      } else {
        max = 1; const v = parseFloat(el.querySelector("input").value.replace(",", "."));
        if (Math.abs(v - q.answer) <= (q.tol == null ? 0.5 : q.tol)) pts = 1;
      }
      q.score = max ? pts / max : 0;
      el.querySelector(".result").textContent = pts + " / " + max + (q.type === "multi" ? T.wrongTicks : "");
      el.querySelector(".expl").hidden = false;
      return q.score;
    }
    function reveal(q) {
      const el = q.el;
      if (q.type === "multi" || q.type === "single") el.querySelectorAll(".opt").forEach((lab, j) => lab.classList.toggle("key", q.opts[j][1]));
      else if (q.type === "match") el.querySelectorAll(".match .key").forEach(k => { k.hidden = false; });
      else el.querySelector(".result").textContent = T.answer + ": " + q.answer + (q.unit ? " " + q.unit : "");
      el.querySelector(".expl").hidden = false;
    }
    const qState = q => [...q.el.querySelectorAll("input, select")].map(x => x.type === "checkbox" || x.type === "radio" ? (x.checked ? 1 : 0) : x.value);
    const answered = q => qState(q).some(v => !!v);
    const prog = document.getElementById("quiz-progress"), scoreAll = document.getElementById("score-all");
    function saveQuiz() { store.set("quiz", Q.map(qState)); if (prog) prog.textContent = Q.filter(answered).length + " / " + Q.length + " " + T.answered; }
    const saved = store.get("quiz", null);
    if (saved) Q.forEach((q, i) => { const v = saved[i]; if (v) q.el.querySelectorAll("input, select").forEach((x, j) => { if (x.type === "checkbox" || x.type === "radio") x.checked = !!v[j]; else if (v[j] != null) x.value = v[j]; }); });
    root.addEventListener("change", saveQuiz); root.addEventListener("input", saveQuiz);
    const btn = id => document.getElementById(id) || { addEventListener() {} };
    btn("btn-check-all").addEventListener("click", () => { let s = 0; Q.forEach(q => { s += check(q); }); scoreAll.textContent = T.score + ": " + s.toFixed(1) + " / " + Q.length + " (" + Math.round(100 * s / Q.length) + "%)"; });
    btn("btn-reveal-all").addEventListener("click", () => Q.forEach(reveal));
    btn("btn-reset-all").addEventListener("click", () => {
      Q.forEach(q => {
        q.el.querySelectorAll("input").forEach(x => { if (x.type === "checkbox" || x.type === "radio") x.checked = false; else x.value = ""; });
        q.el.querySelectorAll("select").forEach(x => { x.value = ""; x.classList.remove("right", "wrong"); });
        q.el.querySelectorAll(".opt").forEach(x => x.classList.remove("right", "wrong", "missed", "key"));
        q.el.querySelectorAll(".key").forEach(k => { if (k.tagName === "DIV") k.hidden = true; });
        q.el.querySelector(".expl").hidden = true; q.el.querySelector(".result").textContent = "";
      });
      scoreAll.textContent = ""; saveQuiz();
    });
    btn("btn-next").addEventListener("click", () => {
      const next = Q.find(q => !answered(q) && q.el.getBoundingClientRect().top > innerHeight * 0.35) || Q.find(q => !answered(q));
      if (next) next.el.scrollIntoView({ block: "start" }); else if (prog) prog.textContent = T.allAnswered;
    });
    saveQuiz();
  }

  // ---------- wide diagrams: swipe hint and fit-to-width on narrow screens ----------
  const figs = [...document.querySelectorAll("figure.fig")];
  figs.forEach(fig => {
    const canvas = fig.querySelector(".canvas"); if (!canvas) return;
    const bar = document.createElement("div"); bar.className = "figbar";
    bar.innerHTML = '<span>' + T.swipe + '</span><button type="button">' + T.fit + '</button>';
    const b = bar.querySelector("button");
    b.addEventListener("click", () => {
      const fit = fig.classList.toggle("fit");
      b.textContent = fit ? T.actual : T.fit;
      bar.firstChild.textContent = fit ? T.pinch : T.swipe;
    });
    canvas.before(bar);
  });
  function layout() {
    figs.forEach(fig => { const c = fig.querySelector(".canvas"); if (c) fig.classList.toggle("pans", fig.classList.contains("fit") || c.scrollWidth > c.clientWidth + 2); });
    const phone = matchMedia("(max-width: 880px)").matches, qt = document.querySelector(".quiz-tools");
    if (nav) document.documentElement.style.setProperty("--navh", phone ? nav.offsetHeight + "px" : "0px");
    if (qt) document.documentElement.style.setProperty("--qth", qt.offsetHeight + "px");
    document.querySelectorAll(".tbl").forEach(t => { t.classList.remove("stick"); const r = t.querySelector("tr"); t.classList.toggle("stick", !!r && r.children.length > 2 && t.scrollWidth > t.clientWidth + 2); });
  }
  layout(); addEventListener("resize", layout); addEventListener("load", layout);

  // ---------- study aids: "reviewed" tick per section marked data-review, "stressed only" view of recording notes ----------
  const units = [...document.querySelectorAll("section.topic[data-review]")];
  const reviewed = new Set(store.get("reviewed", []));
  const brand = nav && nav.querySelector(".brand");
  const count = brand && units.length ? brand.insertAdjacentElement("afterend", document.createElement("div")) : null;
  if (count) count.className = "rvcount";
  function paintReviewed() {
    units.forEach(sec => {
      const on = reviewed.has(sec.id), b = sec.querySelector(".revbtn");
      b.setAttribute("aria-pressed", on); b.textContent = fill(on ? T.reviewed : T.mark, { x: label(sec.id) });
      const a = tabOf(sec.id); if (a) a.classList.toggle("done", on);
    });
    if (count) count.textContent = fill(T.reviewedCount, { n: reviewed.size, m: units.length });
  }
  units.forEach(sec => {
    const b = document.createElement("button"); b.type = "button"; b.className = "revbtn";
    b.addEventListener("click", () => { reviewed.has(sec.id) ? reviewed.delete(sec.id) : reviewed.add(sec.id); store.set("reviewed", [...reviewed]); paintReviewed(); });
    sec.appendChild(b);
  });
  paintReviewed();
  const recs = [...document.querySelectorAll(".rec")].filter(r => r.querySelector("li .pill.warn"));
  function paintStressed() {
    const on = document.body.classList.contains("stressed");
    recs.forEach(r => { const b = r.querySelector(".only"); b.setAttribute("aria-pressed", on); b.textContent = on ? T.showAll : fill(T.onlyStressed, { n: r.querySelectorAll("li .pill.warn").length }); });
  }
  recs.forEach(r => {
    const b = document.createElement("button"); b.type = "button"; b.className = "only";
    b.addEventListener("click", () => {
      const top = r.getBoundingClientRect().top;
      document.body.classList.toggle("stressed"); store.set("stressed", document.body.classList.contains("stressed")); paintStressed();
      scrollBy(0, r.getBoundingClientRect().top - top);
    });
    r.querySelector(".rec-h").appendChild(b);
  });
  if (store.get("stressed", false)) document.body.classList.add("stressed");
  paintStressed(); layout();

  // ---------- detail cards: a tapped diagram box opens its card inline, right under the diagram ----------
  const INFO = DATA.info, dr = document.getElementById("drawer");
  const drT = document.getElementById("dr-title"), drB = document.getElementById("dr-body"), drS = document.getElementById("dr-src");
  const drX = document.getElementById("dr-exam"), drG = document.getElementById("dr-go"), drC = document.getElementById("dr-close");
  let activeEl = null;
  function openCard(el) {
    const it = INFO[el.dataset.k]; if (!it) return;
    if (activeEl) activeEl.classList.remove("sel");
    activeEl = el; el.classList.add("sel");
    drT.textContent = it.t; drB.textContent = it.d; drS.textContent = T.source + ": " + (it.s || T.sourceDefault);
    drX.hidden = !it.x; drX.querySelector("span").textContent = it.x || "";
    drG.hidden = !it.a; drG.href = "#" + (it.a || ""); drG.textContent = T.readSection;
    const fig = el.closest("figure");
    if (fig && fig.nextElementSibling !== dr) fig.after(dr);
    dr.classList.add("open"); dr.setAttribute("aria-hidden", "false");
    // scroll to show the card, but never past the tapped box; the card's start always shows
    const navh = parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--navh")) || 0;
    const r = dr.getBoundingClientRect(), b = el.getBoundingClientRect();
    const d = Math.max(Math.min(r.bottom - innerHeight + 12, b.top - navh - 12), r.top - innerHeight + Math.min(r.height, 160));
    if (d > 0) scrollBy({ top: d, behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
    document.body.dataset.card = el.dataset.k;
  }
  function closeCard() {
    dr.classList.remove("open"); dr.setAttribute("aria-hidden", "true");
    if (activeEl) { activeEl.classList.remove("sel"); try { activeEl.focus({ preventScroll: true }); } catch (e) {} }
    activeEl = null;
  }
  document.querySelectorAll("[data-k]").forEach(el => {
    el.addEventListener("click", () => openCard(el));
    el.addEventListener("keydown", e => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); openCard(el); } });
  });
  drC.addEventListener("click", closeCard);
  drG.addEventListener("click", () => { dr.classList.remove("open"); dr.setAttribute("aria-hidden", "true"); if (activeEl) activeEl.classList.remove("sel"); activeEl = null; });
  document.addEventListener("keydown", e => { if (e.key === "Escape" && dr.classList.contains("open")) closeCard(); });

  // ---------- tabs: one section on screen at a time; every "#id" link opens the tab that holds it ----------
  const main = document.querySelector("main");
  const panes = [...main.querySelectorAll(":scope > header.hero, :scope > section.topic")];
  panes.forEach((p, i) => {
    const pg = document.createElement("nav"); pg.className = "pager"; pg.setAttribute("aria-label", T.pager);
    if (i > 0) pg.innerHTML += '<a class="pv" href="#' + panes[i - 1].id + '">← ' + label(panes[i - 1].id) + '</a>';
    if (i < panes.length - 1) pg.innerHTML += '<a class="nx" href="#' + panes[i + 1].id + '">' + label(panes[i + 1].id) + ' →</a>';
    p.appendChild(pg);
  });
  document.body.classList.add("tabs");
  let current = null;
  function route(hash, y) {
    const el = (hash.length > 1 && document.getElementById(decodeURIComponent(hash.slice(1)))) || panes[0];
    const pane = panes.find(p => p.contains(el)) || panes[0];
    if (pane !== current) {
      panes.forEach(p => p.classList.toggle("pane-on", p === pane)); current = pane;
      if (nav) nav.querySelectorAll("a.on").forEach(a => a.classList.remove("on"));
      const a = tabOf(pane.id);
      if (a) { a.classList.add("on"); if (ol.scrollWidth > ol.clientWidth) ol.scrollTo({ left: a.parentElement.offsetLeft - 16 }); }
      layout();
    }
    // instant, not smooth: the page CSS sets scroll-behavior: smooth, which would break the back pill's restore
    if (y != null) scrollTo({ top: y, behavior: "instant" });
    else if (el === pane) scrollTo({ top: 0, behavior: "instant" });
    else el.scrollIntoView({ block: "start", behavior: "instant" });
  }
  const back = document.createElement("button"); back.type = "button"; back.className = "backpill"; back.hidden = true;
  document.body.appendChild(back);
  let from = null;
  document.addEventListener("click", e => {
    const a = e.target.closest('a[href^="#"]');
    if (!a || a.getAttribute("href").length < 2 || e.metaKey || e.ctrlKey) return;
    e.preventDefault();
    const hash = a.getAttribute("href"), target = document.getElementById(hash.slice(1));
    const jump = !a.closest("nav.toc, .pager") && target && !current.contains(target);
    if (jump) { from = { hash: "#" + current.id, y: scrollY }; back.textContent = T.back + " " + label(current.id, true); back.hidden = false; }
    else back.hidden = true;
    history.pushState(null, "", hash); route(hash);
  });
  back.addEventListener("click", () => { if (from) { history.pushState(null, "", from.hash); route(from.hash, from.y); } back.hidden = true; from = null; });
  addEventListener("popstate", () => { back.hidden = true; route(location.hash); });

  // #selftest: open every card once and record the result for check.py
  if (location.hash === "#selftest") {
    const all = document.querySelectorAll("[data-k]"); let bad = 0;
    all.forEach(el => { openCard(el); if (drT.textContent !== INFO[el.dataset.k].t) bad++; });
    document.body.dataset.selftest = all.length + " parts, " + bad + " failed, quiz " + document.querySelectorAll(".q").length;
    closeCard();
  }
  route(location.hash);
})();
