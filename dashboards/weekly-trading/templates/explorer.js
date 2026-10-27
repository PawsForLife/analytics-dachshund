/* Pet Circle Weekly Trading Dashboard - Commercial tab: interactive metric explorer.
   Reads one dataset, commercial_explorer: one row per metric x split x comparison period x segment,
   with this week (cur), the comparison (base) and the change (delta) computed in the SQL. The page only
   picks the slice the reader asks for and draws it. Loaded before app.js, which calls html() inside the
   Commercial tab and mount() once the tab is in place. */
(function () {
  'use strict';
  const DS = 'commercial_explorer';
  const MINUS = '−';

  // ---------- what can be explored ----------
  const LINE_SPLITS = ['book', 'category', 'brand'];
  const ORDER_SPLITS = ['channel', 'status', 'state'];
  const METRICS = [
    { key: 'revenue', label: 'Product revenue', unit: '$', type: 'waterfall', splits: [...LINE_SPLITS, ...ORDER_SPLITS] },
    { key: 'margin', label: 'Product margin', unit: '$', type: 'waterfall', splits: [...LINE_SPLITS, ...ORDER_SPLITS] },
    { key: 'orders', label: 'Orders', unit: 'n', type: 'waterfall', splits: ORDER_SPLITS },
    { key: 'customers', label: 'Purchasing customers', unit: 'n', type: 'segment', splits: ORDER_SPLITS },
    { key: 'aov', label: 'AOV', unit: '$2', type: 'segment', splits: ORDER_SPLITS },
  ];
  const SPLITS = { book: 'Book', category: 'Category', brand: 'Brand', channel: 'Channel', status: 'Customer status', state: 'Delivery state' };
  const PLAN_SPLITS = ['book', 'category'];
  const planLabel = () => { const c = dash.data('cal'); return c.status === 'ok' && c.data.length ? c.data[0].plan_label : 'Plan'; };
  const PERIODS = () => [
    { key: 'lw', label: 'vs last week', base: 'Last week' },
    { key: 'l12', label: 'vs 12-week average', base: '12-wk avg' },
    { key: 'ly', label: 'vs LY (same 445 week)', base: 'LY' },
    { key: 'plan', label: 'vs ' + planLabel().toLowerCase(), base: planLabel() },
  ];
  const S = { metric: 'revenue', period: 'lw', split: 'channel', msg: '' };
  const M = () => METRICS.find((m) => m.key === S.metric);
  const P = () => PERIODS().find((p) => p.key === S.period);
  const planOk = (m, split) => (m.key === 'revenue' || m.key === 'margin') && PLAN_SPLITS.includes(split);

  // ---------- formats ----------
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const enc = (s) => encodeURIComponent(String(s));
  const isN = (v) => v !== null && v !== undefined && v !== '' && !isNaN(+v);
  function moneyAbs(a, full) {
    if (full) return '$' + a.toFixed(2);
    if (a >= 1e6) return '$' + (a / 1e6).toFixed(2) + 'M';
    if (a >= 1e4) return '$' + Math.round(a / 1e3) + 'k';
    if (a >= 1e3) return '$' + (a / 1e3).toFixed(1) + 'k';
    return '$' + Math.round(a);
  }
  function numAbs(a) {
    if (a >= 1e6) return (a / 1e6).toFixed(2) + 'M';
    if (a >= 1e4) return (a / 1e3).toFixed(1) + 'k';
    return Math.round(a).toLocaleString('en-AU');
  }
  const absU = (u, a) => (u === '$' ? moneyAbs(a) : u === '$2' ? moneyAbs(a, true) : numAbs(a));
  const lvl = (u, v) => (isN(v) ? (+v < 0 ? MINUS : '') + absU(u, Math.abs(+v)) : 'n/a');
  const chg = (u, v) => (isN(v) ? (+v > 0 ? '+' : +v < 0 ? MINUS : '') + absU(u, Math.abs(+v)) : 'n/a');
  const pctF = (f) => (isN(f) ? (+f >= 0 ? '+' : MINUS) + Math.abs(+f * 100).toFixed(1) + '%' : 'n/a');
  const shareF = (f) => (isN(f) ? Math.round(+f * 100) + '%' : '');
  const cls = (d) => (!isN(d) || Math.abs(+d) < 1e-9 ? 'flat' : +d > 0 ? 'pos' : 'neg');
  const whereOf = (r) => ['metric', 'split', 'period', 'segment'].map((k) => enc(k) + '=' + enc(r[k])).join('&amp;');
  const V = (r, field, text, c) => '<span data-source="' + DS + '" data-field="' + field + '" data-where="' + whereOf(r) + '"' + (c ? ' class="' + c + '"' : '') + '>' + text + '</span>';
  const segLabel = (r) => (r.segment.startsWith('All other') && r.n_members ? r.segment + ' (' + r.n_members + ')' : r.segment);

  // ---------- the slice ----------
  function slice() {
    const d = dash.data(DS);
    if (d.status !== 'ok') return null;
    const rs = d.data.filter((r) => r.metric === S.metric && r.split === S.split && r.period === S.period);
    const total = rs.find((r) => r.is_total === true || r.is_total === 'true') || null;
    const segs = rs.filter((r) => !(r.is_total === true || r.is_total === 'true'))
      .map((r) => ({ ...r, cur: +r.cur, base: isN(r.base) ? +r.base : null, delta: isN(r.delta) ? +r.delta : null, sort: +r.sort, n_members: +r.n_members || 0 }))
      .sort((a, b) => (a.sort >= 97 || b.sort >= 97 ? a.sort - b.sort : (b.delta ?? 0) - (a.delta ?? 0)));
    return { total: total && { ...total, cur: +total.cur, base: +total.base, delta: +total.delta }, segs };
  }

  // ---------- markup ----------
  function controls() {
    const m = M();
    const opt = (v, t, sel, dis) => '<option value="' + v + '"' + (sel ? ' selected' : '') + (dis ? ' disabled' : '') + '>' + esc(t) + '</option>';
    let h = '<div class="xp-controls">';
    h += '<label class="xp-field"><span>Metric</span><select data-xp="metric">' + METRICS.map((x) => opt(x.key, x.label, x.key === S.metric)).join('') + '</select></label>';
    h += '<label class="xp-field"><span>Compare</span><select data-xp="period">' + PERIODS().map((p) => opt(p.key, p.label + (p.key === 'plan' && !(m.key === 'revenue' || m.key === 'margin') ? ' (revenue and margin only)' : ''), p.key === S.period, p.key === 'plan' && !(m.key === 'revenue' || m.key === 'margin'))).join('') + '</select></label>';
    h += '<label class="xp-field"><span>Split by</span><select data-xp="split">' + m.splits.map((s) => opt(s, SPLITS[s] + (S.period === 'plan' && !PLAN_SPLITS.includes(s) ? ' (no plan split)' : ''), s === S.split, S.period === 'plan' && !PLAN_SPLITS.includes(s))).join('') + '</select></label>';
    h += '<span class="chip">' + (m.type === 'waterfall' ? 'Waterfall: adds up to the total change' : 'Change by segment: segments move independently') + '</span>';
    return h + '</div>';
  }
  function body() {
    const d = dash.data(DS);
    if (['error', 'missing', 'declined'].includes(d.status)) return '<div class="fail">Failed to load</div>';
    if (d.status !== 'ok') return '<div class="dash-skeleton" style="min-height:260px;border-radius:var(--cds-radius)"></div>';
    const sl = slice(), m = M(), p = P();
    if (!sl || !sl.total || !sl.segs.length) return '<p class="note">No data for this combination.</p>';
    const t = sl.total;
    let h = '<p class="xp-head" id="xp-headline"><b>' + esc(m.label) + '</b> ' + V(t, 'cur', lvl(m.unit, t.cur)) + ' this week, ' + V(t, 'delta', chg(m.unit, t.delta), cls(t.delta)) + ' (' + V(t, 'pct', pctF(t.pct)) + ') against ' + esc(p.base) + ' of ' + V(t, 'base', lvl(m.unit, t.base)) + '.</p>';
    if (S.msg) h += '<p class="note xp-msg">' + esc(S.msg) + '</p>';
    h += '<div class="legend">' + (m.type === 'waterfall' ? '<span><i style="background:var(--pc-c2)"></i>' + esc(p.base) + ' and this week</span>' : '') + '<span><i style="background:var(--color-ok)"></i>Up</span><span><i style="background:var(--color-bad)"></i>Down</span>' + (m.type === 'segment' ? '<span><i style="background:var(--pc-c2)"></i>All ' + esc(m.label.toLowerCase()) + '</span>' : '') + '</div>';
    h += '<div class="chart xp-chart" id="ch-explorer" data-source="' + DS + '" role="img" aria-label="' + esc(m.label + ' ' + p.label + ' by ' + SPLITS[S.split]) + '"></div>';
    // the numbers behind the chart
    const rowsH = [...sl.segs, t].map((r) => '<tr' + (r === t ? ' class="tot"' : '') + '><td>' + esc(r === t ? 'Total' : segLabel(r)) + '</td><td>' + V(r, 'base', lvl(m.unit, r.base)) + '</td><td>' + V(r, 'cur', lvl(m.unit, r.cur)) + '</td><td class="' + cls(r.delta) + '">' + V(r, 'delta', chg(m.unit, r.delta)) + '</td><td class="' + cls(r.delta) + '">' + V(r, 'pct', pctF(r.pct)) + '</td>' + (m.type === 'waterfall' ? '<td>' + (r === t ? '' : V(r, 'share', shareF(r.share))) + '</td>' : '') + '</tr>').join('');
    h += '<details class="xp-details"><summary>The numbers</summary><div class="tw"><table class="t"><thead><tr><th>' + esc(SPLITS[S.split]) + '</th><th>' + esc(p.base) + '</th><th>This week</th><th>Change</th><th>% change</th>' + (m.type === 'waterfall' ? '<th>Share of change</th>' : '') + '</tr></thead><tbody>' + rowsH + '</tbody></table></div></details>';
    h += '<p class="note">' + notes(m, p) + '</p>';
    return h;
  }
  function notes(m, p) {
    const n = [];
    if (m.type === 'waterfall') n.push('Each bar is one segment’s change; together they add exactly to the total change. The axis does not start at zero, so small weekly moves stay visible; the break mark on the end bars shows where it is cut.');
    else n.push(m.key === 'customers' ? 'A customer who ordered through two channels (or two delivery states) counts in both, so the segments do not add up to the total.' : 'AOV is product revenue divided by orders within each segment. A segment AOV can rise while the total falls when mix shifts toward lower-AOV segments.');
    if (LINE_SPLITS.includes(S.split)) n.push('Book, category and brand are built from basket lines and tie to the order-level total. Category and brand show the eight biggest movers for this comparison; the rest are rolled into one bar.');
    if (S.split === 'status') n.push('New = first-ever completed order; Reactivated = no prior order or a gap of 92 days or more; Returning = otherwise.');
    if (S.period === 'l12') n.push('12-week average = the mean of the 12 weeks before this one, as on the scorecard.');
    if (S.period === 'plan') n.push('The plan is the finance category target for the week; summed across categories it equals the scorecard plan.');
    n.push('Excl GST, orders not cancelled, refreshed with the rest of the dashboard every Monday.');
    return n.join(' ');
  }
  function html() {
    return '<div class="xp" id="xp-root">' + controls() + '<div class="card xp-card" id="xp-body">' + body() + '</div></div>';
  }

  // ---------- chart ----------
  function tipFor(el) { let tp = el.querySelector('.tip'); if (!tp) { tp = document.createElement('div'); tp.className = 'tip'; el.appendChild(tp); } return tp; }
  function place(el, tp, x, y) { tp.style.display = 'block'; const w = tp.offsetWidth, W = el.clientWidth; tp.style.left = Math.max(0, Math.min(W - w, x + 10)) + 'px'; tp.style.top = Math.max(0, y - 10 - tp.offsetHeight) + 'px'; }
  function axisStyle(g) { g.attr('font-size', null).attr('font-family', null); g.selectAll('text').attr('fill', 'var(--color-fg-muted)').style('font-size', 'var(--cds-font-size-caption)'); g.selectAll('line,path').attr('stroke', 'var(--cds-chart-axis)'); }
  const tickFmt = (u) => (v) => (u === 'n' ? (Math.abs(v) >= 1e3 ? (v / 1e3).toFixed(Math.abs(v) >= 1e5 ? 0 : 1) + 'k' : String(Math.round(v))) : u === '$2' ? '$' + v.toFixed(0) : Math.abs(v) >= 1e6 ? '$' + (v / 1e6).toFixed(2) + 'M' : '$' + Math.round(v / 1e3) + 'k');

  function bars() {
    const sl = slice(), m = M(), p = P();
    if (!sl || !sl.total) return null;
    const t = sl.total;
    if (m.type === 'waterfall') {
      let run = t.base;
      const out = [{ label: p.base, kind: 'total', lo: null, hi: t.base, r: t, v: t.base }];
      for (const s of sl.segs) { const lo = run, hi = run + (s.delta || 0); out.push({ label: segLabel(s), kind: (s.delta || 0) >= 0 ? 'pos' : 'neg', lo: Math.min(lo, hi), hi: Math.max(lo, hi), from: lo, to: hi, r: s, v: s.delta }); run = hi; }
      out.push({ label: 'This week', kind: 'total', lo: null, hi: t.cur, r: t, v: t.cur });
      const path = out.flatMap((b) => (b.kind === 'total' ? [b.hi] : [b.lo, b.hi]));
      const mn = Math.min(...path), mx = Math.max(...path), span = Math.max(mx - mn, Math.abs(mx) * 0.01, 1);
      const floor = Math.max(0, mn - span * 0.35);
      out.forEach((b) => { if (b.kind === 'total') b.lo = floor; });
      return { bars: out, domain: [floor, mx + span * 0.12], truncated: floor > 0, zero: null };
    }
    const out = [{ label: 'All', kind: 'total', lo: Math.min(0, t.delta), hi: Math.max(0, t.delta), r: t, v: t.delta, gapAfter: true }];
    for (const s of sl.segs) out.push({ label: segLabel(s), kind: (s.delta || 0) >= 0 ? 'pos' : 'neg', lo: Math.min(0, s.delta || 0), hi: Math.max(0, s.delta || 0), r: s, v: s.delta });
    const ext = [Math.min(0, ...out.map((b) => b.lo)), Math.max(0, ...out.map((b) => b.hi))];
    const pad = (ext[1] - ext[0]) * 0.15 || 1;
    return { bars: out, domain: [ext[0] < 0 ? ext[0] - pad : 0, ext[1] > 0 ? ext[1] + pad : 0], truncated: false, zero: 0 };
  }
  const fill = (k) => (k === 'total' ? 'var(--pc-c2)' : k === 'pos' ? 'var(--color-ok)' : 'var(--color-bad)');

  function tipHTML(b) {
    const m = M(), p = P(), r = b.r;
    const head = '<span class="k">' + esc(b.kind === 'total' ? (m.type === 'waterfall' ? b.label : 'All ' + m.label.toLowerCase()) : segLabel(r)) + '</span><br>';
    if (m.type === 'waterfall' && b.kind === 'total') return head + esc(m.label) + ' ' + lvl(m.unit, b.v);
    let s = head + esc(p.base) + ' ' + lvl(m.unit, r.base) + ' → this week ' + lvl(m.unit, r.cur) + '<br>Change ' + chg(m.unit, r.delta) + ' (' + pctF(r.pct) + ')';
    if (m.type === 'waterfall' && isN(r.share)) s += '<br>' + shareF(r.share) + ' of the total change';
    return s;
  }

  function draw(el) {
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const B = bars();
    if (!B || !el.clientWidth || typeof d3 === 'undefined') return;
    const m = M(), W = el.clientWidth, n = B.bars.length, vertical = W >= 620;
    const tp = tipFor(el);
    const lab = (b) => (b.kind === 'total' ? (m.type === 'waterfall' ? lvl(m.unit, b.v) : chg(m.unit, b.v)) : chg(m.unit, b.v));
    if (vertical) {
      const H = 320, mg = { t: 22, r: 8, b: 48, l: 56 };
      const x = d3.scaleBand(B.bars.map((b, i) => i), [mg.l, W - mg.r]).padding(0.22);
      const y = d3.scaleLinear(B.domain, [H - mg.b, mg.t]).nice();
      if (B.truncated) y.domain([Math.max(B.domain[0], y.domain()[0]), y.domain()[1]]);
      const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
      svg.append('g').attr('transform', 'translate(' + mg.l + ',0)').call(d3.axisLeft(y).ticks(5).tickFormat(tickFmt(m.unit))).call(axisStyle).call((g) => g.select('.domain').remove());
      if (B.zero !== null) svg.append('line').attr('x1', mg.l).attr('x2', W - mg.r).attr('y1', y(0)).attr('y2', y(0)).attr('stroke', 'var(--cds-chart-axis)');
      // connectors between waterfall steps
      if (m.type === 'waterfall') B.bars.slice(0, -1).forEach((b, i) => { const lvlV = b.kind === 'total' ? b.hi : b.to; svg.append('line').attr('x1', x(i) + x.bandwidth()).attr('x2', x(i + 1)).attr('y1', y(lvlV)).attr('y2', y(lvlV)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '2 2'); });
      const g = svg.append('g');
      B.bars.forEach((b, i) => {
        const y0 = y(Math.max(b.lo, y.domain()[0])), y1 = y(b.hi), h = Math.max(1.5, y0 - y1);
        g.append('rect').attr('x', x(i)).attr('width', x.bandwidth()).attr('y', y0 - h).attr('height', h).attr('rx', 3).attr('fill', fill(b.kind));
        if (B.truncated && b.kind === 'total') { const zy = y0 - 8; g.append('path').attr('d', 'M' + (x(i) + 3) + ',' + zy + ' l' + x.bandwidth() * 0.3 + ',-5 l' + x.bandwidth() * 0.3 + ',10 l' + (x.bandwidth() * 0.4 - 6) + ',-5').attr('fill', 'none').attr('stroke', 'var(--color-panel)').attr('stroke-width', 2); }
        const neg = m.type === 'segment' && b.v < 0;
        g.append('text').attr('x', x(i) + x.bandwidth() / 2).attr('y', neg ? y(b.lo) + 14 : y1 - 6).attr('text-anchor', 'middle').attr('fill', 'var(--color-fg)').style('font-size', 'var(--cds-font-size-caption)').style('font-weight', 600).text(lab(b));
        // two-line category label, clipped to the bar's width
        const maxCh = Math.max(4, Math.floor(x.step() / 6.2));
        const words = String(b.label).split(' '); const lines = ['', ''];
        for (const w of words) { if ((lines[0] + ' ' + w).trim().length <= maxCh && !lines[1]) lines[0] = (lines[0] + ' ' + w).trim(); else lines[1] = (lines[1] + ' ' + w).trim(); }
        if (lines[1].length > maxCh) lines[1] = lines[1].slice(0, maxCh - 1) + '…';
        const tx = g.append('text').attr('x', x(i) + x.bandwidth() / 2).attr('y', H - mg.b + 16).attr('text-anchor', 'middle').attr('fill', 'var(--color-fg-muted)').style('font-size', 'var(--cds-font-size-caption)');
        lines.filter(Boolean).forEach((l, k) => tx.append('tspan').attr('x', x(i) + x.bandwidth() / 2).attr('dy', k ? 13 : 0).text(l));
        g.append('rect').attr('x', x(i) - x.step() * 0.11).attr('width', x.step()).attr('y', mg.t).attr('height', H - mg.t - mg.b).attr('fill', 'transparent')
          .on('mousemove', (ev) => { const [px, py] = d3.pointer(ev, el); tp.innerHTML = tipHTML(b); place(el, tp, px, py); })
          .on('mouseleave', () => { tp.style.display = 'none'; });
      });
    } else {
      // narrow: horizontal bars, one row per step, labels on the left
      const row = 26, mg = { t: 6, r: 64, b: 22, l: Math.min(140, Math.round(W * 0.38)) }, H = mg.t + mg.b + row * n;
      const yb = d3.scaleBand(B.bars.map((b, i) => i), [mg.t, H - mg.b]).padding(0.2);
      const x = d3.scaleLinear(B.domain, [mg.l, W - mg.r]).nice();
      if (B.truncated) x.domain([Math.max(B.domain[0], x.domain()[0]), x.domain()[1]]);
      const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
      svg.append('g').attr('transform', 'translate(0,' + (H - mg.b) + ')').call(d3.axisBottom(x).ticks(3).tickFormat(tickFmt(m.unit))).call(axisStyle);
      if (B.zero !== null) svg.append('line').attr('y1', mg.t).attr('y2', H - mg.b).attr('x1', x(0)).attr('x2', x(0)).attr('stroke', 'var(--cds-chart-axis)');
      const g = svg.append('g');
      B.bars.forEach((b, i) => {
        const x0 = x(Math.max(b.lo, x.domain()[0])), x1 = x(b.hi), w = Math.max(1.5, x1 - x0);
        g.append('rect').attr('y', yb(i)).attr('height', yb.bandwidth()).attr('x', x0).attr('width', w).attr('rx', 3).attr('fill', fill(b.kind));
        const maxCh = Math.floor(mg.l / 6.4); const l = String(b.label);
        g.append('text').attr('x', mg.l - 6).attr('y', yb(i) + yb.bandwidth() / 2 + 4).attr('text-anchor', 'end').attr('fill', 'var(--color-fg-muted)').style('font-size', 'var(--cds-font-size-caption)').text(l.length > maxCh ? l.slice(0, maxCh - 1) + '…' : l);
        g.append('text').attr('x', x0 + w + 4).attr('y', yb(i) + yb.bandwidth() / 2 + 4).attr('fill', 'var(--color-fg)').style('font-size', 'var(--cds-font-size-caption)').style('font-weight', 600).text(lab(b));
        g.append('rect').attr('x', 0).attr('width', W).attr('y', yb(i)).attr('height', yb.step()).attr('fill', 'transparent')
          .on('mousemove', (ev) => { const [px, py] = d3.pointer(ev, el); tp.innerHTML = tipHTML(b); place(el, tp, px, py); })
          .on('mouseleave', () => { tp.style.display = 'none'; });
      });
    }
  }

  function mount(panel) { const el = (panel || document).querySelector('#ch-explorer'); if (el) draw(el); }
  function refresh() {
    const root = document.getElementById('xp-root'); if (!root) return;
    root.outerHTML = html();
    mount(document.getElementById('commercial'));
  }

  // ---------- controls: one delegated listener, the panel is redrawn on every data change ----------
  const panel = document.getElementById('commercial');
  if (panel) panel.addEventListener('change', (e) => {
    const sel = e.target.closest('[data-xp]'); if (!sel) return;
    S.msg = '';
    S[sel.dataset.xp] = sel.value;
    const m = M();
    if (!m.splits.includes(S.split)) S.split = m.splits[0];
    if (S.period === 'plan' && !planOk(m, S.split)) {
      if (sel.dataset.xp === 'split' || sel.dataset.xp === 'metric') { S.period = 'lw'; S.msg = 'Plan is set by merchandise category only, so the comparison moved to last week.'; }
      else { S.split = 'book'; S.msg = 'Plan is set by merchandise category only, so the split moved to Book.'; }
    }
    refresh();
  });

  window.pcExplorer = { html, mount };
})();
