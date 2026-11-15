/* graph.js: the atlas's graph view. The same parts and connections as the drawing,
   laid out by force instead of by hand, the way Obsidian and graphify show a vault.

   It is an ENGINE, not a page: it knows nothing about panels, tabs or findings. atlas.js
   builds a model from the payload, mounts one of these per drawing (plus one for the
   whole atlas), and gets callbacks when a node or edge is picked. That split exists
   because two different callers use it (one diagram, all diagrams), so the seam is real.

   SVG and not <canvas>, on purpose. Every node is a DOM element with role=button, so
   hit testing is the browser's, keyboard focus works, the theme flows in through CSS
   custom properties with no repaint code, and check.mjs can drive it with the real
   mouse exactly as it drives the drawing. At atlas sizes (a few hundred nodes) a tick
   costs about a millisecond. */
(function () {
  var NS = 'http://www.w3.org/2000/svg';

  function s(tag, attrs, parent) {
    var n = document.createElementNS(NS, tag);
    if (attrs) for (var k in attrs) n.setAttribute(k, attrs[k]);
    if (parent) parent.appendChild(n);
    return n;
  }
  // Deterministic layout: the same atlas opens in the same shape every time, so "the
  // cluster on the left" means something on the second visit and in a screenshot.
  function seeded(str) {
    var h = 2166136261;
    for (var i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 16777619); }
    return function () {
      h += 0x6D2B79F5;
      var t = h;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // SHAPE IS THE SECOND ENCODING, not decoration. Six component types in a node-link view
  // put every pair of hues next to each other somewhere, and the validator
  // (dataviz/scripts/validate_palette.js) fails any palette past three slots on all
  // pairs. So type is carried twice: hue, and a shape a colour-blind reader can still
  // tell apart. External is a hollow ring: outside the system, so drawn as an outline.
  var SHAPE = { frontend: 'circle', backend: 'hex', database: 'square', cloud: 'tri',
                security: 'diamond', messagebus: 'pill', external: 'ring' };
  function shapeOf(type) { return SHAPE[type] || 'circle'; }
  function shapePath(kind, r) {
    var p, i, a;
    switch (kind) {
      case 'square':
        var h = r * 0.9, c = r * 0.32;
        return 'M' + (-h + c) + ',' + (-h) + 'H' + (h - c) + 'Q' + h + ',' + (-h) + ' ' + h + ',' + (-h + c) +
          'V' + (h - c) + 'Q' + h + ',' + h + ' ' + (h - c) + ',' + h + 'H' + (-h + c) +
          'Q' + (-h) + ',' + h + ' ' + (-h) + ',' + (h - c) + 'V' + (-h + c) + 'Q' + (-h) + ',' + (-h) + ' ' + (-h + c) + ',' + (-h) + 'Z';
      case 'diamond':
        a = r * 1.22;
        return 'M0,' + (-a) + 'L' + a + ',0L0,' + a + 'L' + (-a) + ',0Z';
      case 'hex':
        p = [];
        for (i = 0; i < 6; i++) {
          a = Math.PI / 3 * i + Math.PI / 6;
          p.push((Math.cos(a) * r * 1.08).toFixed(2) + ',' + (Math.sin(a) * r * 1.08).toFixed(2));
        }
        return 'M' + p.join('L') + 'Z';
      case 'tri':
        a = r * 1.3;
        return 'M0,' + (-a) + 'L' + (a * 0.94) + ',' + (a * 0.62) + 'L' + (-a * 0.94) + ',' + (a * 0.62) + 'Z';
      case 'pill':
        var w = r * 1.35, hh = r * 0.78;
        return 'M' + (-w + hh) + ',' + (-hh) + 'H' + (w - hh) + 'A' + hh + ',' + hh + ' 0 0 1 ' + (w - hh) + ',' + hh +
          'H' + (-w + hh) + 'A' + hh + ',' + hh + ' 0 0 1 ' + (-w + hh) + ',' + (-hh) + 'Z';
      default:
        return 'M' + (-r) + ',0A' + r + ',' + r + ' 0 1 0 ' + r + ',0A' + r + ',' + r + ' 0 1 0 ' + (-r) + ',0Z';
    }
  }

  // Convex hull (monotone chain), then a closed Catmull-Rom so a zone reads as a soft
  // region rather than a polygon somebody drew with a ruler.
  function hull(pts) {
    if (pts.length < 3) return pts.slice();
    pts = pts.slice().sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });
    function cross(o, a, b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }
    var lo = [], up = [], i;
    for (i = 0; i < pts.length; i++) {
      while (lo.length >= 2 && cross(lo[lo.length - 2], lo[lo.length - 1], pts[i]) <= 0) lo.pop();
      lo.push(pts[i]);
    }
    for (i = pts.length - 1; i >= 0; i--) {
      while (up.length >= 2 && cross(up[up.length - 2], up[up.length - 1], pts[i]) <= 0) up.pop();
      up.push(pts[i]);
    }
    up.pop(); lo.pop();
    return lo.concat(up);
  }
  function smooth(p) {
    var n = p.length;
    if (n < 3) return '';
    var d = 'M' + p[0][0].toFixed(1) + ',' + p[0][1].toFixed(1);
    for (var i = 0; i < n; i++) {
      var p0 = p[(i - 1 + n) % n], p1 = p[i], p2 = p[(i + 1) % n], p3 = p[(i + 2) % n];
      d += 'C' + (p1[0] + (p2[0] - p0[0]) / 6).toFixed(1) + ',' + (p1[1] + (p2[1] - p0[1]) / 6).toFixed(1) +
        ' ' + (p2[0] - (p3[0] - p1[0]) / 6).toFixed(1) + ',' + (p2[1] - (p3[1] - p1[1]) / 6).toFixed(1) +
        ' ' + p2[0].toFixed(1) + ',' + p2[1].toFixed(1);
    }
    return d + 'Z';
  }

  var reduced = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* model = {
       nodes: [{id, label, type, group, inside, badge}],
       links: [{id, source, target, label, dashed, weight}],
       zones: [{label, kind, members:[node ids]}],
     }
     opts = {seed, onNode(id), onEdge(id), onOpen(id), onBackground(), onLevel(text),
             dense: bool, d3: bool, spin: bool} */
  function Graph(host, model, opts) {
    this.host = host;
    this.opts = opts || {};
    this.model = model;
    this.built = false;
    this.k = 1; this.tx = 0; this.ty = 0;
    this.homeK = 1;
    this.follow = true;          // the camera tracks the bloom until the reader takes over
    this.alpha = 1; this.alphaTarget = 0;
    this.raf = 0;
    this.hoverId = null;
    this.selId = null;
    // 3D is the same engine with a depth axis and an orbit camera, still SVG: every node
    // stays a DOM button, so the panel, keyboard and check.mjs work unchanged. `amt`
    // blends 2D into 3D (0..1), and at 0 every number is the 2D engine's exactly.
    this.d3 = !!this.opts.d3;
    this.amt = this.d3 ? 1 : 0;
    this.yaw = 0; this.pitch = 0; this.rotTo = null;
    this.R = 0;
    this.spinOK = !!this.opts.spin && !reduced;
    this.spinning = false; this.paused = false;
  }

  Graph.prototype.build = function () {
    var self = this, m = this.model, host = this.host, rand = seeded(this.opts.seed || 'atlas');
    var byId = {};
    var nodes = m.nodes.map(function (n) {
      var o = { id: n.id, label: n.label, type: n.type || '', group: n.group, inside: !!n.inside,
                badge: n.badge || 0, deg: 0, x: 0, y: 0, vx: 0, vy: 0, fx: null, fy: null, zone: -1,
                z: 0, vz: 0, fz: null, px: 0, py: 0, s: 1, Z: 0, dep: 0.5 };
      byId[n.id] = o;
      return o;
    });
    var links = [];
    m.links.forEach(function (l) {
      var a = byId[l.source], b = byId[l.target];
      if (!a || !b) return;
      a.deg++; b.deg++;
      links.push({ id: l.id, s: a, t: b, label: l.label || '', dashed: !!l.dashed,
                   weight: l.weight || 1, bend: 0 });
    });
    // Parallel edges between one pair fan out as curves, or they print on top of each
    // other and the second one cannot be clicked: the occlusion the drawing has too.
    var pairs = {};
    links.forEach(function (l) {
      var key = l.s.id < l.t.id ? l.s.id + '\u0000' + l.t.id : l.t.id + '\u0000' + l.s.id;
      (pairs[key] = pairs[key] || []).push(l);
    });
    Object.keys(pairs).forEach(function (k) {
      var list = pairs[k];
      if (list.length < 2) return;
      list.forEach(function (l, i) {
        var off = (i - (list.length - 1) / 2) * 22;
        // A link drawn t->s bends the other way in its own frame; normalise so the fan is
        // symmetric whatever direction each arrow points.
        l.bend = (l.s.id < l.t.id) ? off : -off;
      });
    });
    nodes.forEach(function (n) { n.nb = []; });
    links.forEach(function (l) {
      if (l.s.nb.indexOf(l.t) < 0) l.s.nb.push(l.t);
      if (l.t.nb.indexOf(l.s) < 0) l.t.nb.push(l.s);
    });
    var maxDeg = 1;
    nodes.forEach(function (n) { maxDeg = Math.max(maxDeg, n.deg); });
    var dense = this.opts.dense || nodes.length > 40;
    nodes.forEach(function (n) {
      n.r = Math.min(dense ? 15 : 17, (dense ? 4.2 : 6.5) + (dense ? 2.0 : 2.5) * Math.sqrt(n.deg + n.badge));
      n.shape = shapeOf(n.type);
      // Labels: a small drawing labels everything; a dense one labels its hubs and lets
      // the rest arrive with zoom, as Obsidian's text-fade threshold does.
      n.tier = !dense ? 'hub' : (n.deg >= Math.max(4, maxDeg * 0.45) || n.badge > 1) ? 'hub'
        : n.deg >= 2 ? 'mid' : 'leaf';
    });
    (m.zones || []).forEach(function (z, zi) {
      z.members.forEach(function (id) { if (byId[id] && byId[id].zone < 0) byId[id].zone = zi; });
    });
    this.nodes = nodes; this.links = links; this.byId = byId; this.dense = dense;
    this.zones = (m.zones || []).map(function (z, zi) {
      return { label: z.label, kind: z.kind || 'region', members: z.members.filter(function (id) { return byId[id]; }), i: zi };
    }).filter(function (z) { return z.members.length; });

    // Phyllotaxis start, like d3: even, deterministic, and it blooms outward rather than
    // exploding from a point. Zone members start near each other so the hulls form early.
    var zc = {};
    this.zones.forEach(function (z, i) {
      var a = (i / Math.max(1, self.zones.length)) * Math.PI * 2;
      zc[i] = [Math.cos(a) * 140, Math.sin(a) * 140];
    });
    nodes.forEach(function (n, i) {
      var rad = 10 * Math.sqrt(0.5 + i), ang = i * Math.PI * (3 - Math.sqrt(5));
      var base = n.zone >= 0 ? zc[n.zone] : [0, 0];
      n.x = base[0] + rad * Math.cos(ang) * 0.6 + (rand() - 0.5) * 4;
      n.y = base[1] + rad * Math.sin(ang) * 0.6 + (rand() - 0.5) * 4;
    });
    if (this.d3) this.inflate();

    links.forEach(function (l) {
      l.dist = (dense ? 46 : 78) + l.s.r + l.t.r + (l.s.zone !== l.t.zone ? (dense ? 24 : 40) : 0);
      // A link that crosses a zone line pulls more weakly than one inside a zone, so
      // zones hold together as regions and the crossing reads as a hand-over between them.
      var cross = l.s.zone >= 0 && l.t.zone >= 0 && l.s.zone !== l.t.zone;
      l.str = 0.9 / Math.min(l.s.deg, l.t.deg) * (cross ? 0.3 : 1);
      l.bias = l.s.deg / (l.s.deg + l.t.deg);
    });

    // ---- DOM ----
    host.textContent = '';
    var svg = s('svg', { class: 'gsvg' + (this.d3 ? ' g3d' : ''), role: 'group', 'aria-label': (this.opts.title || 'Graph') +
      ': ' + nodes.length + ' parts, ' + links.length + ' connections' }, host);
    var world = s('g', { class: 'gworld' }, svg);
    var zl = s('g', { class: 'gzones' }, world);
    var ll = s('g', { class: 'glinks' }, world);
    var nl = s('g', { class: 'gnodes' }, world);
    var tl = s('g', { class: 'gtags' }, world);
    this.svg = svg; this.world = world; this.nl = nl;

    this.zones.forEach(function (z) {
      z.el = s('path', { class: 'gzone' + (z.kind === 'security-group' ? ' trust' : '') }, zl);
      z.tag = s('text', { class: 'gzlabel' }, zl);
      z.tag.textContent = z.label;
    });

    links.forEach(function (l) {
      var g = s('g', { class: 'glink' + (l.dashed ? ' dashed' : ''), 'data-glink': l.id }, ll);
      l.hit = s('path', { class: 'ghit' }, g);
      l.line = s('path', { class: 'gline' }, g);
      if (l.weight > 1) l.line.style.strokeWidth = (1.1 + Math.min(3, l.weight - 1) * 0.55) + 'px';
      l.flow = s('path', { class: 'gflow' }, g);
      l.head = s('path', { class: 'ghead' }, g);
      if (l.label) {
        l.tag = s('text', { class: 'gelabel' }, tl);
        l.tag.textContent = l.label;
      }
      l.el = g;
    });

    nodes.forEach(function (n) {
      var g = s('g', { class: 'gnode', 'data-gnode': n.id, 'data-type': n.type || 'other',
                       'data-tier': n.tier, tabindex: '0', role: 'button',
                       'aria-label': n.label + (n.type ? ', ' + n.type : '') }, nl);
      g.style.setProperty('--c', 'var(--gt-' + (SHAPE[n.type] ? n.type : 'other') + ')');
      // The body carries the depth fog, so the dimming on .gnode multiplies with it
      // instead of fighting it for one opacity.
      var bd = s('g', { class: 'gbody' }, g);
      s('circle', { class: 'ghalo', r: (n.r * 2.3).toFixed(1) }, bd);
      if (n.inside) s('circle', { class: 'gorbit', r: (n.r * 1.62).toFixed(1) }, bd);
      s('path', { class: 'gring', d: shapePath(n.shape, n.r) }, bd);
      s('path', { class: 'gdot' + (n.shape === 'ring' ? ' hollow' : ''), d: shapePath(n.shape, n.r) }, bd);
      if (n.shape !== 'ring') s('ellipse', { class: 'gshine', cx: (-n.r * 0.28).toFixed(1), cy: (-n.r * 0.34).toFixed(1),
                                             rx: (n.r * 0.42).toFixed(1), ry: (n.r * 0.26).toFixed(1) }, bd);
      s('circle', { class: 'gsel', r: (n.r * 1.5 + 3).toFixed(1) }, bd);
      if (n.badge > 1) {
        var b = s('g', { class: 'gbadge', transform: 'translate(' + (n.r * 0.95).toFixed(1) + ',' + (-n.r * 0.95).toFixed(1) + ')' }, bd);
        s('circle', { r: 7 }, b);
        var bt = s('text', { dy: '.35em' }, b);
        bt.textContent = String(n.badge);
      }
      var t = s('text', { class: 'glabel', y: (n.r * 1.32 + 12).toFixed(1) }, bd);
      t.textContent = n.label;
      n.el = g; n.body = bd; n.tagEl = t;
    });

    this.wire();
    this.built = true;
    if (reduced) { this.run(400); this.render(); this.fit(false); }
  };

  // ---- simulation ------------------------------------------------------------------
  Graph.prototype.tick = function () {
    var a = this.alpha, nodes = this.nodes, links = this.links, n = nodes.length, i, j;
    var charge = this.dense ? -150 : -420, maxD2 = this.dense ? 420 * 420 : 900 * 900;
    // In 2D every z is 0, so each z term below adds exactly nothing.
    links.forEach(function (l) {
      var s1 = l.s, t1 = l.t;
      var dx = t1.x + t1.vx - s1.x - s1.vx || 1e-3, dy = t1.y + t1.vy - s1.y - s1.vy || 1e-3;
      var dz = t1.z + t1.vz - s1.z - s1.vz;
      var d = Math.sqrt(dx * dx + dy * dy + dz * dz);
      var k = (d - l.dist) / d * a * l.str;
      dx *= k; dy *= k; dz *= k;
      t1.vx -= dx * l.bias; t1.vy -= dy * l.bias; t1.vz -= dz * l.bias;
      s1.vx += dx * (1 - l.bias); s1.vy += dy * (1 - l.bias); s1.vz += dz * (1 - l.bias);
    });
    for (i = 0; i < n; i++) {
      var p = nodes[i];
      for (j = i + 1; j < n; j++) {
        var q = nodes[j], dx2 = q.x - p.x, dy2 = q.y - p.y, dz2 = q.z - p.z, d2 = dx2 * dx2 + dy2 * dy2 + dz2 * dz2;
        if (d2 > maxD2) continue;
        if (d2 < 1) { dx2 = (i % 7) - 3 || 1; dy2 = (j % 5) - 2 || 1; dz2 = 0; d2 = dx2 * dx2 + dy2 * dy2; }
        var w = charge * a / d2 * (1 + (p.r + q.r) / 30);
        p.vx += dx2 * w; p.vy += dy2 * w; p.vz += dz2 * w;
        q.vx -= dx2 * w; q.vy -= dy2 * w; q.vz -= dz2 * w;
      }
    }
    // Zones pull their members toward the zone centroid, which is what turns a hull from
    // a lasso around scattered points into a region.
    var zs = this.zones;
    if (zs.length) {
      var cx = {}, cy = {}, cz = {}, cn = {};
      nodes.forEach(function (o) {
        if (o.zone < 0) return;
        cx[o.zone] = (cx[o.zone] || 0) + o.x; cy[o.zone] = (cy[o.zone] || 0) + o.y;
        cz[o.zone] = (cz[o.zone] || 0) + o.z; cn[o.zone] = (cn[o.zone] || 0) + 1;
      });
      nodes.forEach(function (o) {
        if (o.zone < 0) return;
        var zx = cx[o.zone] / cn[o.zone], zy = cy[o.zone] / cn[o.zone], zz = cz[o.zone] / cn[o.zone];
        o.vx += (zx - o.x) * 0.22 * a; o.vy += (zy - o.y) * 0.22 * a; o.vz += (zz - o.z) * 0.22 * a;
      });
      // Zones keep apart as wholes. Without this two linked zones interpenetrate, the
      // hulls overlap, and a hand-over across a zone line, the thing zones exist to show,
      // becomes a line inside one blob.
      var keys = Object.keys(cn), push = {};
      for (i = 0; i < keys.length; i++) {
        for (j = i + 1; j < keys.length; j++) {
          var A = keys[i], B = keys[j];
          var ax = cx[A] / cn[A], ay = cy[A] / cn[A], bx = cx[B] / cn[B], by = cy[B] / cn[B];
          var want = (Math.sqrt(cn[A]) + Math.sqrt(cn[B])) * (this.dense ? 30 : 46) + 40;
          var zdz = cz[B] / cn[B] - cz[A] / cn[A];
          var zdx = bx - ax, zdy = by - ay, zd = Math.sqrt(zdx * zdx + zdy * zdy + zdz * zdz) || 1;
          if (zd < want) {
            var f = (want - zd) / zd * 0.12 * a;
            push[A] = push[A] || [0, 0, 0]; push[B] = push[B] || [0, 0, 0];
            push[A][0] -= zdx * f; push[A][1] -= zdy * f; push[A][2] -= zdz * f;
            push[B][0] += zdx * f; push[B][1] += zdy * f; push[B][2] += zdz * f;
          }
        }
      }
      nodes.forEach(function (o) {
        var pz = o.zone >= 0 && push[o.zone];
        if (pz) { o.vx += pz[0]; o.vy += pz[1]; o.vz += pz[2]; }
      });
    }
    // FAN-OUT. Two links leaving one node at almost the same angle print on top of each
    // other, and the lower one cannot be clicked anywhere along its length: measured on a
    // client atlas, 3 of 172 graph edges, the same edge-over-edge occlusion archify does
    // not check for in the drawing. So the far ends of a node's links are pushed apart
    // until each pair keeps a minimum angle.
    // Fan-out and collision measure where a node will SHOW at home, not where it sits:
    // perspective moves parts by several percent in 3D, enough to fold a 23° fan to 10°
    // on screen (measured). hs is the home view's scale; in 2D it is 1 and nothing moves.
    var F3 = this.amt > 0 && this.R ? this.R * 3.2 : 0, amt3 = this.amt;
    nodes.forEach(function (o) { o.hs = F3 ? 1 + amt3 * (F3 / (F3 + o.z) - 1) : 1; });
    var MIN = 0.42;
    nodes.forEach(function (hub) {
      var nb = hub.nb, lim = Math.min(MIN, 4.4 / Math.max(1, nb.length));   // a hub cannot give every pair 24°
      for (var x = 0; x < nb.length; x++) {
        for (var y = x + 1; y < nb.length; y++) {
          var P = nb[x], Q = nb[y];
          var ax = P.x * P.hs - hub.x * hub.hs, ay = P.y * P.hs - hub.y * hub.hs;
          var bx = Q.x * Q.hs - hub.x * hub.hs, by = Q.y * Q.hs - hub.y * hub.hs;
          var la = Math.sqrt(ax * ax + ay * ay) || 1, lb = Math.sqrt(bx * bx + by * by) || 1;
          var ang = Math.atan2(ax * by - ay * bx, ax * bx + ay * by);
          if (Math.abs(ang) >= lim) continue;
          var sg = ang < 0 ? -1 : 1, k = (lim - Math.abs(ang)) * 2.4 * a;
          if (P.fx == null) { P.vx += sg * (ay / la) * k * la * 0.4; P.vy -= sg * (ax / la) * k * la * 0.4; }
          if (Q.fx == null) { Q.vx -= sg * (by / lb) * k * lb * 0.4; Q.vy += sg * (bx / lb) * k * lb * 0.4; }
        }
      }
    });
    var g = this.dense ? 0.05 : 0.035;
    // Depth is held tighter than width: a thick slab facing the camera, not a ball, so the
    // straight-on view still fills a wide stage and a turn still shows the layers.
    nodes.forEach(function (o) { o.vx -= o.x * g * a; o.vy -= o.y * g * a; o.vz -= o.z * g * a * 2.2; });
    // Collision, with room for the label under each node: a graph whose labels overprint
    // each other is a graph nobody can read. It stays in the screen plane in 3D ON PURPOSE:
    // at home (straight on) no part hides another, so all are clickable before any turn.
    for (i = 0; i < n; i++) {
      var u = nodes[i];
      for (j = i + 1; j < n; j++) {
        var v = nodes[j], rr = (u.r + v.r + (this.dense ? 10 : 22)) * (u.hs + v.hs) / 2;
        // An ellipse, wider than tall: a label is a wide, short box under its node, so
        // two nodes side by side need more room than two stacked.
        var ex = (v.x + v.vx) * v.hs - (u.x + u.vx) * u.hs, ey = (v.y + v.vy) * v.hs - (u.y + u.vy) * u.hs;
        var sx = this.dense ? 0.72 : 0.5;
        var dd = ex * ex * sx * sx + ey * ey;
        if (dd < rr * rr) {
          var dl = Math.sqrt(dd) || 1e-3, push = (rr - dl) / dl * 0.6;
          ex *= push * 0.5; ey *= push * 0.5;
          v.vx += ex; v.vy += ey; u.vx -= ex; u.vy -= ey;
        }
      }
    }
    var flat = !this.d3;
    nodes.forEach(function (o) {
      if (o.fx != null) {
        o.x = o.fx; o.y = o.fy; if (o.fz != null) o.z = o.fz;
        o.vx = 0; o.vy = 0; o.vz = 0;
      } else {
        o.vx *= 0.58; o.vy *= 0.58; o.vz *= 0.58;
        o.x += o.vx; o.y += o.vy; o.z += o.vz;
      }
      // Leaving 3D, depth drains away over a few frames rather than snapping flat.
      if (flat && o.z) { o.vz = 0; o.z = Math.abs(o.z) < 0.05 ? 0 : o.z * 0.8; }
    });
    this.alpha += (this.alphaTarget - this.alpha) * 0.0228;
  };
  // Depth for a layout that has none yet: seeded, so 3D opens in the same shape too.
  Graph.prototype.inflate = function () {
    var rz = seeded((this.opts.seed || 'atlas') + ':depth'), ns = this.nodes, rms = 0;
    ns.forEach(function (n) { rms += n.x * n.x + n.y * n.y; });
    rms = Math.sqrt(rms / Math.max(1, ns.length)) || 60;
    ns.forEach(function (n) { n.z = (rz() - 0.5) * 1.6 * rms; n.vz = 0; });
  };
  Graph.prototype.run = function (n) { for (var i = 0; i < n && this.alpha > 0.002; i++) this.tick(); };

  // ---- drawing -----------------------------------------------------------------------
  // The camera's view of the layout. yaw turns about the vertical axis, pitch tilts; Z is
  // the depth after turning (larger is further), and s the perspective scale. With amt 0
  // and no turn this is the identity, so the 2D view is the 2D engine, exactly.
  Graph.prototype.project = function (snap) {
    var amt = this.amt, ns = this.nodes;
    if (amt === 0 && !this.yaw && !this.pitch) {
      var flat = true;
      for (var i = 0; i < ns.length; i++) if (ns[i].z) { flat = false; break; }
      if (flat) {
        ns.forEach(function (n) { n.px = n.x; n.py = n.y; n.s = 1; n.Z = 0; n.dep = 0.5; });
        return;
      }
    }
    var rms = 0;
    ns.forEach(function (n) { rms += n.x * n.x + n.y * n.y + n.z * n.z; });
    var Rt = Math.max(120, Math.sqrt(rms / Math.max(1, ns.length)) * 1.6);
    this.R = (snap || !this.R) ? Rt : this.R + (Rt - this.R) * 0.15;
    var R = this.R, F = R * 3.2;
    var cy = Math.cos(this.yaw), sy = Math.sin(this.yaw), cp = Math.cos(this.pitch), sp = Math.sin(this.pitch);
    ns.forEach(function (n) {
      var x1 = n.x * cy + n.z * sy, z1 = -n.x * sy + n.z * cy;
      var y1 = n.y * cp - z1 * sp, z2 = n.y * sp + z1 * cp;
      var s = 1 + amt * (F / (F + z2) - 1);
      n.px = x1 * s; n.py = y1 * s; n.s = s; n.Z = z2;
      n.dep = Math.max(0, Math.min(1, (z2 / R + 1) / 2));
    });
  };
  // SVG has no z-index: the last painted is on top and takes the click. So nodes stay in
  // DOM order far to near, making "the part in front is the part you click" true by
  // construction. Only out-of-place nodes move; a moved focused node gets focus back.
  Graph.prototype.sortDepth = function () {
    var list = this.nodes.slice().sort(function (p, q) { return q.Z - p.Z; });
    var nl = this.nl, ref = nl.firstChild, act = document.activeElement, moved = false;
    list.forEach(function (n) {
      if (n.el === ref) ref = ref.nextSibling;
      else { nl.insertBefore(n.el, ref); moved = true; }
    });
    if (moved && act && act !== document.activeElement && act.closest && act.closest('.gnode')) {
      try { act.focus({ preventScroll: true }); } catch (e) {}
    }
  };
  // Labels in 3D: repulsion spends itself partly along depth, so labels overprint. A label
  // landing on one already placed is hushed, hubs and near first; hover, selection or a
  // highlight always brings it back (CSS).
  Graph.prototype.cull = function () {
    var on = this.amt > 0.5 && !this.svg.classList.contains('alllabels'), ns = this.nodes;
    if (!on) {
      if (this.culled) { ns.forEach(function (n) { if (n.hush) { n.hush = false; n.el.classList.remove('hush'); } }); this.culled = false; }
      return;
    }
    this.culled = true;
    var cls = this.svg.classList, z1 = cls.contains('z1'), z2 = cls.contains('z2');
    var want = ns.filter(function (n) { return z2 || n.tier === 'hub' || (n.tier === 'mid' && z1); });
    var rank = { hub: 0, mid: 1, leaf: 2 };
    want.sort(function (p, q) { return (rank[p.tier] - rank[q.tier]) || (p.Z - q.Z); });
    var boxes = [], keep = {};
    want.forEach(function (n) {
      if (n.lw == null) { try { n.lw = n.tagEl.getComputedTextLength(); } catch (e) {} if (!n.lw) n.lw = n.label.length * 6; }
      var hw = n.lw / 2 * n.s + 2, cy = n.py + (n.r * 1.32 + 8) * n.s, hh = 7 * n.s;
      var b = [n.px - hw, cy - hh, n.px + hw, cy + hh];
      for (var i = 0; i < boxes.length; i++) {
        var o = boxes[i];
        if (b[0] < o[2] && b[2] > o[0] && b[1] < o[3] && b[3] > o[1]) return;
      }
      boxes.push(b);
      keep[n.id] = 1;
    });
    ns.forEach(function (n) {
      var h = !keep[n.id] || (this.dense && n.dep > 0.62);
      if (h !== !!n.hush) { n.hush = h; n.el.classList.toggle('hush', h); }
    }, this);
  };
  Graph.prototype.render = function () {
    this.project();
    var amt = this.amt, dense = this.dense;
    this.nodes.forEach(function (n) {
      n.el.setAttribute('transform', 'translate(' + n.px.toFixed(1) + ',' + n.py.toFixed(1) + ')' +
        (n.s !== 1 ? ' scale(' + n.s.toFixed(3) + ')' : ''));
      // Depth fog: the far side fades toward the ground, which is most of what makes a
      // projection read as depth rather than as a flat graph that shrank in places.
      var fog = amt ? 1 - amt * 0.62 * n.dep : 1, fs = fog.toFixed(2);
      if (n.fog !== fs) { n.fog = fs; n.body.style.opacity = fog < 1 ? fs : ''; }
    });
    this.cull();
    this.links.forEach(function (l) {
      var a = l.s, b = l.t, dx = b.px - a.px, dy = b.py - a.py, d = Math.sqrt(dx * dx + dy * dy) || 1;
      var nx = -dy / d, ny = dx / d, ls = (a.s + b.s) / 2;
      l.plen = d;
      var mx = (a.px + b.px) / 2 + nx * l.bend * ls, my = (a.py + b.py) / 2 + ny * l.bend * ls;
      // Trim both ends to the node's edge, along the curve's own tangent, so the arrow
      // touches the shape instead of disappearing under it.
      var t0x = mx - a.px, t0y = my - a.py, t0 = Math.sqrt(t0x * t0x + t0y * t0y) || 1;
      var t1x = b.px - mx, t1y = b.py - my, t1 = Math.sqrt(t1x * t1x + t1y * t1y) || 1;
      var sx = a.px + t0x / t0 * (a.r + 2) * a.s, sy = a.py + t0y / t0 * (a.r + 2) * a.s;
      var ex = b.px - t1x / t1 * (b.r + 4) * b.s, ey = b.py - t1y / t1 * (b.r + 4) * b.s;
      var path = l.bend ? 'M' + sx.toFixed(1) + ',' + sy.toFixed(1) + 'Q' + mx.toFixed(1) + ',' + my.toFixed(1) + ' ' + ex.toFixed(1) + ',' + ey.toFixed(1)
        : 'M' + sx.toFixed(1) + ',' + sy.toFixed(1) + 'L' + ex.toFixed(1) + ',' + ey.toFixed(1);
      l.hit.setAttribute('d', path); l.line.setAttribute('d', path); l.flow.setAttribute('d', path);
      var lf = amt ? 1 - amt * 0.62 * (a.dep + b.dep) / 2 : 1, lfs = lf.toFixed(2);
      if (l.fog !== lfs) { l.fog = lfs; l.line.style.opacity = l.head.style.opacity = lf < 1 ? lfs : ''; }
      var ux = t1x / t1, uy = t1y / t1, hs = 5.5 * ls;
      l.head.setAttribute('d', 'M' + ex.toFixed(1) + ',' + ey.toFixed(1) +
        'L' + (ex - ux * hs * 1.6 + uy * hs * 0.8).toFixed(1) + ',' + (ey - uy * hs * 1.6 - ux * hs * 0.8).toFixed(1) +
        'L' + (ex - ux * hs * 1.6 - uy * hs * 0.8).toFixed(1) + ',' + (ey - uy * hs * 1.6 + ux * hs * 0.8).toFixed(1) + 'Z');
      if (l.tag) {
        // Toward the less connected end: a hub's labels would otherwise all print in the
        // same ring around it, which is exactly where a reader is looking.
        var f = a.deg > b.deg ? 0.64 : a.deg < b.deg ? 0.36 : 0.5, g1 = 1 - f;
        var lx = l.bend ? g1 * g1 * sx + 2 * g1 * f * mx + f * f * ex : sx + (ex - sx) * f;
        var ly = l.bend ? g1 * g1 * sy + 2 * g1 * f * my + f * f * ey : sy + (ey - sy) * f;
        l.tag.setAttribute('x', lx.toFixed(1)); l.tag.setAttribute('y', (ly - 4).toFixed(1));
      }
    });
    var byId = this.byId;
    this.zones.forEach(function (z) {
      var pts = [];
      z.members.forEach(function (id) {
        var n = byId[id], pad = (n.r + 22) * n.s;
        for (var i = 0; i < 10; i++) {
          var a = Math.PI * 2 * i / 10;
          // The lower half reaches further, because the label hangs under the node.
          pts.push([n.px + Math.cos(a) * pad, n.py + Math.sin(a) * pad + (Math.sin(a) > 0 ? 12 * n.s : 0)]);
        }
      });
      var h = hull(pts);
      z.el.setAttribute('d', smooth(h));
      var top = h[0];
      h.forEach(function (p) { if (p[1] < top[1]) top = p; });
      var cx = 0;
      h.forEach(function (p) { cx += p[0]; });
      cx /= h.length || 1;
      z.tag.setAttribute('x', (top[0] * 0.35 + cx * 0.65).toFixed(1));
      z.tag.setAttribute('y', (top[1] - 7).toFixed(1));
    });
    if (amt > 0) { this.sortDepth(); this.sortLinks(); }
  };
  // Links in 3D paint longest first: one running toward the camera foreshortens (21px for
  // 78 units, measured) and a longer neighbour's hit stroke covered all of it. Short on top
  // keeps it clickable; a long link has plenty of its own length elsewhere.
  Graph.prototype.sortLinks = function () {
    var list = this.links.slice().sort(function (p, q) { return q.plen - p.plen; });
    var ll = this.links.length && this.links[0].el.parentNode, ref = ll && ll.firstChild;
    if (!ll) return;
    list.forEach(function (l) {
      if (l.el === ref) ref = ref.nextSibling;
      else ll.insertBefore(l.el, ref);
    });
  };

  Graph.prototype.bounds = function () {
    var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    this.nodes.forEach(function (n) {
      var lw = Math.min(90, n.label.length * 3.4) * n.s, r = n.r * n.s;
      x0 = Math.min(x0, n.px - r - lw); x1 = Math.max(x1, n.px + r + lw);
      y0 = Math.min(y0, n.py - r - 30 * n.s); y1 = Math.max(y1, n.py + r * 1.4 + 22 * n.s);
    });
    if (!isFinite(x0)) return { x: -100, y: -100, w: 200, h: 200 };
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  };

  // ---- camera ----------------------------------------------------------------------
  Graph.prototype.size = function () {
    var r = this.svg.getBoundingClientRect();
    return { w: r.width || 800, h: r.height || 600, left: r.left, top: r.top };
  };
  Graph.prototype.apply = function () {
    this.world.setAttribute('transform', 'translate(' + this.tx.toFixed(2) + ',' + this.ty.toFixed(2) + ') scale(' + this.k.toFixed(4) + ')');
    var cls = this.svg.classList;
    var rel = this.k / (this.homeK || 1), was = cls.contains('z1') + 2 * cls.contains('z2');
    cls.toggle('z1', rel >= 1.25 || this.k >= 0.95);
    cls.toggle('z2', rel >= 2 || this.k >= 1.5);
    // Zooming in brings more labels in, so the 3D label pass has new candidates.
    if (this.amt > 0.5 && was !== cls.contains('z1') + 2 * cls.contains('z2')) this.cull();
    // The ground moves with the drawing. A dot grid that stays put while the nodes slide
    // over it makes the pan feel like the page is slipping.
    var step = 26 * this.k;
    while (step < 12) step *= 2;
    this.host.style.backgroundSize = step.toFixed(2) + 'px ' + step.toFixed(2) + 'px';
    this.host.style.backgroundPosition = this.tx.toFixed(1) + 'px ' + this.ty.toFixed(1) + 'px';
    if (this.opts.onLevel) this.opts.onLevel(Math.round(rel * 100) + '%');
  };
  // Fit into what is left once the floating legend and zoom cluster have taken their
  // corners: a node fitted underneath the legend is a node nobody can click (measured on a
  // 276-part atlas: 2 of them).
  Graph.prototype.target = function () {
    var b = this.bounds(), v = this.size();
    var ins = (this.opts.inset && this.opts.inset()) || { l: 0, t: 0, r: 0, b: 0 };
    var w = Math.max(120, v.w - ins.l - ins.r), h = Math.max(120, v.h - ins.t - ins.b);
    var k = Math.min(w / b.w, h / b.h) * 0.94;
    k = Math.max(0.12, Math.min(this.dense ? 1.3 : 1.6, k));
    return { k: k, tx: ins.l + w / 2 - (b.x + b.w / 2) * k, ty: ins.t + h / 2 - (b.y + b.h / 2) * k };
  };
  // Fit returns exactly home, and in 3D home includes the turn: the box is measured as
  // it will be once the camera has swung back to straight on.
  Graph.prototype.fit = function (animate, auto) {
    var t, y0 = this.yaw, p0 = this.pitch;
    if (y0 || p0) {
      this.yaw = 0; this.pitch = 0; this.project(); t = this.target();
      this.yaw = Math.atan2(Math.sin(y0), Math.cos(y0)); this.pitch = p0; this.project();
    } else t = this.target();
    this.homeK = t.k;
    this.follow = true;
    this.stopSpin(!auto);
    if (!animate || reduced) {
      this.yaw = 0; this.pitch = 0; this.rotTo = null;
      if (y0 || p0) this.render();
      this.k = t.k; this.tx = t.tx; this.ty = t.ty; this.apply(); return;
    }
    if (y0 || p0) { this.rotTo = { yaw: 0, pitch: 0 }; this.loop(); }
    this.tween(t);
  };
  // Turn the camera: by a step (keys), or straight to an angle (the check's seam).
  Graph.prototype.turn = function (dyaw, dpitch) {
    var b = this.rotTo || { yaw: this.yaw, pitch: this.pitch };
    this.stopSpin();
    this.follow = false;
    this.rotTo = { yaw: b.yaw + dyaw, pitch: Math.max(-1.35, Math.min(1.35, b.pitch + dpitch)) };
    if (reduced) { this.yaw = this.rotTo.yaw; this.pitch = this.rotTo.pitch; this.rotTo = null; this.render(); return; }
    this.loop();
  };
  Graph.prototype.turnTo = function (yaw, pitch) {
    this.stopSpin();
    this.follow = false;
    this.rotTo = null; this.yaw = yaw; this.pitch = pitch;
    this.render();
    // Framed at the new angle, so a turned view still has every part on the stage.
    var t = this.target();
    cancelAnimationFrame(this.tw);
    this.k = t.k; this.tx = t.tx; this.ty = t.ty; this.apply();
  };
  Graph.prototype.stopSpin = function (forGood) {
    this.spinning = false;
    clearTimeout(this.spinT);
    if (forGood !== false) this.spinOK = false;
  };
  // The whole-atlas graph turns slowly by itself until the reader reaches for it: the
  // pointer arriving pauses it, any press, wheel or key ends it for the visit.
  Graph.prototype.queueSpin = function (delay) {
    var self = this;
    clearTimeout(this.spinT);
    if (!this.spinOK || !this.d3 || reduced) return;
    this.spinT = setTimeout(function () {
      if (!self.visible || !self.spinOK || self.paused || !self.d3 || self.amt < 1) return;
      if (self.alpha > 0.002 || self.rotTo) { self.queueSpin(500); return; }
      self.spinning = true; self.follow = false; self.loop();
    }, delay == null ? 900 : delay);
  };
  // The switch. Into 3D the layout gains depth and relaxes into it; out of it the depth
  // drains away while the camera swings back to straight on.
  Graph.prototype.set3d = function (on, animate) {
    on = !!on;
    if (on === this.d3) return;
    this.d3 = on;
    if (!this.built) { this.amt = on ? 1 : 0; return; }
    this.svg.classList.toggle('g3d', on);
    this.stopSpin(false);
    if (on) this.inflate();
    this.yaw = Math.atan2(Math.sin(this.yaw), Math.cos(this.yaw));
    this.rotTo = on ? null : { yaw: 0, pitch: 0 };
    this.alpha = Math.max(this.alpha, on ? 0.55 : 0.45);
    this.follow = true;
    if (!animate || reduced || !this.visible) {
      this.amt = on ? 1 : 0; this.yaw = 0; this.pitch = 0; this.rotTo = null;
      this.run(600); this.alpha = 0;
      if (!on) this.nodes.forEach(function (n) { n.z = 0; n.vz = 0; });
      this.render(); this.fit(false);
      return;
    }
    this.loop();
  };
  Graph.prototype.tween = function (t) {
    var self = this, k0 = this.k, x0 = this.tx, y0 = this.ty, t0 = performance.now(), dur = 420;
    cancelAnimationFrame(this.tw);
    function f(now) {
      var p = Math.min(1, (now - t0) / dur), e = 1 - Math.pow(1 - p, 3);
      self.k = k0 + (t.k - k0) * e; self.tx = x0 + (t.tx - x0) * e; self.ty = y0 + (t.ty - y0) * e;
      self.apply();
      if (p < 1) self.tw = requestAnimationFrame(f);
    }
    this.tw = requestAnimationFrame(f);
  };
  Graph.prototype.zoomAt = function (factor, cx, cy) {
    var v = this.size();
    var px = cx - v.left, py = cy - v.top;
    var k = Math.max(this.homeK * 0.3, Math.min(this.homeK * 8, this.k * factor));
    var f = k / this.k;
    this.tx = px - (px - this.tx) * f; this.ty = py - (py - this.ty) * f; this.k = k;
    this.follow = false;
    this.apply();
  };
  Graph.prototype.zoom = function (factor) {
    var v = this.size();
    this.zoomAt(factor, v.left + v.w / 2, v.top + v.h / 2);
  };
  Graph.prototype.center = function (id, closer) {
    var n = this.byId[id];
    if (!n) return;
    var v = this.size(), k = closer ? Math.max(this.k, this.homeK * 1.5) : this.k;
    this.follow = false;
    var t = { k: k, tx: v.w / 2 - n.px * k, ty: v.h / 2 - n.py * k };
    if (reduced) { this.k = t.k; this.tx = t.tx; this.ty = t.ty; this.apply(); } else this.tween(t);
  };
  Graph.prototype.toScreen = function (x, y) {
    var v = this.size();
    return { x: v.left + this.tx + x * this.k, y: v.top + this.ty + y * this.k };
  };

  // ---- the loop ----------------------------------------------------------------------
  Graph.prototype.loop = function () {
    var self = this;
    if (this.raf) return;
    function frame() {
      self.raf = 0;
      if (!self.visible) return;
      var phys = self.alpha > 0.002 || self.alphaTarget > 0, busy = phys;
      if (phys) {
        self.tick();
        if (self.alpha > 0.3) self.tick();     // two ticks a frame early on: a quicker bloom
      }
      var to = self.d3 ? 1 : 0;
      if (self.amt !== to) {
        self.amt += (to - self.amt) * 0.1;
        if (Math.abs(to - self.amt) < 0.004) self.amt = to;
        busy = true;
      }
      if (self.rotTo) {
        self.yaw += (self.rotTo.yaw - self.yaw) * 0.16;
        self.pitch += (self.rotTo.pitch - self.pitch) * 0.16;
        if (Math.abs(self.rotTo.yaw - self.yaw) + Math.abs(self.rotTo.pitch - self.pitch) < 0.002) {
          self.yaw = self.rotTo.yaw; self.pitch = self.rotTo.pitch; self.rotTo = null;
        }
        busy = true;
      }
      if (self.spinning) { self.yaw += 0.0024; busy = true; }
      if (busy) {
        self.render();
        if (self.follow) {
          // Ease the camera toward the fitted box as the layout grows, rather than
          // snapping: the reader watches it open instead of watching it jump.
          var t = self.target();
          self.homeK = t.k;
          self.k += (t.k - self.k) * 0.12; self.tx += (t.tx - self.tx) * 0.12; self.ty += (t.ty - self.ty) * 0.12;
          self.apply();
        }
        self.raf = requestAnimationFrame(frame);
      } else {
        if (self.follow) self.fit(true, true);
        self.queueSpin();
      }
    }
    this.raf = requestAnimationFrame(frame);
  };
  Graph.prototype.show = function () {
    this.visible = true;
    if (!this.built) {
      this.build();
      if (!reduced) {
        // Start small at the centre so the first frame is the beginning of the bloom.
        var v = this.size();
        this.k = 0.35; this.tx = v.w / 2; this.ty = v.h / 2; this.apply();
      }
    }
    if (reduced) { this.render(); this.fit(false); return; }
    this.loop();
  };
  Graph.prototype.hide = function () { this.visible = false; this.stopSpin(false); };
  Graph.prototype.reheat = function () { this.alpha = Math.max(this.alpha, 0.7); this.follow = true; this.loop(); };
  // A test seam, and the reduced-motion path: run the layout to rest and fit, now.
  Graph.prototype.settle = function () {
    if (!this.built) this.build();
    this.alpha = Math.max(this.alpha, 0.002);
    this.alphaTarget = 0;
    this.run(600);
    this.alpha = 0;
    // At rest means at home: no spin, no turn, no half-finished switch between 2D and 3D.
    this.stopSpin();
    this.amt = this.d3 ? 1 : 0; this.yaw = 0; this.pitch = 0; this.rotTo = null; this.R = 0;
    if (!this.d3) this.nodes.forEach(function (n) { n.z = 0; n.vz = 0; });
    this.render();
    var t = this.target();
    cancelAnimationFrame(this.tw);
    this.follow = false;
    this.homeK = t.k; this.k = t.k; this.tx = t.tx; this.ty = t.ty;
    this.apply();
  };

  // ---- state shown on the graph -----------------------------------------------------
  // Same contract as the drawing's highlight: dim, never hide, so two selections are
  // always two highlights on one graph.
  Graph.prototype.light = function (ids, edgeIds) {
    if (!this.built) { this.pending = [ids, edgeIds]; return; }
    ids = ids || []; edgeIds = edgeIds || [];
    var on = {}, eon = {};
    ids.forEach(function (i) { on[i] = 1; });
    edgeIds.forEach(function (i) { eon[i] = 1; });
    this.nodes.forEach(function (n) { n.el.classList.toggle('lit', !!on[n.id]); });
    this.links.forEach(function (l) { l.el.classList.toggle('lit', !!eon[l.id]); if (l.tag) l.tag.classList.toggle('lit', !!eon[l.id]); });
    if (ids.length || edgeIds.length) this.svg.setAttribute('data-focus', '1');
    else this.svg.removeAttribute('data-focus');
  };
  Graph.prototype.select = function (id) {
    if (!this.built) { this.pendingSel = id; return; }
    var self = this;
    this.selId = id;
    this.nodes.forEach(function (n) { n.el.classList.toggle('sel', n.id === id); });
    if (id && this.byId[id]) {
      // Pan only if the picked node is off-screen or near an edge: moving the camera
      // under a reader's cursor on every click is disorienting.
      this.stopSpin();
      var p = this.toScreen(this.byId[id].px, this.byId[id].py), v = this.size(), m = 60;
      if (p.x < v.left + m || p.x > v.left + v.w - m || p.y < v.top + m || p.y > v.top + v.h - m) self.center(id);
    }
  };
  Graph.prototype.hover = function (id) {
    if (this.hoverId === id) return;
    this.hoverId = id;
    var svg = this.svg;
    if (!id) {
      svg.classList.remove('hovering');
      this.nodes.forEach(function (n) { n.el.classList.remove('near'); });
      this.links.forEach(function (l) { l.el.classList.remove('near', 'out', 'in'); if (l.tag) l.tag.classList.remove('near'); });
      return;
    }
    var near = {};
    near[id] = 1;
    this.links.forEach(function (l) {
      var hit = l.s.id === id || l.t.id === id;
      l.el.classList.toggle('near', hit);
      l.el.classList.toggle('out', hit && l.s.id === id);
      l.el.classList.toggle('in', hit && l.t.id === id);
      if (l.tag) l.tag.classList.toggle('near', hit);
      if (hit) { near[l.s.id] = 1; near[l.t.id] = 1; }
    });
    this.nodes.forEach(function (n) { n.el.classList.toggle('near', !!near[n.id]); });
    var c = this.byId[id] && this.byId[id].el.style.getPropertyValue('--c');
    if (c) svg.style.setProperty('--hc', c);
    svg.classList.add('hovering');
  };
  // Hover a whole group from the legend: the same dimming, aimed at a type.
  Graph.prototype.hoverType = function (type) {
    var svg = this.svg;
    if (!type) { this.hover(null); return; }
    this.hoverId = '\u0000' + type;
    this.nodes.forEach(function (n) { n.el.classList.toggle('near', (n.type || 'other') === type || (!SHAPE[n.type] && type === 'other')); });
    this.links.forEach(function (l) { l.el.classList.remove('near', 'out', 'in'); });
    svg.style.setProperty('--hc', 'var(--gt-' + type + ')');
    svg.classList.add('hovering');
  };
  Graph.prototype.labels = function (all) { this.svg.classList.toggle('alllabels', !!all); if (this.built) this.cull(); };

  // ---- input -------------------------------------------------------------------------
  Graph.prototype.wire = function () {
    var self = this, svg = this.svg, o = this.opts;
    var pts = new Map(), pinch = null, from = null, moved = false, drag = null;

    function nodeOf(t) { var g = t instanceof Element && t.closest('.gnode'); return g ? g.getAttribute('data-gnode') : null; }
    function linkOf(t) { var g = t instanceof Element && t.closest('.glink'); return g ? g.getAttribute('data-glink') : null; }

    svg.addEventListener('wheel', function (e) {
      e.preventDefault();
      self.stopSpin();
      self.zoomAt(e.deltaY < 0 ? 1.12 : 1 / 1.12, e.clientX, e.clientY);
    }, { passive: false });

    svg.addEventListener('pointerdown', function (e) {
      if (e.pointerType !== 'mouse') pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pts.size === 2) {
        from = null; drag = null;
        var it = pts.values(), a = it.next().value, b = it.next().value;
        pinch = { d: Math.hypot(a.x - b.x, a.y - b.y) };
        return;
      }
      if (e.button !== 0) return;
      self.stopSpin();
      var id = nodeOf(e.target);
      moved = false;
      // NO capture on pointerdown, for the reason atlas.js gives: capture redirects the
      // click away from the node, and every node goes dead while looking fine.
      from = { x: e.clientX, y: e.clientY, tx: self.tx, ty: self.ty, id: e.pointerId,
               yaw: self.yaw, pitch: self.pitch, pan: e.shiftKey };
      drag = id ? self.byId[id] : null;
      if (drag) drag.Z0 = drag.Z;
    });
    svg.addEventListener('pointermove', function (e) {
      if (pts.has(e.pointerId)) pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pinch && pts.size === 2) {
        var it = pts.values(), a = it.next().value, b = it.next().value, d = Math.hypot(a.x - b.x, a.y - b.y);
        if (d > 0) { self.zoomAt(d / pinch.d, (a.x + b.x) / 2, (a.y + b.y) / 2); pinch.d = d; }
        return;
      }
      if (!from) return;
      var dx = e.clientX - from.x, dy = e.clientY - from.y;
      if (!moved && Math.abs(dx) + Math.abs(dy) < 4) return;
      if (!moved) {
        try { svg.setPointerCapture(from.id); } catch (err) {}
        svg.classList.add(drag ? 'dragging' : 'grabbing');
        self.follow = false;
      }
      moved = true;
      if (drag) {
        var v = self.size();
        var PX = (e.clientX - v.left - self.tx) / self.k, PY = (e.clientY - v.top - self.ty) / self.k;
        if (self.amt || self.yaw || self.pitch) {
          // Undo the projection at the depth the node had when it was picked up, so it
          // stays under the pointer instead of sliding off along the view ray.
          var F = self.R * 3.2, Z0 = drag.Z0, sc = 1 + self.amt * (F / (F + Z0) - 1);
          var X = PX / sc, Y = PY / sc;
          var cy = Math.cos(self.yaw), sy = Math.sin(self.yaw), cp = Math.cos(self.pitch), sp = Math.sin(self.pitch);
          var z1 = -Y * sp + Z0 * cp;
          drag.fy = Y * cp + Z0 * sp;
          drag.fx = X * cy - z1 * sy;
          drag.fz = X * sy + z1 * cy;
        } else { drag.fx = PX; drag.fy = PY; }
        self.alphaTarget = 0.28;
        if (self.alpha < 0.28) self.alpha = 0.28;
        self.loop();
      } else if (self.d3 && !from.pan) {
        // In 3D a drag on the ground turns the graph; shift-drag pans, as in a 3D viewer.
        self.rotTo = null;
        self.yaw = from.yaw + dx * 0.0065;
        self.pitch = Math.max(-1.35, Math.min(1.35, from.pitch + dy * 0.0065));
        self.render();
      } else {
        self.tx = from.tx + dx; self.ty = from.ty + dy;
        self.apply();
      }
    });
    function release(e) {
      pts.delete(e.pointerId);
      if (pts.size < 2) pinch = null;
      if (!from) return;
      try { svg.releasePointerCapture(e.pointerId); } catch (err) {}
      if (drag) { drag.fx = null; drag.fy = null; drag.fz = null; self.alphaTarget = 0; }
      from = null; drag = null;
      svg.classList.remove('grabbing', 'dragging');
    }
    svg.addEventListener('pointerup', release);
    svg.addEventListener('pointercancel', release);
    svg.addEventListener('click', function (e) {
      if (moved) { e.stopPropagation(); moved = false; return; }
      var id = nodeOf(e.target);
      if (id) { if (o.onNode) o.onNode(id); return; }
      var lid = linkOf(e.target);
      if (lid) { if (o.onEdge) o.onEdge(lid); return; }
      if (o.onBackground) o.onBackground();
    });
    svg.addEventListener('dblclick', function (e) {
      var id = nodeOf(e.target);
      if (id && o.onOpen) { e.preventDefault(); o.onOpen(id); }
    });
    svg.addEventListener('pointerover', function (e) {
      if (e.pointerType && e.pointerType !== 'mouse') return;
      if (from && moved) return;
      var id = nodeOf(e.target);
      if (id) { self.hover(id); return; }
      var lid = linkOf(e.target);
      if (lid) {
        self.hover(null);
        self.links.forEach(function (l) { if (l.id === lid) { l.el.classList.add('near'); if (l.tag) l.tag.classList.add('near'); } });
        return;
      }
      self.hover(null);
    });
    svg.addEventListener('pointerleave', function () {
      if (!(from && moved)) self.hover(null);
      if (self.paused) { self.paused = false; self.queueSpin(1400); }
    });
    // A pointer arriving pauses the spin, so nothing slides out from under a reader who
    // is aiming at it.
    svg.addEventListener('pointerenter', function (e) {
      if (e.pointerType && e.pointerType !== 'mouse') return;
      if (self.spinning || self.spinOK) { self.paused = true; self.stopSpin(false); }
    });
    svg.addEventListener('keydown', function (e) {
      var id = nodeOf(e.target);
      self.stopSpin();
      if (!id) return;
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); if (o.onNode) o.onNode(id); }
    });
    svg.addEventListener('focusin', function (e) { self.stopSpin(); var id = nodeOf(e.target); if (id) self.hover(id); });
    svg.addEventListener('focusout', function () { self.hover(null); });
  };

  window.AtlasGraph = Graph;
  window.AtlasGraph.shapePath = shapePath;
  window.AtlasGraph.shapeOf = shapeOf;
})();
