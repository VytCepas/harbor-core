(function () {
  var D = window.__ATLAS__, order = D.order;
  var stage = document.querySelector('.stage');
  var inspect = document.querySelector('.inspect');
  var head = document.querySelector('.ins-head');
  var body = document.querySelector('.ins-body');
  var title = head.querySelector('h2');
  var sub = head.querySelector('p');
  var current = order[0], selected = null;

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }
  // Does this cell read as a figure? One unbroken token, short enough to sit in a narrow
  // column: "1.36×", "€23,425.72", "yes", "DC-14771046". Anything carrying a space is a
  // sentence. Deliberately about SHAPE, not meaning — a test for "is this a number"
  // argues with currency, ids and units forever, while "does it fit on one line" is the
  // question the layout is actually asking.
  function figure(v) {
    var s = String(v == null ? '' : v).trim();
    return s.length > 0 && s.length <= 14 && !/\s/.test(s);
  }
  // A PANEL FIELD IS textContent, NEVER innerHTML — every helper below builds nodes. This
  // is not a style preference: a `<b>` written into a description renders as the four
  // characters `<b>` in the reader's face, which is how a paragraph of markup shipped on
  // 2026-09-03. build.py now refuses `<` in these fields; this is the other half of that.
  //
  // The reason the two helpers exist at all is that a finding stated as a sentence is a
  // claim, and a reader cannot check a claim. A table says which rows, and a link says
  // where to go and look — so both are structure the panel can render, not prose the
  // author has to remember to write well.
  function evidence(t) {
    var wrap = el('details');
    wrap.open = true;
    wrap.appendChild(el('summary', null, t.title || 'The numbers'));
    var box = el('div', 'in'), tb = el('table', 'ev');
    if (t.cols && t.cols.length) {
      var thead = el('thead'), htr = el('tr');
      t.cols.forEach(function (c) { htr.appendChild(el('th', null, c)); });
      thead.appendChild(htr); tb.appendChild(thead);
    }
    // `.num` right-aligns and sets white-space:nowrap, which is right for a column of
    // money and fatal for a column of prose: an unwrappable sentence widens the table
    // past the panel and the panel does not scroll, so the text is simply GONE. Column
    // POSITION was standing in for column TYPE — every cell after the first was a
    // figure — and the last column of an evidence table is usually the verdict.
    // A figure is one unbroken short token; anything with a space is prose and wraps.
    var tbody = el('tbody');
    (t.rows || []).forEach(function (r) {
      var tr = el('tr');
      // A row may flag itself — "total", "control" — so the eye finds the line that
      // carries the argument without the author bolding it into the text.
      if (r.mark) tr.className = 'mark-' + r.mark;
      (r.cells || r).forEach(function (c, i) {
        var td = el('td', i && figure(c) ? 'num' : null, c);
        tr.appendChild(td);
      });
      tbody.appendChild(tr);
    });
    tb.appendChild(tbody);
    box.appendChild(tb);
    if (t.note) box.appendChild(el('p', 'evnote', t.note));
    wrap.appendChild(box);
    return wrap;
  }

  function openers(list, label) {
    var d = el('details');
    d.open = true;
    d.appendChild(el('summary', null, label + ' · ' + list.length));
    var box = el('div', 'in'), ul = el('ul', 'opens');
    list.forEach(function (o) {
      var li = el('li');
      if (o.href) {
        var a = el('a', null, o.label);
        a.href = o.href;
        a.target = '_blank';
        a.rel = 'noopener noreferrer';
        li.appendChild(a);
      } else {
        // No URL is a legitimate state — "ask the warehouse MCP for X" has no link, and
        // inventing one would be worse than the plain instruction.
        li.appendChild(el('span', 'nolink', o.label));
      }
      if (o.note) li.appendChild(el('span', 'onote', o.note));
      ul.appendChild(li);
    });
    box.appendChild(ul);
    d.appendChild(box);
    return d;
  }

  function canvas(name) { return stage.querySelector('.plate[data-name="' + name + '"] .canvas'); }
  // NOT EVERY TAB IS A DRAWING. The brief is a plate with no canvas, so every function
  // below that measures, fits, zooms or pans has to be asked first — `order` still lists
  // only the diagrams, which is what keeps the wheel, drag and zoom wiring off it for
  // free; these guards cover the paths driven by the TAB rather than by the list.
  function isDiagram(name) { return !!(D.diagrams && D.diagrams[name]); }

  // ---- fit the box to the drawing ---------------------------------------------
  // archify sizes the viewBox from the authored layout, not from what ends up drawn, so
  // every diagram carries 15-21% empty box — measured. A viewBox scaled to fit a stage
  // scales that emptiness too, which is why a diagram looks zoomed out with margins it
  // never asked for. getBBox is the only honest source: text extents depend on the font
  // that actually loaded, so this runs after fonts settle and only on a VISIBLE plate —
  // getBBox inside display:none returns zeroes and would crop the drawing to nothing.
  var SKIP = /c-grid|c-mask/;
  function tighten(svg) {
    if (!svg || svg.dataset.fitted) return;
    var x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, seen = 0;
    svg.querySelectorAll(
      '[data-node-id],[data-edge-id],[data-legend],[data-composition-frame-id],' +
      '[data-graph-role],text'
    ).forEach(function (n) {
      if (SKIP.test(n.getAttribute('class') || '')) return;
      var b;
      try { b = n.getBBox(); } catch (e) { return; }
      if (!b || (!b.width && !b.height)) return;
      seen++;
      x0 = Math.min(x0, b.x); y0 = Math.min(y0, b.y);
      x1 = Math.max(x1, b.x + b.width); y1 = Math.max(y1, b.y + b.height);
    });
    if (seen < 3 || !isFinite(x0)) return;   // nothing measurable: keep archify's own box
    var pad = 10;
    svg.setAttribute('viewBox',
      (x0 - pad) + ' ' + (y0 - pad) + ' ' + (x1 - x0 + pad * 2) + ' ' + (y1 - y0 + pad * 2));
    svg.dataset.fitted = '1';
    svg.dataset.ratio = ((x1 - x0) / (y1 - y0)).toFixed(3);
  }

  // ---- highlight -------------------------------------------------------------
  // Dimming marks what stays lit; it never hides. A hidden edge changes what the picture
  // claims, and a reader comparing two selections would be shown two different graphs.
  function light(name, ids, edgeIds) {
    var c = canvas(name);
    c.querySelectorAll('.lit').forEach(function (n) { n.classList.remove('lit'); });
    ids = ids || []; edgeIds = edgeIds || [];
    if (!ids.length && !edgeIds.length) { c.removeAttribute('data-focus'); return; }
    c.setAttribute('data-focus', ids.concat(edgeIds).join(' '));
    ids.forEach(function (id) {
      var n = c.querySelector('[data-node-id="' + id + '"]');
      if (n) n.classList.add('lit');
    });
    c.querySelectorAll('[data-edge-id]').forEach(function (e) {
      // A NAMED EDGE WINS OVER AN INFERRED ONE. Inference from endpoints is right for a
      // selected box — everything it touches is relevant — and wrong for a finding, which
      // is a claim about SPECIFIC arrows: lighting every edge between its nodes would
      // implicate hops the finding does not. So once a caller names edges, nothing else
      // is inferred, and a finding that names none still gets the old behaviour.
      if (edgeIds.length) {
        if (edgeIds.indexOf(e.getAttribute('data-edge-id')) > -1) e.classList.add('lit');
        return;
      }
      var a = e.getAttribute('data-edge-from'), b = e.getAttribute('data-edge-to');
      if (ids.indexOf(a) > -1 && (ids.length > 1 ? ids.indexOf(b) > -1 : true)) e.classList.add('lit');
      else if (ids.indexOf(b) > -1 && (ids.length > 1 ? ids.indexOf(a) > -1 : true)) e.classList.add('lit');
    });
  }

  // ---- inspector at rest: the diagram's own orientation -----------------------
  function showDiagram(name) {
    var g = D.diagrams[name];
    selected = null;
    inspect.classList.remove('node');
    title.textContent = g.title;
    sub.textContent = Object.keys(g.nodes).length + ' parts · ' + g.edges + ' connections';
    body.textContent = '';

    // The way back up from an inside view, to the part it opens.
    if (g.parent) {
      var up = el('button', 'drill up', '↑ Inside of ' + g.parent[2] + ' · ' + g.parent[3]);
      up.type = 'button';
      up.addEventListener('click', function () { goTo(g.parent[0], g.parent[1]); });
      body.appendChild(up);
    }

    if (g.views.length) {
      body.appendChild(el('p', 'sec', 'How to read it'));
      var ul = el('ul', 'views');
      g.views.forEach(function (v) {
        var li = el('li');
        li.appendChild(el('b', null, v.label));
        if (v.note) li.appendChild(el('p', null, v.note));
        var who = el('div', 'who');
        v.focus.forEach(function (lab, i) {
          var b = el('button', null, lab);
          b.type = 'button';
          b.addEventListener('click', function () { showNode(name, v.ids[i]); });
          who.appendChild(b);
        });
        li.appendChild(who);
        ul.appendChild(li);
      });
      body.appendChild(ul);
    }
    // Open at rest. The panel is a column of its own with room to spare, and a reader who
    // has to click three times to see what the page knows will click none of them.
    g.cards.forEach(function (card) {
      var d = el('details');
      d.open = true;
      d.appendChild(el('summary', null, card.title));
      var wrap = el('div', 'in'), list = el('ul');
      card.items.forEach(function (t) { list.appendChild(el('li', null, t)); });
      wrap.appendChild(list);
      d.appendChild(wrap);
      body.appendChild(d);
    });
    light(name, null);
    if (typeof setHash === 'function') setHash(name);
  }

  // ---- the data layer ---------------------------------------------------------
  // WHY THIS IS ITS OWN BLOCK AND NOT MORE FACTS. `facts` answers "what is this thing";
  // this answers "which column is it", and a reader chasing a column is not reading
  // prose — they are scanning for a name. So it renders as a name/type/meaning table and
  // stays open by default, because unlike the connections it is NOT visible in the
  // drawing and the panel's job is what the picture cannot say.
  function fieldsBlock(rows, label) {
    if (!rows || !rows.length) return null;
    var d = el('details');
    d.open = true;
    d.appendChild(el('summary', null, label + ' · ' + rows.length));
    var box = el('div', 'in');
    var t = el('table', 'fields');
    rows.forEach(function (r) {
      var tr = el('tr');
      var nm = el('td', 'fname');
      nm.appendChild(el('code', null, r[0]));
      tr.appendChild(nm);
      tr.appendChild(el('td', 'ftype', r[1]));
      tr.appendChild(el('td', 'fnote', r[2]));
      t.appendChild(tr);
    });
    box.appendChild(t);
    d.appendChild(box);
    return d;
  }

  // Where a reader would have met this part, and what it showed them. Open by default
  // and above the column list, because on an audit "was anybody looking" is the question
  // asked immediately after "what is this" — and the state is a badge rather than prose
  // so a reader can run down the column instead of reading five sentences.
  function exposureBlock(rows) {
    if (!rows || !rows.length) return null;
    var d = el('details');
    d.open = true;
    d.appendChild(el('summary', null, 'What a reader saw · ' + rows.length));
    var box = el('div', 'in');
    var t = el('table', 'expo');
    rows.forEach(function (r) {
      var tr = el('tr');
      tr.appendChild(el('td', 'xsurf', r[0]));
      var st = el('td', 'xstate');
      st.appendChild(el('span', 'xbadge x-' + r[1], r[1]));
      tr.appendChild(st);
      tr.appendChild(el('td', 'xnote', r[2]));
      t.appendChild(tr);
    });
    box.appendChild(t);
    d.appendChild(box);
    return d;
  }

  // ---- inspector on selection: one part ---------------------------------------
  function showNode(name, id) {
    var g = D.diagrams[name], n = g.nodes[id];
    if (!n) return;
    selected = id;
    inspect.classList.add('node', 'open');
    title.textContent = n.label;
    sub.textContent = n.sub || n.type;
    body.textContent = '';
    body.scrollTop = 0;

    body.appendChild(el('span', 'kind', n.kind));
    body.appendChild(el('p', 'role', n.role));

    // An inside view: the deeper drawing of this part, one click down (SKILL.md § Inside views).
    if (n.inside) {
      var dn = el('button', 'drill', 'Open the inside view · ' + n.inside[1] + ' →');
      dn.type = 'button';
      dn.addEventListener('click', function () { goDiagram(n.inside[0]); });
      body.appendChild(dn);
    }

    var dl = el('dl', 'facts');
    n.facts.forEach(function (f) {
      dl.appendChild(el('dt', null, f[0]));
      dl.appendChild(el('dd', null, f[1]));
    });
    body.appendChild(dl);

    // Closed. The connections are the one thing already visible in the drawing — the
    // selection lights them — so repeating them open costs the panel's best space to
    // say what the picture cannot.
    var wires = el('details');
    wires.appendChild(el('summary', null, 'Carries · ' + n.carries.length + ' of ' + g.edges));
    var wbox = el('div', 'in');
    var ul = el('ul', 'wires');
    n.carries.forEach(function (w) {
      var li = el('li');
      li.appendChild(el('span', 'd ' + w[0], w[0] === 'out' ? '→' : '←'));
      var t = el('span');
      t.appendChild(el('span', 'peer', w[1]));
      t.appendChild(el('span', 'cargo', w[2] || '—'));
      // A relationship that declares columns says so here, so the reader knows there is
      // something to open rather than having to click every edge to find out.
      if (w[4]) t.appendChild(el('span', 'cols', w[4] + ' col' + (w[4] === 1 ? '' : 's')));
      li.appendChild(t);
      if (w[3]) {
        li.className = 'hot';
        li.addEventListener('click', function () { showWire(name, w[3]); });
      }
      ul.appendChild(li);
    });
    wbox.appendChild(ul);
    wires.appendChild(wbox);
    body.appendChild(wires);

    var xb = exposureBlock(n.exposure);
    if (xb) body.appendChild(xb);

    var nf = fieldsBlock(n.fields, 'Columns it holds');
    if (nf) body.appendChild(nf);

    var d = el('details');
    d.open = true;
    d.appendChild(el('summary', null, 'Why it is here'));
    var wrap = el('div', 'in');
    wrap.appendChild(document.createTextNode(n.why));
    d.appendChild(wrap);
    body.appendChild(d);

    // The same component seen in another diagram. This is the one thing an atlas can do
    // that four separate pictures cannot: say that the box you are looking at is the box
    // over there, and take you to it.
    if (n.also && n.also.length) {
      var a = el('details');
      a.open = true;
      a.appendChild(el('summary', null, 'Also appears in · ' + n.also.length));
      var abox = el('div', 'in'), jumps = el('div', 'who');
      n.also.forEach(function (w) {
        var b = el('button', null, D.diagrams[w[0]].tab);
        b.type = 'button';
        b.addEventListener('click', function () { goTo(w[0], w[1]); });
        jumps.appendChild(b);
      });
      abox.appendChild(jumps);
      a.appendChild(abox);
      body.appendChild(a);
    }

    // A BOX IS A PLACE, AND A PLACE HAS AN ADDRESS. Without this the topology tells a
    // reader that "the crosswalk sheet" exists and leaves them to find out which of the
    // three, in whose Drive, under which account — so the picture is only checkable by
    // whoever drew it. The note carries the access condition, because a link you cannot
    // open is a link that teaches you the diagram is decorative.
    if (n.links && n.links.length) body.appendChild(openers(n.links, 'Open it'));

    // A component is rarely one file. Where the description names the files it is built
    // from, they are listed here — linked when the config knows the repository, plain
    // text when it does not, because a dead link is worse than a path you can grep for.
    if (n.sources && n.sources.length) {
      var s = el('details');
      s.open = true;
      s.appendChild(el('summary', null, 'Where it lives · ' + n.sources.length));
      var box = el('div', 'in'), files = el('ul', 'files');
      n.sources.forEach(function (src) {
        var li = el('li');
        if (D.repo) {
          var a = el('a', null, src);
          a.href = D.repo.replace(/\/$/, '') + '/' + src;
          a.target = '_blank';
          a.rel = 'noopener noreferrer';
          li.appendChild(a);
        } else {
          li.appendChild(el('code', null, src));
        }
        files.appendChild(li);
      });
      box.appendChild(files);
      s.appendChild(box);
      body.appendChild(s);
    }

    light(name, [id]);
    if (typeof setHash === 'function') setHash(name + '/' + id);
  }

  // ---- inspector on selection: one relationship ---------------------------------
  // A line is as much a thing as a box, and the two facts a reader wants from it — what
  // moves along it, and what that traffic is classified as — are the ones the drawing
  // has no room to print beside every arrow.
  function showWire(name, id) {
    var g = D.diagrams[name];
    var w = null;
    g.wires.forEach(function (x) { if (x.id === id) w = x; });
    if (!w) return;
    selected = id;
    inspect.classList.add('node', 'open');
    title.textContent = w.label || (w.fromLabel + ' → ' + w.toLabel);
    sub.textContent = w.fromLabel + '  →  ' + w.toLabel;
    body.textContent = '';
    body.scrollTop = 0;

    body.appendChild(el('span', 'kind', 'Connection'));
    var dl = el('dl', 'facts');
    var rows = [['From', w.fromLabel], ['To', w.toLabel]];
    if (w.label) rows.push(['Carries', w.label]);
    if (w.note) rows.push(['Classified', w.note]);
    if (w.variant) rows.push(['Drawn as', w.variant]);
    rows.forEach(function (r) {
      dl.appendChild(el('dt', null, r[0]));
      dl.appendChild(el('dd', null, r[1]));
    });
    body.appendChild(dl);

    var ef = fieldsBlock(w.fields, 'Columns on this edge');
    if (ef) body.appendChild(ef);

    body.appendChild(el('p', 'sec', 'Either end'));
    var ends = el('div', 'who');
    [[w.from, w.fromLabel], [w.to, w.toLabel]].forEach(function (pair) {
      var b = el('button', null, pair[1]);
      b.type = 'button';
      b.addEventListener('click', function () { showNode(name, pair[0]); });
      ends.appendChild(b);
    });
    body.appendChild(ends);

    light(name, [w.from, w.to]);
  }

  // ---- going somewhere ----------------------------------------------------------
  // One entry point for "show me this component", whichever diagram it lives in. The tab
  // has to change first: a plate that is not visible has no layout, so selecting into it
  // would light a node nobody can see and leave the panel describing another diagram.
  function goDiagram(diagram) {
    var tab = tabs.filter(function (t) { return t.dataset.name === diagram; })[0];
    if (tab) select(tab);
  }
  function goTo(diagram, id) {
    var tab = tabs.filter(function (t) { return t.dataset.name === diagram; })[0];
    if (!tab) return;
    if (diagram !== current) select(tab);
    showNode(diagram, id);
  }

  // ---- wiring ------------------------------------------------------------------
  order.forEach(function (name) {
    var c = canvas(name);
    c.querySelectorAll('[data-node-id]').forEach(function (node) {
      var id = node.getAttribute('data-node-id');
      node.addEventListener('click', function (e) { e.stopPropagation(); showNode(name, id); });
      node.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); showNode(name, id); }
      });
    });
    c.querySelectorAll('[data-edge-id]').forEach(function (edge) {
      var id = edge.getAttribute('data-edge-id');
      edge.classList.add('hit');
      // A 1.5px stroke is not a hit target, and an L-shaped or curved edge does not even
      // pass through the centre of its own bounding box — measured: three of forty-eight
      // edges could not be hit at their midpoint. So each drawn segment gets a fat
      // transparent twin behind it, which is what every diagram editor does. It is
      // pointer-events only: no fill, no marker, nothing that could alter the picture.
      //
      // `data-edge-id` sits on two different shapes and both must be handled: on a
      // sequence diagram it is a <g> WRAPPING the line, on an architecture diagram it is
      // the <path> ITSELF. A descendant-only query silently found nothing for the second,
      // which is how every architecture edge stayed unclickable while the sequence ones
      // worked.
      var drawn = /^(path|line|polyline)$/i.test(edge.tagName)
        ? [edge]
        : [].slice.call(edge.querySelectorAll('path,line,polyline'));
      drawn.forEach(function (seg) {
        if (seg.dataset.hitTwin) return;
        var twin = seg.cloneNode(false);
        twin.dataset.hitTwin = '1';
        twin.removeAttribute('marker-end');
        twin.removeAttribute('marker-start');
        twin.removeAttribute('class');
        twin.setAttribute('fill', 'none');
        twin.setAttribute('stroke', 'transparent');
        twin.setAttribute('stroke-width', '14');
        twin.setAttribute('stroke-dasharray', 'none');
        twin.setAttribute('pointer-events', 'stroke');
        seg.parentNode.insertBefore(twin, seg);
      });
      edge.addEventListener('click', function (e) { e.stopPropagation(); showWire(name, id); });
    });
    // Clicking the ground clears the selection, which is the gesture people try first.
    c.addEventListener('click', function () { if (selected) showDiagram(name); });
  });

  var tabs = [].slice.call(document.querySelectorAll('[role=tab]'));

  // ---- the view menu ------------------------------------------------------------
  // The tabs live in a popup rather than a row, so the trigger has to say which view is
  // open — a closed menu that does not name its selection is worse than the row it
  // replaced. It mirrors the selected tab's own two lines rather than keeping a second
  // copy of the labels, so it cannot drift from them.
  var trig = document.querySelector('.tabtrig');
  var pop = document.querySelector('.tabpop');
  function menu(open) {
    if (!trig || !pop) return;
    pop.hidden = !open;
    trig.setAttribute('aria-expanded', open ? 'true' : 'false');
  }
  if (trig && pop) {
    trig.addEventListener('click', function (e) {
      e.stopPropagation();
      menu(pop.hidden);
      if (!pop.hidden) {
        var on = pop.querySelector('[role=tab][aria-selected=true]');
        if (on) on.focus();
      }
    });
    // Clicking away closes it. Without this the panel sits over the drawing and the
    // reader has to find the trigger again to get rid of it.
    document.addEventListener('click', function (e) {
      if (!pop.hidden && !pop.contains(e.target) && e.target !== trig) menu(false);
    });
    pop.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { e.stopPropagation(); menu(false); trig.focus(); }
    });
  }

  // Search and the findings picker are behind one button below 760px, where they were
  // costing two full rows of a four-row header. Class on <body> rather than a style on the
  // element, so the media query stays the single place that decides this is a phone —
  // toggling display here would leave the controls hidden on a desktop after a resize.
  var more = document.querySelector('.barmore');
  if (more) {
    more.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = !document.body.classList.contains('baropen');
      document.body.classList.toggle('baropen', open);
      more.setAttribute('aria-expanded', open ? 'true' : 'false');
      if (open) { var q = document.querySelector('.q'); if (q) q.focus(); }
    });
  }

  function select(tab) {
    tabs.forEach(function (t) {
      var on = t === tab;
      t.setAttribute('aria-selected', on ? 'true' : 'false');
      t.tabIndex = on ? 0 : -1;
      stage.querySelector('.plate[data-name="' + t.dataset.name + '"]').classList.toggle('on', on);
    });
    current = tab.dataset.name;
    if (trig) {
      var tb = tab.querySelector('b'), ti = tab.querySelector('i');
      trig.querySelector('b').textContent = tb ? tb.textContent : current;
      trig.querySelector('i').textContent = ti ? ti.textContent : '';
      menu(false);
    }
    if (isDiagram(current)) {
      // Only now is this plate visible, which is the only state getBBox can measure in.
      document.body.classList.remove('docview');
      tighten(canvas(current).querySelector('svg'));
      home(current);
      showDiagram(current);
    } else {
      // The brief carries its own orientation, so the panel steps out of the way rather
      // than showing the last diagram's summary beside prose that is not about it. It
      // then held nothing but the tab's own title while occupying the panel beside a column
      // of text that had nowhere to go — so on a document it leaves entirely, and the
      // prose gets the width back.
      selected = null;
      document.body.classList.add('docview');
      inspect.classList.remove('node', 'open');
      title.textContent = tab.querySelector('b') ? tab.querySelector('b').textContent : '';
      sub.textContent = tab.querySelector('i') ? tab.querySelector('i').textContent : '';
      body.textContent = '';
      if (typeof setHash === 'function') setHash(current);
    }
    try { localStorage.setItem('atlas-tab', current); } catch (e) {}
  }
  tabs.forEach(function (tab, i) {
    tab.addEventListener('click', function () { select(tab); });
    tab.addEventListener('keydown', function (e) {
      var next = null;
      if (e.key === 'ArrowRight') next = tabs[(i + 1) % tabs.length];
      if (e.key === 'ArrowLeft') next = tabs[(i - 1 + tabs.length) % tabs.length];
      if (e.key === 'Home') next = tabs[0];
      if (e.key === 'End') next = tabs[tabs.length - 1];
      if (next) { e.preventDefault(); select(next); next.focus(); }
    });
  });

  // ---- navigation ---------------------------------------------------------------
  // Fitting alone cannot help a near-square drawing in a landscape stage: the admission
  // sequence is 1.07 wide against a 1.59 stage, so a third of the stage is unreachable
  // whatever the box says. Every schema tool answers this the same way and so does this —
  // wheel to zoom at the pointer, drag to pan, and a fit button to get back. The viewBox
  // is the only thing that moves; no transform, so hit testing and text stay exact.
  var HOME = {};                       // name -> the fitted box, which Fit returns to
  var VIEW = {};                       // name -> the box on screen right now
  var MIN = 0.4, MAX = 8;              // scale bounds, relative to the fitted box
  var STEP = 1.1;                      // one press is 10%; a quarter was too coarse to aim

  function box(svg) {
    var v = svg.getAttribute('viewBox').split(/\s+/).map(Number);
    return { x: v[0], y: v[1], w: v[2], h: v[3] };
  }
  function put(name, b) {
    var svg = canvas(name).querySelector('svg');
    VIEW[name] = b;
    svg.setAttribute('viewBox', b.x + ' ' + b.y + ' ' + b.w + ' ' + b.h);
    level(name).textContent = Math.round((HOME[name].w / b.w) * 100) + '%';
  }
  function home(name) {
    var svg = canvas(name).querySelector('svg');
    if (!HOME[name]) HOME[name] = box(svg);
    put(name, { x: HOME[name].x, y: HOME[name].y, w: HOME[name].w, h: HOME[name].h });
  }

  // Zoom about a fixed point: the user-space coordinate under the pointer must land on
  // the same screen pixel afterwards, or the drawing slides away from the cursor.
  function zoomAt(name, factor, clientX, clientY) {
    var c = canvas(name), r = c.getBoundingClientRect(), b = VIEW[name], h = HOME[name];
    var next = b.w / factor;
    if (h.w / next < MIN) next = h.w / MIN;
    if (h.w / next > MAX) next = h.w / MAX;
    var f = next / b.w;
    // Where the pointer is, as a fraction of the rendered drawing — not of the canvas,
    // because a letterboxed drawing does not fill it.
    var scale = Math.min(r.width / b.w, r.height / b.h);
    var drawnW = b.w * scale, drawnH = b.h * scale;
    var offX = (r.width - drawnW) / 2, offY = (r.height - drawnH) / 2;
    var ux = b.x + (clientX - r.left - offX) / scale;
    var uy = b.y + (clientY - r.top - offY) / scale;
    put(name, { x: ux - (ux - b.x) * f, y: uy - (uy - b.y) * f, w: b.w * f, h: b.h * f });
  }
  function step(name, factor) {
    var r = canvas(name).getBoundingClientRect();
    zoomAt(name, factor, r.left + r.width / 2, r.top + r.height / 2);
  }

  // One control cluster per plate, sitting OVER the drawing but OUTSIDE the canvas
  // element — a button inside it would start a pan on pointerdown before it could be
  // clicked, and stopping propagation to fix that would be papering over the wrong layout.
  function plate(name) { return stage.querySelector('.plate[data-name="' + name + '"]'); }
  function level(name) { return plate(name).querySelector('.level'); }
  order.forEach(function (name) {
    var p = plate(name);
    p.querySelector('.zin').addEventListener('click', function () { step(name, STEP); });
    p.querySelector('.zout').addEventListener('click', function () { step(name, 1 / STEP); });
    p.querySelector('.zfit').addEventListener('click', function () { home(name); });
  });

  order.forEach(function (name) {
    var c = canvas(name);
    c.addEventListener('wheel', function (e) {
      e.preventDefault();
      zoomAt(name, e.deltaY < 0 ? 1.12 : 1 / 1.12, e.clientX, e.clientY);
    }, { passive: false });

    // TWO-FINGER ZOOM. `touch-action:none` above hands every touch to this script so a
    // one-finger drag pans instead of scrolling the page — which also means the browser's
    // own pinch is gone. Without a handler here a phone could pan a drawing it had no way
    // to magnify, and the only zoom left was two 28px buttons in a corner. Measured on a
    // 390px viewport: the whole diagram renders about 250px wide, which is legible to
    // nobody.
    var pts = new Map(), pinch = null;
    function span() {
      var it = pts.values(), a = it.next().value, b = it.next().value;
      return { d: Math.hypot(a.x - b.x, a.y - b.y),
               x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
    }

    var from = null, moved = false;
    c.addEventListener('pointerdown', function (e) {
      if (e.pointerType !== 'mouse') pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pts.size === 2) {
        // A second finger cancels the pan it started as, or the drawing lurches on the
        // frame the pinch begins.
        from = null;
        c.classList.remove('grabbing');
        var s = span();
        pinch = { d: s.d, b: VIEW[name] };
        return;
      }
      if (e.button !== 0) return;
      from = { x: e.clientX, y: e.clientY, b: VIEW[name], id: e.pointerId };
      moved = false;
      // NO pointer capture here. Capturing on pointerdown redirects the eventual `click`
      // to the capture target — measured: pointerdown lands on the SVG text, the click
      // lands on this DIV — so every node and edge in the drawing became unclickable
      // while looking perfectly fine. Capture is taken below, only once a drag is real,
      // where it is actually needed and where no click is coming.
    });
    c.addEventListener('pointermove', function (e) {
      if (pts.has(e.pointerId)) pts.set(e.pointerId, { x: e.clientX, y: e.clientY });
      if (pinch && pts.size === 2) {
        var s = span();
        if (s.d > 0) {
          // Zoom about the midpoint between the fingers, and re-base every frame so the
          // gesture stays anchored to where the fingers actually are rather than drifting
          // from a start point they have long left.
          VIEW[name] = pinch.b;
          zoomAt(name, s.d / pinch.d, s.x, s.y);
          pinch = { d: s.d, b: VIEW[name] };
        }
        return;
      }
      if (!from) return;
      var dx = e.clientX - from.x, dy = e.clientY - from.y;
      if (!moved && Math.abs(dx) + Math.abs(dy) < 4) return;   // still a click, not a drag
      if (!moved) {
        // Now it is a drag: take capture so it survives leaving the canvas, and set the
        // cursor. Throws if the pointer is already gone, which is not a reason to abandon
        // the pan.
        try { c.setPointerCapture(from.id); } catch (err) {}
        c.classList.add('grabbing');
      }
      moved = true;
      var r = c.getBoundingClientRect();
      var scale = Math.min(r.width / from.b.w, r.height / from.b.h);
      put(name, { x: from.b.x - dx / scale, y: from.b.y - dy / scale,
                  w: from.b.w, h: from.b.h });
    });
    function release(e) {
      pts.delete(e.pointerId);
      // Lifting one finger of a pinch must not resume a pan from a stale origin — the
      // drawing would jump by however far that finger had travelled.
      if (pts.size < 2) { pinch = null; if (pts.size === 1) { from = null; moved = true; } }
      if (!from) return;
      try { c.releasePointerCapture(e.pointerId); } catch (err) {}
      from = null;
      c.classList.remove('grabbing');
    }
    c.addEventListener('pointerup', release);
    c.addEventListener('pointercancel', release);
    // A drag that ends over a node must not also select it.
    c.addEventListener('click', function (e) {
      if (moved) { e.stopPropagation(); moved = false; }
    }, true);
  });

  document.addEventListener('keydown', function (e) {
    // `closest` lives on Element. A keydown can arrive with the Document as its target —
    // when nothing is focused, and whenever one is dispatched programmatically — so the
    // instance check is the guard, not a nicety.
    var t = e.target;
    if (t instanceof Element && t.closest('.inspect')) return;
    if (!isDiagram(current)) return;
    if (e.key === '+' || e.key === '=') { e.preventDefault(); step(current, STEP); }
    if (e.key === '-' || e.key === '_') { e.preventDefault(); step(current, 1 / STEP); }
    if (e.key === '0') { e.preventDefault(); home(current); }
  });

  head.querySelector('.x').addEventListener('click', function (e) {
    e.stopPropagation();
    if (isDiagram(current)) showDiagram(current);
  });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && selected && isDiagram(current)) showDiagram(current);
  });
  // On a narrow screen the panel is a sheet; its header is the handle.
  head.addEventListener('click', function () {
    if (window.matchMedia('(max-width:960px)').matches) inspect.classList.toggle('open');
  });

  // Collapsing the panel returns its width to the stage. It helps a WIDE drawing, where
  // width is the binding constraint; a tall one is bounded by height and gains
  // nothing, which is why this is a control and not a default.
  var panner = document.querySelector('.panner');
  panner.addEventListener('click', function () {
    var off = document.body.classList.toggle('nopanel');
    panner.setAttribute('aria-pressed', off ? 'true' : 'false');
    try { localStorage.setItem('atlas-panel', off ? 'off' : 'on'); } catch (e) {}
    // The stage just changed size, so the fitted box has to be recomputed.
    order.forEach(function (n) { delete HOME[n]; });
    requestAnimationFrame(function () { home(current); });
  });

  // ---- find ----------------------------------------------------------------------
  // Thirty components across four tabs is past what anyone scans. The index is built at
  // build time and searched over label, sublabel, kind, role and tab name, so "who checks
  // the grant" finds the roster without knowing it is called roster.
  var q = document.querySelector('.q'), hits = document.querySelector('.hits'), cursor = -1;
  function render(list) {
    hits.textContent = '';
    cursor = -1;
    if (!list.length) { hits.hidden = true; return; }
    list.slice(0, 8).forEach(function (r, i) {
      var li = el('li');
      li.setAttribute('role', 'option');
      li.tabIndex = -1;
      li.appendChild(el('b', null, r.label));
      li.appendChild(el('span', null, r.kind + ' · ' + r.tab));
      li.addEventListener('mousedown', function (e) {
        e.preventDefault();
        goTo(r.d, r.id);
        close();
      });
      li.dataset.i = i;
      hits.appendChild(li);
    });
    hits.hidden = false;
  }
  function close() { hits.hidden = true; q.value = ''; q.blur(); }
  function search() {
    var v = q.value.trim().toLowerCase();
    if (!v) { hits.hidden = true; return; }
    var words = v.split(/\s+/);
    render(D.index.filter(function (r) {
      return words.every(function (w) { return r.hay.indexOf(w) > -1; });
    }));
  }
  q.addEventListener('input', search);
  q.addEventListener('keydown', function (e) {
    var rows = [].slice.call(hits.children);
    if (e.key === 'Escape') { e.preventDefault(); close(); return; }
    if (!rows.length) return;
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      cursor = (cursor + (e.key === 'ArrowDown' ? 1 : rows.length - 1)) % rows.length;
      rows.forEach(function (r, i) { r.classList.toggle('on', i === cursor); });
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      var pick = rows[cursor < 0 ? 0 : cursor];
      if (pick) pick.dispatchEvent(new MouseEvent('mousedown'));
    }
  });
  q.addEventListener('blur', function () { setTimeout(function () { hits.hidden = true; }, 120); });
  document.addEventListener('keydown', function (e) {
    if (e.key === '/' && document.activeElement !== q &&
        !(e.target instanceof HTMLInputElement)) {
      e.preventDefault();
      q.focus();
    }
  });

  var themer = document.querySelector('.themer');
  themer.addEventListener('click', function () {
    var root = document.documentElement;
    var now = root.getAttribute('data-theme');
    var next = now === 'dark' ? 'light' : now === 'light' ? '' : 'dark';
    if (next) root.setAttribute('data-theme', next); else root.removeAttribute('data-theme');
    themer.textContent = next === 'dark' ? 'Dark' : next === 'light' ? 'Light' : 'Auto';
    try { localStorage.setItem('atlas-theme', next); } catch (e) {}
  });

  // LIGHT IS THE DEFAULT, NOT THE SYSTEM SETTING. This document is read once, by people
  // who did not choose its theme and mostly on a machine set to dark for editors rather
  // than for reading. An audit is long-form prose and a printed-page contrast is the one
  // more of them can read; the toggle is still one click for anyone who disagrees, and a
  // stored choice always wins over this.
  try {
    var t = localStorage.getItem('atlas-theme');
    var start = t === null ? 'light' : t;
    if (start) {
      document.documentElement.setAttribute('data-theme', start);
      themer.textContent = start === 'dark' ? 'Dark' : 'Light';
    }
  } catch (e) {
    document.documentElement.setAttribute('data-theme', 'light');
    themer.textContent = 'Light';
  }
  var saved = null;
  try {
    saved = localStorage.getItem('atlas-tab');
    if (localStorage.getItem('atlas-panel') === 'off') {
      document.body.classList.add('nopanel');
      panner.setAttribute('aria-pressed', 'true');
    }
  } catch (e) {}
  // A location in the atlas is a diagram and, optionally, a component: #admission/mcpauth.
  // Without it there is no way to send somebody THIS view — only the file, and directions.
  function fromHash() {
    var h = (location.hash || '').replace(/^#/, '');
    if (!h) return false;
    var bits = h.split('/');
    var tab = tabs.filter(function (t) { return t.dataset.name === bits[0]; })[0];
    if (!tab) return false;
    select(tab);
    if (bits[1] && isDiagram(bits[0]) && D.diagrams[bits[0]].nodes[bits[1]]) showNode(bits[0], bits[1]);
    return true;
  }
  var writingHash = false;
  function setHash(v) {
    writingHash = true;
    try { history.replaceState(null, '', '#' + v); } catch (e) { location.hash = v; }
    writingHash = false;
  }
  window.addEventListener('hashchange', function () { if (!writingHash) fromHash(); });

  if (!fromHash()) {
    var start = tabs.filter(function (t) { return t.dataset.name === saved; })[0] || tabs[0];
    select(start);
  }

  // ---- findings: where this system FAILS ---------------------------------------
  // The drawing answers what the system IS. A reader handed it during an audit is asking
  // something else — where does it BREAK — and the answer is a PATH, not a box: some
  // nodes and the arrows between them. Picking one dims the rest of the diagram to the
  // same level a selection does, so the failing hop is the only thing at full contrast.
  //
  // It DIMS, it never hides, for the reason the highlight code already gives: a hidden
  // edge changes what the picture claims, and a reader comparing two findings would be
  // shown two different graphs.
  var fsel = document.querySelector('.fsel');
  var fclear = document.querySelector('.fclear');
  var FIND = D.findings || [];
  var activeF = null;

  function clearFinding() {
    if (activeF === null) return;
    activeF = null;
    if (fsel) fsel.value = '';
    if (fclear) fclear.hidden = true;
    if (isDiagram(current)) showDiagram(current);
  }

  function showFinding(i) {
    var f = FIND[i];
    if (!f) return;
    activeF = i;
    if (fclear) fclear.hidden = false;
    if (fsel) fsel.value = String(i);
    // STAY WHERE THE READER IS IF THIS FINDING IS ALSO DRAWN HERE. Jumping to the home
    // diagram of every finding makes an overview map unusable: a reader working down the
    // map is thrown out of it by the first finding they open, and has to navigate back to
    // keep their place. `also` says the path exists on this drawing too, so paint it.
    var also = f.also || {};
    var on = (current !== f.diagram && also[current]) ? current : f.diagram;
    // select() re-runs showDiagram, which clears the highlight — so switch first, paint
    // after, or the finding lands on a diagram that immediately forgets it.
    if (current !== on) {
      var tab = tabs.filter(function (t) { return t.dataset.name === on; })[0];
      if (tab) select(tab);
    }
    var g = D.diagrams[on];
    var pathN, pathE;
    if (on === f.diagram) {
      pathN = f.nodes || [];
      pathE = f.edges || [];
    } else {
      // `also` is one flat list; a node id and an edge id cannot collide inside a
      // diagram, so each id is routed by which of the two it is.
      pathN = []; pathE = [];
      (also[on] || []).forEach(function (id) { (g.nodes[id] ? pathN : pathE).push(id); });
    }
    light(on, pathN, pathE);

    selected = null;
    inspect.classList.add('node', 'open');
    title.textContent = f.id + ' · ' + f.label;
    sub.textContent = g.tab;
    body.textContent = '';
    body.scrollTop = 0;

    if (f.severity) {
      body.appendChild(el('span', 'fnd-sev ' + f.severity.toLowerCase(), f.severity));
    }
    // HOW BADLY IT HURTS AND HOW WELL WE KNOW ARE DIFFERENT QUESTIONS, and a panel that
    // answers only the first invites the reader to assume the second. `lead` sits beside
    // `critical` on purpose: a one-lane critical is the most dangerous card on the page.
    var V = D.vocab || {};
    if (f.status) {
      var badge = el('span', 'fnd-st st-' + f.status, f.status === 'lead' ? 'ONE LANE' : f.status);
      badge.title = (V.status && V.status[f.status]) || '';
      body.appendChild(badge);
    }
    if (f.what) body.appendChild(el('p', 'role', f.what));

    var rows = [];
    if (f.basis && V.basis && V.basis[f.basis]) rows.push(['Rests on', V.basis[f.basis]]);
    if (f.measured) rows.push(['Measured', f.measured]);
    if (f.cost) rows.push(['Costs', f.cost]);
    if (f.owner) rows.push(['Owner', f.owner]);
    if (f.fix) rows.push(['Fix', f.fix]);
    if (f.ticket) rows.push(['Ticket', f.ticket]);
    if (rows.length) {
      var dl = el('dl', 'facts');
      rows.forEach(function (r) {
        dl.appendChild(el('dt', null, r[0]));
        dl.appendChild(el('dd', null, r[1]));
      });
      body.appendChild(dl);
    }

    // The measurements the claim rests on, as label/value pairs rather than as a story
    // about them — a reader checking a finding is scanning for a number, not reading.
    //
    // THE HEADING USED TO SAY "Which columns do not match", which was true of the one
    // atlas this was built from and false of every other: most findings are not column
    // mismatches, and since the data layer landed it also collided with the genuinely
    // column-shaped "Columns it holds" two blocks up. A finding may override it.
    if (f.keys) {
      var k = el('details');
      k.open = true;
      k.appendChild(el('summary', null, f.keysTitle || 'What the numbers say'));
      var kb = el('div', 'in'), kdl = el('dl', 'keys');
      f.keys.forEach(function (r) {
        kdl.appendChild(el('dt', null, r[0]));
        kdl.appendChild(el('dd', null, r[1]));
      });
      kb.appendChild(kdl);
      k.appendChild(kb);
      body.appendChild(k);
    }

    (f.tables || []).forEach(function (t) { body.appendChild(evidence(t)); });
    if (f.open && f.open.length) body.appendChild(openers(f.open, 'Check it yourself'));

    // The path, as buttons. This is what makes the finding locatable rather than merely
    // stated: every box and every arrow it runs through, one click from its own panel.
    if (pathN.length) {
      body.appendChild(el('p', 'sec', 'Where it happens'));
      var pn = el('div', 'path');
      pathN.forEach(function (id) {
        var n = g.nodes[id];
        if (!n) return;
        var b = el('button', null, n.label);
        b.type = 'button';
        b.addEventListener('click', function () { showNode(on, id); });
        pn.appendChild(b);
      });
      body.appendChild(pn);
    }
    if (pathE.length) {
      body.appendChild(el('p', 'sec', 'On these connections'));
      var pe = el('div', 'path');
      pathE.forEach(function (id) {
        var w = null;
        g.wires.forEach(function (x) { if (x.id === id) w = x; });
        if (!w) return;
        var b = el('button', 'edge', w.fromLabel + ' \u2192 ' + w.toLabel);
        b.type = 'button';
        b.addEventListener('click', function () { showWire(on, id); });
        pe.appendChild(b);
      });
      body.appendChild(pe);
    }
  }

  if (fsel && FIND.length) {
    FIND.forEach(function (f, i) {
      var o = el('option', null,
        (f.severity ? f.severity.toUpperCase().slice(0, 4) + ' \u00b7 ' : '') + f.id + ' \u2014 ' + f.label);
      o.value = String(i);
      fsel.appendChild(o);
    });
    fsel.addEventListener('change', function () {
      if (fsel.value === '') clearFinding(); else showFinding(Number(fsel.value));
    });
    if (fclear) fclear.addEventListener('click', clearFinding);
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && activeF !== null) clearFinding();
    });
    // Switching tab by hand abandons the finding: it belongs to one diagram, and leaving
    // that diagram with the picker still reading F1 says the highlight is somewhere on
    // this page when it is not.
    tabs.forEach(function (t) {
      t.addEventListener('click', function () {
        if (activeF !== null && FIND[activeF].diagram !== t.dataset.name) clearFinding();
      });
    });
  }

  // ---- the brief's links into the drawing ---------------------------------------
  // What makes this a tab rather than a second document: an explanation ends with the
  // path it is about, one click away and already highlighted. Delegated from the stage
  // because the brief is authored markup and its buttons are not known here by name.
  stage.addEventListener('click', function (ev) {
    var b = ev.target instanceof Element && ev.target.closest('.tofind');
    if (!b) return;
    var want = b.getAttribute('data-finding');
    for (var i = 0; i < FIND.length; i++) {
      if (FIND[i].id === want) { showFinding(i); return; }
    }
  });

  // Text extents decide the box, so a measurement taken before the webfont arrives is a
  // measurement of the fallback. Re-fit once fonts settle; `dataset.fitted` makes the
  // second pass a no-op for anything already correct.
  if (document.fonts && document.fonts.ready) {
    document.fonts.ready.then(function () {
      var svg = isDiagram(current) && canvas(current).querySelector('svg');
      if (svg) {
        delete svg.dataset.fitted;
        delete HOME[current];
        tighten(svg);
        home(current);
      }
    });
  }
})();
