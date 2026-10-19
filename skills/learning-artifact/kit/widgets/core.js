// Widget toolkit. A widget is <div class="wg" data-wg="name"></div> in page.html and WG.name = root => { ... } in a widgets/*.js file.
// Every widget builds itself from H helpers, so sliders, readouts and plots look the same everywhere.
const WG = {};
const H = (() => {
  const SVGNS = "http://www.w3.org/2000/svg";
  // Animations here start only when the student presses ▶, and the motion IS the lesson, so they play even with
  // Reduce Motion on (it made every ▶ jump to its last frame, which reads as a dead button). Nothing moves by itself.
  const reduce = false;
  // Lithuanian number format: decimal comma, thin space never; "−" for minus
  const fmt = (x, d = 2) => {
    if (!isFinite(x)) return "—";
    let s = (+x.toFixed(d)).toString();
    if (Math.abs(x) >= 1e6 || (Math.abs(x) < 1e-3 && x !== 0)) s = x.toExponential(2).replace(/e\+?(-?)(\d+)/, (m, sg, e) => " · 10" + sup((sg ? "-" : "") + e));
    return s.replace(".", ",").replace(/^-/, "−");
  };
  const sup = s => s.split("").map(c => ({ "-": "⁻", 0: "⁰", 1: "¹", 2: "²", 3: "³", 4: "⁴", 5: "⁵", 6: "⁶", 7: "⁷", 8: "⁸", 9: "⁹" })[c] || c).join("");
  function el(tag, attrs = {}, kids = []) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) { if (k === "html") e.innerHTML = v; else if (k === "text") e.textContent = v; else if (k.startsWith("on")) e.addEventListener(k.slice(2), v); else if (v != null) e.setAttribute(k, v); }
    (Array.isArray(kids) ? kids : [kids]).forEach(c => c != null && e.append(c));
    return e;
  }
  function s(tag, attrs = {}, parent) {
    const e = document.createElementNS(SVGNS, tag);
    for (const [k, v] of Object.entries(attrs)) { if (k === "text") e.textContent = v; else if (v != null) e.setAttribute(k, v); }
    if (parent) parent.append(e);
    return e;
  }
  let uid = 0;
  // panel: header (title + subject tag) and a body; returns the body
  function panel(root, title, subj = "mf") {
    root.innerHTML = "";
    const tags = (subj.includes("m") ? '<span class="tag-m">matematika</span>' : "") + (subj.includes("f") ? '<span class="tag-f">fizika</span>' : "");
    root.append(el("div", { class: "wg-h", html: tags + "<b>" + title + "</b>" }));
    const body = el("div", { class: "wg-body" }); root.append(body);
    return body;
  }
  // slider with a live value; opts: {label, min, max, step, value, unit, subj:'m'|'f', digits, onInput}
  function slider(parent, o) {
    const id = "wg" + (++uid);
    const out = el("output", { for: id });
    const inp = el("input", { type: "range", id, min: o.min, max: o.max, step: o.step ?? 1, value: o.value });
    const box = el("div", { class: "wg-sl" + (o.subj === "f" ? " f" : "") }, [el("label", { for: id, html: o.label }), out, inp]);
    // The value lives here, not in the input: a range input snaps to its step, so an animation adding
    // 0,03 s per frame to a 0,1 s slider was rounded back every frame and froze (worse on 120 Hz screens).
    let cur = +inp.value;
    const show = () => { out.textContent = fmt(cur, o.digits ?? 2) + (o.unit ? " " + o.unit : ""); };
    inp.addEventListener("input", () => { cur = +inp.value; show(); o.onInput && o.onInput(cur); });
    show(); parent.append(box);
    return { get v() { return cur; }, set v(x) { cur = Math.min(+o.max, Math.max(+o.min, +x)); inp.value = cur; show(); }, input: inp };
  }
  function ctl(parent) { const c = el("div", { class: "wg-ctl" }); parent.append(c); return c; }
  function out(parent) { const o = el("div", { class: "wg-out", "aria-live": "polite" }); parent.append(o); return o; }
  function btns(parent, list) {
    const b = el("div", { class: "wg-btns" });
    list.forEach(([label, fn, cls]) => b.append(el("button", { type: "button", class: cls || null, onclick: fn, html: label })));
    parent.append(b); return b;
  }
  // plot: maps data coordinates to an SVG viewBox; opts {w, h, x:[min,max], y:[min,max], xl, yl, xs (tick step), ys, pad}
  function plot(parent, o) {
    const w = o.w || 480, h = o.h || 300, P = Object.assign({ l: 50, r: 14, t: 22, b: 44 }, o.pad || {});
    const stage = el("div", { class: "wg-stage" }); parent.append(stage);
    const svg = s("svg", { viewBox: `0 0 ${w} ${h}`, role: "img", "aria-label": o.aria || o.yl + " nuo " + o.xl }, stage);
    const g = { svg, w, h, P };
    g.X = o.x; g.Y = o.y;
    g.sx = x => P.l + (x - g.X[0]) / (g.X[1] - g.X[0]) * (w - P.l - P.r);
    g.sy = y => h - P.b - (y - g.Y[0]) / (g.Y[1] - g.Y[0]) * (h - P.t - P.b);
    g.ix = px => g.X[0] + (px - P.l) / (w - P.l - P.r) * (g.X[1] - g.X[0]);
    g.iy = py => g.Y[0] + (h - P.b - py) / (h - P.t - P.b) * (g.Y[1] - g.Y[0]);
    g.layer = s("g", {}, svg);
    g.axes = () => {
      const a = s("g", {}, svg); svg.insertBefore(a, g.layer);
      const xs = o.xs || nice(g.X), ys = o.ys || nice(g.Y);
      for (let x = Math.ceil(g.X[0] / xs) * xs; x <= g.X[1] + 1e-9; x += xs) { s("line", { class: "p-grid", x1: g.sx(x), x2: g.sx(x), y1: g.sy(g.Y[0]), y2: g.sy(g.Y[1]) }, a); s("text", { class: "p-tick", x: g.sx(x), y: h - P.b + 16, "text-anchor": "middle", text: fmt(x, 2) }, a); }
      for (let y = Math.ceil(g.Y[0] / ys) * ys; y <= g.Y[1] + 1e-9; y += ys) { s("line", { class: "p-grid", x1: g.sx(g.X[0]), x2: g.sx(g.X[1]), y1: g.sy(y), y2: g.sy(y) }, a); s("text", { class: "p-tick", x: P.l - 6, y: g.sy(y) + 4, "text-anchor": "end", text: fmt(y, 2) }, a); }
      const x0 = Math.min(Math.max(0, g.X[0]), g.X[1]), y0 = Math.min(Math.max(0, g.Y[0]), g.Y[1]);
      s("line", { class: "p-ax", x1: g.sx(g.X[0]), x2: g.sx(g.X[1]), y1: g.sy(y0), y2: g.sy(y0) }, a);
      s("line", { class: "p-ax", x1: g.sx(x0), x2: g.sx(x0), y1: g.sy(g.Y[0]), y2: g.sy(g.Y[1]) }, a);
      if (o.xl) s("text", { class: "p-lab", x: w - P.r, y: h - 6, "text-anchor": "end", text: o.xl }, a);
      if (o.yl) s("text", { class: "p-lab", x: 6, y: P.t + 2, "dominant-baseline": "hanging", text: o.yl }, a);
    };
    g.clear = () => { g.layer.innerHTML = ""; };
    g.fn = (f, cls = "p-m", from = g.X[0], to = g.X[1], n = 240) => {
      let d = "", pen = false;
      for (let i = 0; i <= n; i++) { const x = from + (to - from) * i / n, y = f(x); if (!isFinite(y) || y < g.Y[0] - (g.Y[1] - g.Y[0]) || y > g.Y[1] + (g.Y[1] - g.Y[0])) { pen = false; continue; } d += (pen ? "L" : "M") + g.sx(x).toFixed(1) + "," + g.sy(y).toFixed(1); pen = true; }
      return s("path", { class: cls, d, "clip-path": clip() }, g.layer);
    };
    g.poly = (pts, cls = "p-m", close = false) => s("path", { class: cls, d: pts.map((p, i) => (i ? "L" : "M") + g.sx(p[0]).toFixed(1) + "," + g.sy(p[1]).toFixed(1)).join("") + (close ? "Z" : ""), "clip-path": clip() }, g.layer);
    g.dot = (x, y, cls = "p-dot-m", r = 5) => s("circle", { class: cls, cx: g.sx(x), cy: g.sy(y), r }, g.layer);
    g.text = (x, y, t, cls = "p-txt", anchor = "start", dy = 0) => s("text", { class: cls, x: g.sx(x), y: g.sy(y) + dy, "text-anchor": anchor, text: t }, g.layer);
    g.seg = (x1, y1, x2, y2, cls = "p-mut") => s("line", { class: cls, x1: g.sx(x1), y1: g.sy(y1), x2: g.sx(x2), y2: g.sy(y2) }, g.layer);
    let clipId = null;
    function clip() {
      if (!clipId) { clipId = "cl" + (++uid); const cp = s("clipPath", { id: clipId }, svg); s("rect", { x: P.l, y: P.t, width: w - P.l - P.r, height: h - P.t - P.b }, cp); }
      return `url(#${clipId})`;
    }
    // drag a point along x (or free): calls onMove(dataX, dataY)
    g.drag = (node, onMove) => {
      node.classList.add("p-drag"); node.setAttribute("tabindex", "0");
      const pt = ev => { const r = svg.getBoundingClientRect(); return [g.ix((ev.clientX - r.left) * w / r.width), g.iy((ev.clientY - r.top) * h / r.height)]; };
      node.addEventListener("pointerdown", e => { e.preventDefault(); node.setPointerCapture(e.pointerId); const mv = ev => onMove(...pt(ev)); const up = () => { node.removeEventListener("pointermove", mv); node.removeEventListener("pointerup", up); }; node.addEventListener("pointermove", mv); node.addEventListener("pointerup", up); });
    };
    if (o.axes !== false) g.axes();
    return g;
  }
  function nice([a, b]) { const r = (b - a) / 6, p = Math.pow(10, Math.floor(Math.log10(r))), m = r / p; return (m < 1.5 ? 1 : m < 3.5 ? 2 : m < 7.5 ? 5 : 10) * p; }
  // a free SVG canvas (no axes) for drawings: returns {svg, layer}
  function canvas(parent, w, h, aria) {
    const stage = el("div", { class: "wg-stage" }); parent.append(stage);
    const svg = s("svg", { viewBox: `0 0 ${w} ${h}`, role: "img", "aria-label": aria || "" }, stage);
    return { svg, w, h, layer: s("g", {}, svg), clear() { this.layer.innerHTML = ""; } };
  }
  // animation loop: runs only while the widget is on screen; respects reduced motion (then draws single frames on demand)
  function loop(root, step) {
    let raf = 0, last = 0, on = false;
    const tick = t => { const dt = Math.min(0.05, (t - (last || t)) / 1000); last = t; if (step(dt) === false) { stop(); return; } raf = requestAnimationFrame(tick); };
    const start = () => { if (on) return; on = true; last = 0; raf = requestAnimationFrame(tick); };
    const stop = () => { on = false; cancelAnimationFrame(raf); };
    return { start, stop, get on() { return on; }, reduce };
  }
  // "2 kartus", "1,5 karto": Lithuanian count of times
  const kartus = r => { const n = Math.round(r); if (Math.abs(r - n) > 1e-9) return fmt(r, 2) + " karto"; const t = n % 100, u = n % 10; return fmt(n, 0) + (u === 0 || (t > 10 && t < 20) ? " kartų" : u === 1 ? " kartą" : " kartus"); };
  return { kartus, el, s, fmt, sup, panel, slider, ctl, out, btns, plot, canvas, loop, nice, reduce };
})();
