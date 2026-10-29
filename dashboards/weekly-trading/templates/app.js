/* Pet Circle Weekly Trading Dashboard - page script.
   Every figure comes from a dataset written weekly by the Monday refresh. Variances are columns in the
   data (computed in the SQL), so the page only formats and chooses words by the sign of the number. */
(function () {
  'use strict';
  // Pet Circle chart palette (pc-styling): Mid Teal, Deep Teal, then neutrals; CSS vars carry the dark-mode variants
  const PCC = ['var(--pc-c1)', 'var(--pc-c2)', 'var(--pc-c3)', 'var(--pc-c4)', 'var(--pc-c5)'];
  const COH = ['var(--pc-c2)', 'var(--pc-c1)', 'var(--pc-c1-tint)'];

  // ---------- data access ----------
  const D = (id) => dash.data(id);
  const ok = (id) => D(id).status === 'ok';
  const bySort = (a, b) => (a.sort ?? 0) - (b.sort ?? 0);
  const rows = (id) => (ok(id) ? [...D(id).data].sort(bySort) : []);
  const one = (id) => (ok(id) && D(id).data.length ? D(id).data[0] : null);
  const find = (id, k, v) => rows(id).find((r) => String(r[k]) === String(v)) || null;

  // ---------- text helpers ----------
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const enc = (s) => encodeURIComponent(String(s));
  const where = (o) => Object.entries(o).map(([k, v]) => enc(k) + '=' + enc(v)).join('&amp;');
  const at = (ds, field, wh) => ' data-source="' + ds + '"' + (field ? ' data-field="' + field + '"' : '') + (wh ? ' data-where="' + where(wh) + '"' : '');
  const V = (ds, field, wh, text, cls) => '<span' + at(ds, field, wh) + (cls ? ' class="' + cls + '"' : '') + '>' + text + '</span>';

  // ---------- number formats ----------
  const isN = (v) => v !== null && v !== undefined && v !== '' && !isNaN(+v);
  const MINUS = '−';
  const sg = (v, s) => (+v > 0 ? '+' : +v < 0 ? MINUS : '') + s;
  const NA = 'n/a';
  function moneyAbs(a) {
    if (a >= 1e6) return '$' + (a / 1e6).toFixed(2) + 'M';
    if (a >= 1e4) return '$' + Math.round(a / 1e3) + 'k';
    if (a >= 1e3) return '$' + (a / 1e3).toFixed(1) + 'k';
    return '$' + a.toFixed(2);
  }
  const money = (v) => (isN(v) ? (+v < 0 ? MINUS : '') + moneyAbs(Math.abs(+v)) : NA);
  const smoney = (v) => (isN(v) ? sg(v, moneyAbs(Math.abs(+v))) : NA);
  function numAbs(a, dp) {
    if (a >= 1e6) return (a / 1e6).toFixed(2) + 'M';
    if (a >= 1e4) return (a / 1e3).toFixed(1) + 'k';
    if (dp === 0) return Math.round(a).toLocaleString('en-AU');
    if (dp !== undefined) return a.toFixed(dp);
    if (Math.abs(a - Math.round(a)) > 1e-9 && a < 100) return a.toFixed(2);
    return Math.round(a).toLocaleString('en-AU');
  }
  const num = (v, dp) => (isN(v) ? (+v < 0 ? MINUS : '') + numAbs(Math.abs(+v), dp) : NA);
  const snum = (v, dp) => (isN(v) ? sg(v, numAbs(Math.abs(+v), dp)) : NA);
  const pct = (v, dp = 1) => (isN(v) ? (+v).toFixed(dp) + '%' : NA);
  const frac = (f, dp = 1) => (isN(f) ? sg(f, Math.abs(f * 100).toFixed(dp) + '%') : NA);
  const pp = (v, dp = 1) => (isN(v) ? sg(v, Math.abs(+v).toFixed(dp) + 'pp') : NA);
  const bps = (vpp) => (isN(vpp) ? sg(vpp, Math.abs(Math.round(vpp * 100)) + 'bps') : NA);
  const bpsRaw = (b) => (isN(b) ? sg(b, Math.abs(Math.round(b)) + 'bps') : NA);
  const fmtU = (u, v) => (u === '$' ? money(v) : u === 'pct' ? pct(v) : num(v));
  const dU = (u, d) => (u === '$' ? smoney(d) : u === 'pct' ? pp(d) : snum(d));
  const MON = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const dateLabel = (s) => { if (!s) return NA; const d = new Date(String(s).slice(0, 10) + 'T00:00:00Z'); return isNaN(d) ? NA : d.getUTCDate() + ' ' + MON[d.getUTCMonth()]; };
  const dollars2 = (v) => (isN(v) ? (+v < 0 ? MINUS : '') + '$' + Math.abs(+v).toFixed(2) : NA);
  const sdollars2 = (v) => (isN(v) ? sg(v, '$' + Math.abs(+v).toFixed(2)) : NA);
  const dollars = (v) => (isN(v) ? '$' + Math.round(+v).toLocaleString('en-AU') : NA);
  const cls = (d, good = true) => (!isN(d) || Math.abs(+d) < 1e-9 ? 'flat' : (+d > 0) === good ? 'pos' : 'neg');
  const pill = (label, text, c) => '<span class="pill ' + c + '">' + text + ' ' + label + '</span>';

  // ---------- loading and failure states ----------
  function state(ids) {
    const list = [].concat(ids);
    if (list.some((id) => ['error', 'missing'].includes(D(id).status))) return '<div class="fail">Failed to load</div>';
    if (list.some((id) => D(id).status !== 'ok')) return '<div class="dash-skeleton" style="min-height:80px;border-radius:var(--cds-radius)"></div>';
    return '';
  }
  const ready = (ids) => [].concat(ids).every(ok);

  // ---------- table builder (one dataset per table, marked once) ----------
  function tbl(ds, key, cols, data, opt = {}) {
    if (!ok(ds)) return state(ds);
    const multi = key.includes(',');
    let h = '<div class="tw"><table class="t"' + at(ds) + ' data-row-key="' + key + '"' + (opt.id ? ' id="' + opt.id + '"' : '') + '><thead><tr>';
    h += cols.map((c) => '<th data-field="' + c.f + '">' + esc(c.h) + '</th>').join('') + '</tr></thead><tbody>';
    for (const r of data) {
      const k = multi ? key.split(',').map((x) => enc(r[x])).join(',') : String(r[key]);
      const rc = opt.rowCls ? opt.rowCls(r) : '';
      const ra = opt.rowAttr ? ' ' + opt.rowAttr(r) : '';
      const hidden = opt.hide && opt.hide(r) ? ' hidden' : '';
      h += '<tr data-key="' + esc(k) + '"' + (rc ? ' class="' + rc + '"' : '') + ra + hidden + '>';
      h += cols.map((c) => '<td' + (c.c ? ' class="' + c.c(r) + '"' : '') + '>' + (c.v ? c.v(r) : esc(r[c.f])) + '</td>').join('');
      h += '</tr>';
    }
    return h + '</tbody></table></div>';
  }

  // ---------- layout helpers ----------
  const card = (title, note, body, extra = '') => '<div class="card"' + extra + '>' + (title ? '<h4>' + title + '</h4>' : '') + (note ? '<p class="note">' + note + '</p>' : '') + body + '</div>';
  const sec = (n, title) => '<div class="sec">' + (n ? '<span class="n">' + n + '</span>' : '') + '<h3>' + title + '</h3></div>';
  const tile = (lab, big, foot, pills = '') => '<div class="card tile"><div class="lab">' + lab + '</div><div class="big">' + big + '</div>' + (pills ? '<div class="pills">' + pills + '</div>' : '') + (foot ? '<div class="foot">' + foot + '</div>' : '') + '</div>';
  const ph = (title, why, items, needs) => '<div class="ph-card"><span class="chip ph">Placeholder</span><h4 style="margin-top:8px">' + title + '</h4><p class="note">' + why + '</p><ul>' + items.map((i) => '<li>' + i + '</li>').join('') + '</ul>' + (needs ? '<p class="note"><b>To wire this up:</b> ' + needs + '</p>' : '') + '</div>';
  const hlBoxes = (good, watch, foot) => '<div class="hl"><div class="box good"><h4>What is working</h4><ul>' + (good.length ? good.map((x) => '<li>' + x + '</li>').join('') : '<li class="flat">Nothing above its comparison this week.</li>') + '</ul></div><div class="box watch"><h4>What to watch</h4><ul>' + (watch.length ? watch.map((x) => '<li>' + x + '</li>').join('') : '<li class="flat">Nothing below its comparison this week.</li>') + '</ul></div></div><p class="note" style="margin-top:-6px;margin-bottom:12px">' + (foot || 'Derived from this tab’s own figures by the sign of each movement, not curated commentary. The tables below are the source of truth.') + '</p>';
  const plan = () => { const c = one('cal'); return c ? c.plan_label : 'Plan'; };
  const planS = () => (plan() === 'Forecast' ? 'Fcst' : 'Bud');
  const above = (d, a = 'above', b = 'below') => (+d >= 0 ? a : b);

  // ---------- tabs ----------
  const TABS = [
    { id: 'highlights', label: 'Highlights', agenda: 'Opening overview' },
    { id: 'cx', label: 'CX', agenda: 'CX overview · 3 min' },
    { id: 'commercial', label: 'Commercial', agenda: 'Commercial Performance · 5 min' },
    { id: 'media', label: 'Media & Funnel', agenda: 'Media & Funnel Review · 10 min' },
    { id: 'customer', label: 'Customer', agenda: 'Customer Retention & Value Review · 10 min' },
    { id: 'autodelivery', label: 'Auto Delivery', agenda: 'Customer Retention & Value Review' },
    { id: 'category', label: 'Category', agenda: 'Category Review · 10 min' },
    { id: 'price', label: 'Price', agenda: 'Category Review' },
    { id: 'inventory', label: 'Inventory', agenda: 'Inventory Planning Review · 3 min' },
    { id: 'operations', label: 'Operations', agenda: 'Supply Chain Operational Review · 5 min' },
  ];
  let current = 'highlights';
  const tabsEl = document.getElementById('pc-tabs');
  tabsEl.innerHTML = TABS.map((t) => '<button class="pc-tab' + (t.later ? ' later' : '') + '" role="tab" data-tab="' + t.id + '" aria-selected="false">' + esc(t.label) + '</button>').join('');
  tabsEl.addEventListener('click', (e) => { const b = e.target.closest('[data-tab]'); if (b) show(b.dataset.tab, true); });
  function show(id, link) {
    if (!TABS.some((t) => t.id === id)) return;
    current = id;
    for (const t of TABS) {
      document.getElementById(t.id).hidden = t.id !== id;
      tabsEl.querySelector('[data-tab="' + t.id + '"]').setAttribute('aria-selected', String(t.id === id));
    }
    if (link) dash.setLink(id);
    charts();
  }
  const ptitle = (t, extra = '') => '<div class="pc-ptitle"><h2>' + esc(t.label) + '</h2><span class="chip">' + esc(t.agenda) + '</span>' + (t.later ? '<span class="chip ph">Phase 2</span>' : '') + extra + '</div>';
  const T = Object.fromEntries(TABS.map((t) => [t.id, t]));

  // ---------- shared movers ----------
  const SC = () => Object.fromEntries(rows('scorecard').map((r) => [r.metric, r]));
  const scW = (m) => ({ metric: m });
  function scText(r, field) { // a scorecard value as a marked span
    const v = r[field];
    const t = field === 'tw' || field === 'bud' || field === 'lw' || field === 'ly' ? fmtU(r.unit, v) : r.metric === 'product_margin_pct' && field.startsWith('d_') && !field.endsWith('_pct') ? bps(v) : field.endsWith('_pct') ? frac(v) : dU(r.unit, v);
    return V('scorecard', field, scW(r.metric), t);
  }
  function planMovers(metrics) {
    const S = SC(); const good = [], watch = [];
    const list = metrics.map((m) => S[m]).filter((r) => r && isN(r.d_bud_pct)).sort((a, b) => Math.abs(b.d_bud_pct) - Math.abs(a.d_bud_pct));
    for (const r of list) {
      const s = '<b>' + esc(r.label) + ' ' + scText(r, 'tw') + '</b>, ' + scText(r, 'd_bud') + ' vs ' + plan() + ' (' + scText(r, 'd_bud_pct') + ').';
      (r.d_bud >= 0 ? good : watch).push(s);
    }
    return { good, watch };
  }

  // ================= HIGHLIGHTS =================
  function rHighlights() {
    const t = T.highlights;
    let h = ptitle(t);
    const need = ['cal', 'scorecard', 'week_ahead', 'fy_periods'];
    if (!ready(need)) return h + state(need);
    const S = SC(), wa = one('week_ahead'), cur = rows('fy_periods').find((r) => r.kind === 'current');
    // week ahead
    h += sec('', 'The week ahead');
    const wh = (o) => o;
    const curW = cur ? { period: cur.period } : null;
    let b1 = '';
    if (cur) {
      b1 = tile(esc(cur.period) + (cur.is_closed ? ' closed vs plan' : ' to date vs plan'), V('fy_periods', 'd_bud', curW, smoney(cur.d_bud), cls(cur.d_bud)),
        V('fy_periods', 'actual', curW, money(cur.actual)) + ' against ' + V('fy_periods', 'budget', curW, money(cur.budget)) + ' of plan across ' + V('fy_periods', 'weeks_traded', curW, cur.weeks_traded) + ' weeks, ' + V('fy_periods', 'd_bud_pct', curW, frac(cur.d_bud_pct)) + '. ' + (cur.is_closed ? 'The period is complete, so this is a result, not a pace.' : 'Full-period plan ' + V('fy_periods', 'full_budget', curW, money(cur.full_budget)) + '.'));
    }
    const b2 = tile(V('week_ahead', 'next_fy_wk', null, esc(wa.next_fy_wk)) + ' revenue target', V('week_ahead', 'next_budget_revenue', null, money(wa.next_budget_revenue)),
      'Week ending ' + V('week_ahead', 'next_week_end', null, dateLabel(wa.next_week_end)) + ', with ' + V('week_ahead', 'next_budget_orders', null, num(wa.next_budget_orders)) + ' orders in the plan. The number to hold the week to.');
    const b3 = tile('Week ahead vs this week', V('week_ahead', 'next_vs_tw_pct', null, frac(wa.next_vs_tw_pct)), 'The week-ahead plan against what the week just closed delivered.');
    const b4 = wa.next_week_in_new_month
      ? tile(V('week_ahead', 'next_month_name', null, esc(wa.next_month_name)) + ' plan', V('week_ahead', 'next_month_budget', null, money(wa.next_month_budget)), V('week_ahead', 'next_month_weeks', null, wa.next_month_weeks) + ' weeks. Nothing traded against it yet - this is the period the meeting now opens.')
      : tile(V('week_ahead', 'cur_month_name', null, esc(wa.cur_month_name)) + ' plan still to trade', V('week_ahead', 'cur_month_remaining_budget', null, money(wa.cur_month_remaining_budget)), V('week_ahead', 'cur_weeks_left', null, wa.cur_weeks_left) + ' weeks left in the period.');
    h += '<div class="grid tiles">' + b1 + b2 + b3 + b4 + '</div><p class="note">Targets are the finance ' + plan().toLowerCase() + ' for the 445 period, read weekly. Metric owners speak to their confidence against the week-ahead number.</p>';

    // headline
    const pr = S.product_revenue, nr = S.net_revenue, pm = S.product_margin, pmp = S.product_margin_pct, o = S.orders, aov = S.aov, asp = S.asp, upo = S.units_per_order, a92 = S.a92_base;
    const c = one('cal');
    h += sec('', 'Headline - ' + V('cal', 'fy_wk', null, esc(c.fy_wk)));
    h += '<div class="card"><p class="lede">Revenue <b>' + scText(pr, 'tw') + '</b>, ' + above(pr.d_bud, 'ahead of', 'behind') + ' ' + plan().toLowerCase() + ' by ' + V('scorecard', 'd_bud_pct', scW('product_revenue'), Math.abs(pr.d_bud_pct * 100).toFixed(1) + '%') + ' (' + scText(pr, 'bud') + ' plan) and ' + scText(pr, 'd_ly_pct') + ' on LY; net revenue ' + scText(nr, 'tw') + ' (' + scText(nr, 'd_ly_pct') + ' on LY).</p>';
    h += '<p class="lede">Product margin <b>' + scText(pmp, 'tw') + '</b>, ' + scText(pmp, 'd_bud') + ' vs plan and ' + scText(pmp, 'd_l13w') + ' on the 12-week average, worth ' + scText(pm, 'tw') + ' (' + scText(pm, 'd_bud') + ' vs plan).</p>';
    h += '<p class="lede">Orders <b>' + scText(o, 'tw') + '</b> (' + scText(o, 'd_bud_pct') + ' vs plan, ' + scText(o, 'd_ly_pct') + ' on LY) at ' + scText(aov, 'tw') + ' AOV (' + scText(aov, 'd_ly_pct') + ' on LY): ASP ' + scText(asp, 'd_ly_pct') + ' and units per order ' + scText(upo, 'd_ly_pct') + ' on LY. The active-92 base moved ' + V('scorecard', 'd_lw', scW('a92_base'), snum(a92.d_lw)) + ' to ' + scText(a92, 'tw') + '.</p></div>';

    // largest movements vs plan
    const withBud = ['product_revenue', 'product_margin', 'product_margin_pct', 'asp', 'units_per_order', 'aov', 'orders', 'units'].map((m) => S[m]).filter((r) => r && isN(r.d_bud_pct));
    if (withBud.length) {
      const hi = withBud.reduce((a, b) => (b.d_bud_pct > a.d_bud_pct ? b : a)), lo = withBud.reduce((a, b) => (b.d_bud_pct < a.d_bud_pct ? b : a));
      h += sec('', 'Largest movements vs ' + plan().toLowerCase());
      h += '<div class="grid">' + tile('Furthest above plan', esc(hi.label) + ' ' + scText(hi, 'tw'), scText(hi, 'd_bud') + ' vs plan (' + scText(hi, 'd_bud_pct') + ').') + tile('Furthest below plan', esc(lo.label) + ' ' + scText(lo, 'tw'), scText(lo, 'd_bud') + ' vs plan (' + scText(lo, 'd_bud_pct') + ').') + '</div>';
    }

    // strategic levers
    h += sec('', 'Strategic levers');
    if (ok('levers')) {
      h += '<div class="grid tiles">' + rows('levers').map((r) => { const wl = { lever: r.lever }; return tile(esc(r.lever), V('levers', 'tw', wl, pct(r.tw)), V('levers', 'num', wl, num(r.num)) + ' of ' + V('levers', 'den', wl, num(r.den)) + ' ' + esc(r.den_label || 'orders'), pill('vs 4wk', V('levers', 'd_avg4_bps', wl, bpsRaw(r.d_avg4_bps)), cls(r.d_avg4_bps)) + pill('vs 12wk', V('levers', 'd_avg12_bps', wl, bpsRaw(r.d_avg12_bps)), cls(r.d_avg12_bps))); }).join('') + '</div>';
      h += '<p class="note">Read against the averages of the 4 and 12 weeks before this one rather than last week alone: a penetration rate moves enough week to week that a single-week step is rarely the signal.</p>';
    } else h += state('levers');

    // snapshot
    h += sec('', 'Business snapshot - one figure per tab');
    const co = one('cust_overview'), nc = rows('cust_wbr').find((r) => r.block === 'new' && r.metric === 'New customers'), adL = rows('levers')[0], adEnd = rows('ad_move').find((r) => r.sort === 7);
    let sn = '';
    sn += tile('Commercial · revenue vs plan', scText(pr, 'tw'), '', pill('vs ' + planS(), scText(pr, 'd_bud_pct'), cls(pr.d_bud_pct)));
    sn += tile('Commercial · product margin %', scText(pmp, 'tw'), '', pill('vs ' + planS(), scText(pmp, 'd_bud'), cls(pmp.d_bud)));
    if (co) sn += tile('Customer · active-92 base', V('cust_overview', 'a92_base', null, num(co.a92_base)), '', pill('net this week', V('cust_overview', 'net_change', null, snum(co.net_change)), cls(co.net_change)));
    if (nc) sn += tile('Customer · new customers', V('cust_wbr', 'tw', { block: 'new', metric: 'New customers' }, num(nc.tw)), '', pill('vs target', V('cust_wbr', 'd_target', { block: 'new', metric: 'New customers' }, frac(nc.d_target)), cls(nc.d_target)));
    if (adL) sn += tile('Auto Delivery · share of orders', V('levers', 'tw', { lever: adL.lever }, pct(adL.tw)), '', pill('vs 4wk', V('levers', 'd_avg4_bps', { lever: adL.lever }, bpsRaw(adL.d_avg4_bps)), cls(adL.d_avg4_bps)));
    if (adEnd) sn += tile('Auto Delivery · live AD customers', V('ad_move', 'tw', { metric: adEnd.metric }, num(adEnd.tw)), '', pill('vs LW', V('ad_move', 'd_lw', { metric: adEnd.metric }, frac(adEnd.d_lw)), cls(adEnd.d_lw)));
    const cbT = rows('cat_books').find((r) => r.book === 'Total'), ih = one('inv_health');
    if (cbT) sn += tile('Category · revenue vs LY', V('cat_books', 'revenue', { book: 'Total' }, money(cbT.revenue)), '', pill('vs LY', V('cat_books', 'rev_vs_ly_pct', { book: 'Total' }, frac(cbT.rev_vs_ly_pct)), cls(cbT.rev_vs_ly_pct)));
    if (ih) sn += tile('Inventory · SLOB of stock', V('inv_health', 'slob_pct', null, pct(ih.slob_pct * 100, 1)), 'against a ' + V('inv_health', 'slob_guardrail_pct', null, pct(ih.slob_guardrail_pct * 100, 0)) + ' guardrail', '<span class="pill ' + (ih.slob_pct > ih.slob_guardrail_pct ? 'neg' : 'pos') + '">' + (ih.slob_pct > ih.slob_guardrail_pct ? 'above guardrail' : 'within guardrail') + '</span>');
    const mh = one('mf_headline');
    if (mh) sn += tile('Media & Funnel · conversion', V('mf_headline', 'cvr', null, pct(mh.cvr, 2)), '', pill('vs 12wk', V('mf_headline', 'cvr_vs_l12w_pp', null, pp(mh.cvr_vs_l12w_pp, 2)), cls(mh.cvr_vs_l12w_pp)));
    const nps = one('cx_nps');
    if (nps) sn += tile('CX · NPS, 13 weeks', V('cx_nps', 'nps', null, num(nps.nps, 1)), 'on ' + V('cx_nps', 'responses', null, num(nps.responses, 0)) + ' responses; last 4 weeks ' + V('cx_nps', 'last4_nps', null, num(nps.last4_nps, 1)), pill('vs target ' + V('cx_nps', 'target', null, num(nps.target, 0)), V('cx_nps', 'nps_vs_target', null, snum(nps.nps_vs_target, 1)), cls(nps.nps_vs_target)));
    else sn += '<div class="card tile">' + state('cx_nps') + '</div>';
    const om = one('ops_meta'), dl = ok('ops_difot') ? rows('ops_difot').filter((r) => r.fc === 'ALL' && r.is_latest) : [];
    const ndd = dl.find((r) => r.order_type === 'NDD');
    if (ndd && om) {
      const dw = (r) => ({ fc: 'ALL', order_type: r.order_type, week_start: r.week_start });
      const held = om.held || (one('cal') && om.week_end !== one('cal').week_end);
      sn += tile('Operations · Next Day DIFOT', V('ops_difot', 'difot_pct', dw(ndd), pct(ndd.difot_pct, 2)), dl.filter((r) => r.order_type !== 'NDD').map((r) => esc(r.order_type_name) + ' ' + V('ops_difot', 'difot_pct', dw(r), pct(r.difot_pct, 1))).join(', ') + (held ? '; week of ' + V('ops_meta', 'ops_week_label', null, esc(om.ops_week_label)) + ' (held)' : ''), pill('vs ' + ndd.target_pct + '% target', V('ops_difot', 'vs_target_pp', dw(ndd), pp(ndd.vs_target_pp, 2)), cls(ndd.vs_target_pp)));
    } else sn += '<div class="card tile">' + state(['ops_meta', 'ops_difot']) + '</div>';
    h += '<div class="grid tiles">' + sn + '</div>';

    // working / watch across the business
    const mv = planMovers(['product_revenue', 'product_margin', 'product_margin_pct', 'aov', 'orders']);
    if (co && ok('a92_flow')) { const f = rows('a92_flow').slice(-1)[0]; const s = '<b>Active-92 base ' + V('cust_overview', 'a92_base', null, num(co.a92_base)) + '</b>, net ' + V('cust_overview', 'net_change', null, snum(co.net_change)) + ' this week against a 13-week average of ' + V('a92_flow', 'avg_net_13w', { week_end: f.week_end }, snum(f.avg_net_13w, 0)) + '.'; (co.net_change >= f.avg_net_13w ? mv.good : mv.watch).push(s); }
    if (nc) { const s = '<b>New customers ' + V('cust_wbr', 'tw', { block: 'new', metric: 'New customers' }, num(nc.tw)) + '</b>, ' + V('cust_wbr', 'd_target', { block: 'new', metric: 'New customers' }, frac(nc.d_target)) + ' vs target.'; (nc.d_target >= 0 ? mv.good : mv.watch).push(s); }
    if (adEnd) { const s = '<b>Live Auto Delivery customers ' + V('ad_move', 'tw', { metric: adEnd.metric }, num(adEnd.tw)) + '</b>, ' + V('ad_move', 'd_lw', { metric: adEnd.metric }, frac(adEnd.d_lw)) + ' on last week.'; (adEnd.d_lw >= 0 ? mv.good : mv.watch).push(s); }
    h += sec('', 'Key highlights');
    h += hlBoxes(mv.good.slice(0, 5), mv.watch.slice(0, 5), 'Every line is chosen and worded by the sign of its own number against plan, target or trend, so a week that turns down reads as turning down. Nothing here is hand-written or carried forward.');

    // actions
    h += sec('', 'Discuss and agree actions · 5 min');
    h += ph('Actions carried out of the meeting', 'The last agenda item, and the one the success criteria turn on: attendees leave with the actions and focus areas for the coming week.', ['Actions raised this week, each with an owner, a date and the metric it is meant to move.', 'Last week’s actions with their status, so the meeting opens on what was closed.', 'Metrics off track where the owner has recorded a diagnosis and a path to resolution.', 'A short focus line per function for the week ahead.'], 'Decide whether actions live on this dashboard (it can hold a shared, editable list) or in the existing meeting notes.');
    return h;
  }

  // ================= COMMERCIAL =================
  const SPARK = { product_revenue: 'product_revenue', net_revenue: 'net_revenue', product_margin: 'product_margin', product_margin_pct: 'product_margin_pct', asp: 'asp', units_per_order: 'units_per_order', aov: 'aov', orders: 'orders' };
  function scTile(r) {
    const isPct = r.metric === 'product_margin_pct';
    const dl = (f) => (isPct ? bps(r[f]) : dU(r.unit, r[f]));
    const p = pill('WoW', V('scorecard', 'd_lw', scW(r.metric), dl('d_lw')), cls(r.d_lw)) + pill('vs 12wk', V('scorecard', 'd_l13w', scW(r.metric), dl('d_l13w')), cls(r.d_l13w)) + pill('LY', V('scorecard', 'd_ly', scW(r.metric), dl('d_ly')), cls(r.d_ly)) + (isN(r.d_bud) ? pill(planS(), V('scorecard', 'd_bud', scW(r.metric), dl('d_bud')), cls(r.d_bud)) : '<span class="pill flat">' + planS() + ' n/a</span>');
    return '<div class="card tile"><div class="lab">' + esc(r.label) + '</div><div class="big">' + scText(r, 'tw') + '</div><div class="pills">' + p + '</div><div class="spark" data-spark="' + SPARK[r.metric] + '" data-source="scorecard_weekly"></div></div>';
  }
  const mixCols = (kind) => kind === 'orders'
    ? [{ f: 'value', h: '' }, { f: 'orders_tw', h: 'Orders', v: (r) => num(r.orders_tw) }, { f: 'orders_pct_lw', h: 'vs LW', v: (r) => frac(r.orders_pct_lw), c: (r) => cls(r.orders_pct_lw) }, { f: 'orders_pct_l13w', h: 'vs 12wk', v: (r) => frac(r.orders_pct_l13w), c: (r) => cls(r.orders_pct_l13w) }, { f: 'share_tw', h: 'Share', v: (r) => pct(r.share_tw) }, { f: 'share_pp_lw', h: 'Share vs LW', v: (r) => (r.value === 'Total' ? '' : pp(r.share_pp_lw)), c: () => 'flat' }, { f: 'share_pp_l13w', h: 'vs 12wk', v: (r) => (r.value === 'Total' ? '' : pp(r.share_pp_l13w)), c: () => 'flat' }]
    : [{ f: 'value', h: '' }, { f: 'aov_tw', h: 'AOV', v: (r) => money(r.aov_tw) }, { f: 'aov_pct_lw', h: 'vs LW', v: (r) => frac(r.aov_pct_lw), c: (r) => cls(r.aov_pct_lw) }, { f: 'aov_pct_l13w', h: 'vs 12wk', v: (r) => frac(r.aov_pct_l13w), c: (r) => cls(r.aov_pct_l13w) }, { f: 'rev_share_tw', h: 'Rev share', v: (r) => pct(r.rev_share_tw) }, { f: 'rev_share_pp_lw', h: 'Share vs LW', v: (r) => (r.value === 'Total' ? '' : pp(r.rev_share_pp_lw)), c: () => 'flat' }, { f: 'rev_share_pp_l13w', h: 'vs 12wk', v: (r) => (r.value === 'Total' ? '' : pp(r.rev_share_pp_l13w)), c: () => 'flat' }];
  const mixT = (cut, kind) => tbl('orders_mix', 'cut,value', mixCols(kind), rows('orders_mix').filter((r) => r.cut === cut), { rowCls: (r) => (r.value === 'Total' ? 'tot' : '') });
  function heat(field, fmt, changeField, changeFmt) {
    if (!ok('channel_trend')) return state('channel_trend');
    const R = rows('channel_trend');
    const weeks = [...new Set(R.map((r) => r.week_end))].sort();
    const chans = ['Website', 'Mobile App', 'AD Scheduled', 'CX'].filter((c) => R.some((r) => r.channel === c));
    let h = '<div class="tw" data-source="channel_trend"><table class="t"><thead><tr><th>Channel</th>' + weeks.map((w) => '<th>' + esc(R.find((r) => r.week_end === w).wk_label) + '</th>').join('') + '<th>13-wk change</th></tr></thead><tbody>';
    for (const ch of chans) {
      const cr = weeks.map((w) => R.find((r) => r.week_end === w && r.channel === ch));
      const vals = cr.map((r) => (r ? +r[field] : NaN)).filter((x) => !isNaN(x));
      const lo = Math.min(...vals), hi = Math.max(...vals);
      h += '<tr><td>' + esc(ch) + '</td>' + cr.map((r) => { if (!r) return '<td></td>'; const t = hi > lo ? (r[field] - lo) / (hi - lo) : 0.5; return '<td style="background:color-mix(in srgb, var(--pc-teal) ' + Math.round(6 + t * 30) + '%, transparent)">' + fmt(r[field]) + '</td>'; }).join('') + '<td class="' + cls(cr[cr.length - 1]?.[changeField]) + '">' + changeFmt(cr[cr.length - 1]?.[changeField]) + '</td></tr>';
    }
    return h + '</tbody></table></div>';
  }
  function rCommercial() {
    const t = T.commercial;
    let h = ptitle(t);
    if (!ready(['scorecard', 'cal'])) return h + state(['scorecard', 'cal']);
    const S = SC();
    const mv = planMovers(['product_revenue', 'product_margin', 'product_margin_pct', 'asp', 'units_per_order', 'aov', 'orders', 'units']);
    const cur = rows('fy_periods').find((r) => r.kind === 'current');
    if (cur) { const s = '<b>' + esc(cur.period) + ' ' + (cur.is_closed ? 'closed' : 'to date') + '</b> ' + V('fy_periods', 'd_bud_pct', { period: cur.period }, frac(cur.d_bud_pct)) + ' vs plan on the weeks traded.'; (cur.d_bud >= 0 ? mv.good : mv.watch).push(s); }
    h += hlBoxes(mv.good.slice(0, 4), mv.watch.slice(0, 4));
    h += sec('1', 'Commercial scorecard');
    for (const g of ['Revenue', 'Margin', 'Revenue drivers']) {
      const list = ['product_revenue', 'net_revenue', 'product_margin', 'product_margin_pct', 'asp', 'units_per_order', 'aov', 'orders'].map((m) => S[m]).filter((r) => r && r.grp === g);
      h += '<p class="pc-sub" style="margin:10px 0 6px;text-transform:uppercase;letter-spacing:.06em">' + g + '</p><div class="grid tiles">' + list.map(scTile).join('') + '</div>';
    }
    h += '<p class="note">WoW = last week. vs 12wk = the average of the 12 weeks before this one. LY = the same 445 week last year. ' + planS() + ' = the finance ' + plan().toLowerCase() + ' for the week. Product margin % moves in basis points. Sparkline = the last 13 weeks with the 13-week mean dashed. Revenue = AOV x orders; AOV = ASP x units per order (units are multipack-unwound). Net revenue = revenue less discounts, coupons and credits plus shipping, on completed orders.</p>';

    // driver tree
    h += sec('2', 'Revenue driver tree - actual vs ' + plan().toLowerCase());
    const vd = Object.fromEntries(rows('value_drivers').map((r) => [r.metric, r])), co = one('cust_overview');
    const node = (lab, val, b) => '<div class="node"><div class="lab">' + lab + '</div><div class="v">' + val + '</div><div class="b">' + b + '</div></div>';
    const bnode = (m, lab) => node(lab || S[m].label, scText(S[m], 'tw'), isN(S[m].bud) ? planS() + ' ' + scText(S[m], 'bud') + ' · ' + scText(S[m], 'd_bud') : planS() + ' n/a');
    const op = (x) => '<span class="op">' + x + '</span>';
    let tr = '<div class="card"><div class="eq">' + bnode('product_revenue') + op('=') + bnode('aov') + op('×') + bnode('orders') + '</div></div>';
    tr += '<div class="card"><div class="eq">' + bnode('aov') + op('=') + bnode('asp') + op('×') + bnode('units_per_order') + '</div></div>';
    if (vd.orders_per_customer) tr += '<div class="card"><div class="eq">' + bnode('orders') + op('=') + bnode('purchasing_customers') + op('×') + node('Orders / customer', V('value_drivers', 'tw', { metric: 'orders_per_customer' }, num(vd.orders_per_customer.tw, 2)), 'no weekly plan') + '</div></div>';
    if (co) tr += '<div class="card"><div class="eq">' + bnode('purchasing_customers') + op('=') + bnode('a92_base') + op('×') + node('% of A92 purchasing', V('cust_overview', 'purchase_rate', null, pct(co.purchase_rate, 2)), 'no weekly plan') + '</div></div>';
    h += '<div class="tree">' + tr + '</div><p class="note">Multiplicative decomposition. The finance plan sets revenue, margin, orders and units weekly; purchasing customers and the A92 base have no weekly plan in the warehouse.</p>';

    const shade = (v) => { const k = cls(v); return k === 'pos' || k === 'neg' ? k + ' bgv bg-' + k : k; };
    // month table
    const c = one('cal');
    h += sec('3', 'Revenue - ' + esc(c.month_name) + ' vs ' + plan().toLowerCase());
    if (ok('fy_weeks')) {
      const wk = rows('fy_weeks').filter((r) => r.in_current_month).sort((a, b) => a.wk - b.wk);
      const mcols = [{ f: 'fy_wk', h: 'Week' }, { f: 'week_end', h: 'Week ending', v: (r) => dateLabel(r.week_end) }, { f: 'actual', h: 'Actual', v: (r) => (r.is_actual ? money(r.actual) : 'not traded') }, { f: 'budget', h: plan(), v: (r) => money(r.budget) }, { f: 'd_bud', h: 'vs plan $', v: (r) => (r.is_actual ? smoney(r.d_bud) : ''), c: (r) => (r.is_actual ? shade(r.d_bud) : '') }, { f: 'd_bud_pct', h: 'vs plan %', v: (r) => (r.is_actual ? frac(r.d_bud_pct) : ''), c: (r) => (r.is_actual ? shade(r.d_bud_pct) : '') }];
      let mt = tbl('fy_weeks', 'wk', mcols, wk);
      if (cur) {
        const w = { period: cur.period }, pv = (f, t) => V('fy_periods', f, w, t);
        const mtd = '<tr class="tot" data-key="mtd"><td>Month to date</td><td>' + pv('weeks_traded', cur.is_closed ? 'period complete' : cur.weeks_traded + ' of ' + cur.weeks_total + ' weeks traded') + '</td><td>' + pv('actual', money(cur.actual)) + '</td><td>' + pv('budget', money(cur.budget)) + (cur.is_closed ? '' : '<span class="sm">full month ' + pv('full_budget', money(cur.full_budget)) + '</span>') + '</td><td class="' + shade(cur.d_bud) + '">' + pv('d_bud', smoney(cur.d_bud)) + '</td><td class="' + shade(cur.d_bud_pct) + '">' + pv('d_bud_pct', frac(cur.d_bud_pct)) + '</td></tr>';
        mt = mt.replace(/<\/tbody><\/table><\/div>$/, mtd + '</tbody></table></div>');
      }
      h += card('', 'Completed weeks show actuals against plan. A week not yet traded shows its plan only - nothing on this table is projected. The month-to-date line compares actuals with the plan for the weeks traded so far, so it is a result rather than a pace. While a month is in progress, the full-month plan sits under its plan figure.', mt);
    } else h += state('fy_weeks');

    // months & YTD
    h += sec('4', 'Completed months and FY to date');
    const per = rows('fy_periods').filter((r) => r.kind !== 'current');
    h += '<div class="grid wide">' + card('Months and YTD vs ' + plan().toLowerCase(), '', tbl('fy_periods', 'period', [{ f: 'period', h: 'Period' }, { f: 'weeks_traded', h: 'Weeks' }, { f: 'actual', h: 'Actual', v: (r) => money(r.actual) }, { f: 'budget', h: plan(), v: (r) => money(r.budget) }, { f: 'd_bud', h: 'vs plan $', v: (r) => smoney(r.d_bud), c: (r) => shade(r.d_bud) }, { f: 'd_bud_pct', h: 'vs plan %', v: (r) => frac(r.d_bud_pct), c: (r) => shade(r.d_bud_pct) }], per, { rowCls: (r) => (r.kind === 'ytd' ? 'tot' : '') }))
      + card('Weekly revenue vs ' + plan().toLowerCase() + ', FY to date', 'Bars are actual product revenue; the tick on each is that week’s plan. Hover for the figures.', '<div class="legend"><span><i style="background:' + PCC[0] + '"></i>Actual</span><span><i style="background:var(--cds-chart-reference)"></i>' + plan() + '</span></div><div class="chart" id="ch-fyweeks" data-source="fy_weeks"></div>') + '</div>';

    // orders composition
    h += sec('5', 'Orders - composition this week');
    h += '<div class="grid wide">' + card('Orders by channel', '', mixT('channel', 'orders')) + card('Orders by customer status', 'New = first-ever completed order; Reactivated = no prior order on record or a gap of 92 days or more; Returning = otherwise.', mixT('status', 'orders')) + card('Orders by delivery state', 'State is the delivery address state; orders with no delivery record sit under UNKNOWN.', mixT('state', 'orders')) + '</div>';
    h += card('Order share trend - last 13 weeks', 'Share of each week’s orders by channel. Shading is scaled within each row, so each channel’s own trajectory reads across; the last column is the change from 13 weeks ago in percentage points.', heat('share', (v) => pct(v), 'share_change_13w_pp', (v) => pp(v)));

    // AOV composition
    h += sec('6', 'AOV - composition this week');
    h += '<div class="grid wide">' + card('AOV by channel', '', mixT('channel', 'aov')) + card('AOV by customer status', '', mixT('status', 'aov')) + card('AOV by delivery state', '', mixT('state', 'aov')) + '</div>';
    h += card('AOV trend - last 13 weeks', 'Product revenue per order by channel. The last column is the change in dollars over the 13 weeks.', heat('aov', (v) => '$' + Math.round(v), 'aov_change_13w', (v) => smoney(v)));
    h += '<p class="note">AOV = product revenue excl GST divided by orders, on the scorecard’s order universe (status not Cancelled). Rev share is each cut’s share of the week’s product revenue, so it moves with both AOV and mix.</p>';

    // interactive metric explorer (explorer.js)
    h += sec('7', 'Interactive metric explorer');
    h += '<p class="note">Pick a metric, a comparison and one split to see what drove the move. Revenue, margin and orders draw as a waterfall that adds up to the total change; purchasing customers and AOV show each segment\u2019s own change.</p>';
    h += window.pcExplorer ? window.pcExplorer.html() : '<div class="fail">Explorer failed to load</div>';
    return h;
  }

  // ================= WBR-style comparison table =================
  function wbr(ds, data, key, withTarget = true) {
    const dcell = (r, d, lvl) => {
      if (r.source === 'tracker') return '';
      if (!isN(d)) return '<span class="flat">' + NA + '</span>';
      const t = r.unit === 'pct' ? pp(d) : frac(d);
      return '<span class="' + cls(d, !r.inverted) + '">' + (r.sign === '-' ? '' : '') + t + '</span>' + (isN(lvl) ? '<span class="sm">' + fmtU(r.unit, lvl) + '</span>' : '');
    };
    const cols = [{ f: 'metric', h: 'Metric', v: (r) => esc(r.metric) + (r.sub ? '<span class="desc">' + esc(r.sub) + '</span>' : '') }, { f: 'tw', h: 'This week', v: (r) => (r.source === 'tracker' ? '<span class="flat">awaiting Tracker</span>' : fmtU(r.unit, r.tw) + (isN(r.tw_n) ? '<span class="sm">' + num(r.tw_n) + '</span>' : '')) }];
    if (withTarget) cols.push({ f: 'd_target', h: 'vs target', v: (r) => (isN(r.target) || r.source === 'tracker' ? dcell(r, r.d_target, r.target) : '<span class="flat">-</span>') });
    cols.push({ f: 'd_lw', h: 'vs last week', v: (r) => dcell(r, r.d_lw, r.lw) }, { f: 'd_avg4', h: 'vs 4wk ave', v: (r) => dcell(r, r.d_avg4, r.avg4) }, { f: 'd_avg12', h: 'vs 12wk ave', v: (r) => dcell(r, r.d_avg12, r.avg12) }, { f: 'd_ly', h: 'vs YA', v: (r) => dcell(r, r.d_ly, r.ly) });
    return tbl(ds, key, cols, data, { rowCls: (r) => (r.child ? 'child' : '') });
  }

  // ================= CUSTOMER =================
  const openBuckets = new Set();
  function rCustomer() {
    const t = T.customer;
    let h = ptitle(t);
    const need = ['cust_overview', 'cust_wbr'];
    if (!ready(need)) return h + state(need);
    const co = one('cust_overview'), W = rows('cust_wbr');
    // highlights from the WBR tables vs 12-week average
    const good = [], watch = [];
    for (const r of W.filter((x) => !x.child && x.source !== 'tracker' && isN(x.d_avg12) && x.block !== 'new' && !(x.block === 'health' && x.metric === 'New customers'))) {
      const s = '<b>' + esc(r.metric) + ' ' + V('cust_wbr', 'tw', { block: r.block, metric: r.metric }, fmtU(r.unit, r.tw)) + '</b>, ' + V('cust_wbr', 'd_avg12', { block: r.block, metric: r.metric }, r.unit === 'pct' ? pp(r.d_avg12) : frac(r.d_avg12)) + ' vs the 12-week average.';
      ((r.d_avg12 >= 0) !== !!r.inverted ? good : watch).push([Math.abs(r.d_avg12), s]);
    }
    const nr = W.find((r) => r.block === 'new' && r.metric === 'New customers');
    if (nr) (nr.d_target >= 0 ? good : watch).push([9, '<b>New customers ' + V('cust_wbr', 'tw', { block: 'new', metric: nr.metric }, num(nr.tw)) + '</b>, ' + V('cust_wbr', 'd_target', { block: 'new', metric: nr.metric }, frac(nr.d_target)) + ' vs target.']);
    (co.net_change >= 0 ? good : watch).push([8, '<b>Active-92 base ' + V('cust_overview', 'a92_base', null, num(co.a92_base)) + '</b>, net ' + V('cust_overview', 'net_change', null, snum(co.net_change)) + ': ' + V('cust_overview', 'lapsed', null, num(co.lapsed)) + ' lapsed against ' + V('cust_overview', 'new_customers', null, num(co.new_customers)) + ' new and ' + V('cust_overview', 'reactivated', null, num(co.reactivated)) + ' reactivated.']);
    const top = (a) => a.sort((x, y) => y[0] - x[0]).slice(0, 4).map((x) => x[1]);
    h += hlBoxes(top(good), top(watch));

    // overview
    h += sec('', 'Customer overview - file to locked-in value');
    const cv = (f, fmt) => V('cust_overview', f, null, fmt(co[f]));
    h += '<div class="grid tiles">' + tile('Customer file', cv('rfm_file', num), 'every customer on the RFM base') + tile('Active 92-day base', cv('a92_base', num), 'bought in the last 92 days') + tile('Purchased this week', cv('purchased', num), cv('purchase_rate', (v) => pct(v)) + ' of the base, ' + cv('rev_per_customer', money) + ' revenue each') + tile('Bought food', cv('food_buyer_share', pct), 'share of this week’s purchasing customers') + tile('On Auto Delivery', cv('ad_customer_share', pct), 'share of this week’s purchasing customers') + tile('Super users', cv('super_user_share', pct), 'food, Auto Delivery and app, all three: ' + cv('super_user_rev_share', pct) + ' of revenue') + '</div>';
    h += '<div class="grid tiles" style="margin-top:var(--cds-gap-md)">' + tile('New this week', cv('new_customers', num), 'first-ever order') + tile('Reactivated', cv('reactivated', num), 'returned to the 92-day base') + tile('Lapsed', cv('lapsed', num), 'passed 92 days without an order') + tile('Net movement in the base', '<span class="' + cls(co.net_change) + '">' + cv('net_change', snum) + '</span>', cv('a92_opening', num) + ' to ' + cv('a92_base', num)) + '</div>';

    // 1 new customers
    h += sec('1', 'New customer shape');
    h += card('', 'The Marketing WBR comparison set. Both averages exclude this week. Acquisition spend, payback and performance CPA live in the Marketing Performance Tracker, outside the warehouse, so they show as awaiting that extract rather than estimated.', wbr('cust_wbr', W.filter((r) => r.block === 'new'), 'block,metric'));
    h += '<div class="grid wide" style="margin-top:var(--cds-gap-md)">' + card('New customers by acquisition channel', 'Acquisition channel is the channel of the session that placed the customer’s first order (Pet Circle website and app, first-touch of the converting visit). First orders with no tracked session, such as phone orders, show as Unattributed. Rows sum to the total.', tbl('new_by_channel', 'channel', [{ f: 'channel', h: 'Acquisition channel' }, { f: 'new_tw', h: 'New', v: (r) => num(r.new_tw) }, { f: 'pct_lw', h: 'vs LW', v: (r) => frac(r.pct_lw), c: (r) => cls(r.pct_lw) }, { f: 'pct_l13w', h: 'vs 12wk', v: (r) => frac(r.pct_l13w), c: (r) => cls(r.pct_l13w) }, { f: 'share', h: 'Share', v: (r) => pct(r.share) }, { f: 'share_pp_lw', h: 'Share vs LW', v: (r) => (r.channel === 'Total' ? '' : pp(r.share_pp_lw)), c: () => 'flat' }], rows('new_by_channel'), { rowCls: (r) => (r.channel === 'Total' ? 'tot' : '') }))
      + card('New customers by category - reach of the first basket', 'A new customer counts in every group their first basket touched, so rows do not sum to the total: read as reach, not composition.', tbl('new_by_category', 'category', [{ f: 'category', h: 'Category group' }, { f: 'new_tw', h: 'New', v: (r) => num(r.new_tw) }, { f: 'pct_lw', h: 'vs LW', v: (r) => frac(r.pct_lw), c: (r) => cls(r.pct_lw) }].concat(rows('new_by_category').some((r) => isN(r.pct_l4w)) ? [{ f: 'pct_l4w', h: 'vs 4wk avg', v: (r) => frac(r.pct_l4w) + '<span class="sm">avg ' + num(r.new_avg4, 0) + '</span>', c: (r) => cls(r.pct_l4w) }] : []).concat([{ f: 'pct_l13w', h: 'vs 12wk', v: (r) => frac(r.pct_l13w), c: (r) => cls(r.pct_l13w) }]), rows('new_by_category'))) + '</div>';

    // 2 health
    h += sec('2', 'Active base and customer health');
    h += card('Customers active in the week', 'A weekly purchaser count, not the 92-day base in section 4 - the two answer different questions and will not tie. New + reactivations + existing = total active. The order-type rows overlap (a customer can place more than one type), so they do not sum.', wbr('cust_wbr', W.filter((r) => r.block === 'health'), 'block,metric'));
    h += '<div style="height:var(--cds-gap-md)"></div>' + card('Value and behaviour segments', 'Customers who bought this week, cut by the behaviours that carry value. High value = the four RFM segments in the High Value bucket. The segments overlap by design, so they are not additive.', wbr('cust_wbr', W.filter((r) => r.block === 'features'), 'block,metric', false));

    // 3 value drivers
    h += sec('3', 'What drives value inside the base');
    if (ok('value_drivers')) h += '<div class="grid tiles">' + rows('value_drivers').map((r) => { const wm = { metric: r.metric }; const dl = (f) => (r.unit === 'pct' ? pp(r[f]) : r.unit === '$' ? smoney(r[f]) : snum(r[f], Math.abs(r.tw) < 100 ? 2 : undefined)); return tile(esc(r.label), V('value_drivers', 'tw', wm, r.unit === 'n' && Math.abs(r.tw) < 100 ? num(r.tw, 2) : fmtU(r.unit, r.tw)), '', pill('WoW', V('value_drivers', 'd_lw', wm, dl('d_lw')), cls(r.d_lw)) + pill('vs 12wk', V('value_drivers', 'd_l13w', wm, dl('d_l13w')), cls(r.d_l13w))); }).join('') + '</div>';
    else h += state('value_drivers');
    const two = (ds, a, b, ha, hb) => tbl(ds, 'metric', [{ f: 'label', h: 'Metric' }, { f: a, h: ha, v: (r) => (r.unit === 'n' ? num(r[a], 2) : fmtU(r.unit, r[a])) }, { f: b, h: hb, v: (r) => (r.unit === 'n' ? num(r[b], 2) : fmtU(r.unit, r[b])) }], rows(ds));
    h += '<div class="grid wide" style="margin-top:var(--cds-gap-md)">' + card('Food vs non-food orders', 'An order counts as food when it holds at least one food line.', two('food_vs_nonfood', 'food', 'nonfood', 'Food', 'Non-food'))
      + card('Cross-sell - categories in food baskets', 'Share of food orders that also hold each category group (excluding the food lines themselves).', tbl('food_crosssell', 'category', [{ f: 'category', h: 'Category also in basket' }, { f: 'pct_of_food_orders', h: '% of food orders', v: (r) => pct(r.pct_of_food_orders) }], rows('food_crosssell')))
      + card('App vs website orders', 'Mobile App against Website order origin.', two('app_vs_web', 'app', 'web', 'App', 'Website')) + '</div>';
    const su = one('super_users');
    if (su) { const sv = (f, fmt) => V('super_users', f, null, fmt(su[f])); h += '<div class="grid tiles" style="margin-top:var(--cds-gap-md)">' + tile('Super users', sv('super_users', num), 'shopped food, on Auto Delivery and via the app this week') + tile('Share of customers', sv('share_customers', pct), '', pill('WoW', sv('share_customers_pp_lw', pp), cls(su.share_customers_pp_lw)) + pill('vs 12wk', sv('share_customers_pp_l13w', pp), cls(su.share_customers_pp_l13w))) + tile('Share of revenue', sv('share_revenue', pct), '', pill('WoW', sv('share_revenue_pp_lw', pp), cls(su.share_revenue_pp_lw)) + pill('vs 12wk', sv('share_revenue_pp_l13w', pp), cls(su.share_revenue_pp_l13w))) + tile('Value index', sv('value_index', (v) => (+v).toFixed(2) + 'x'), sv('rev_per_super', money) + ' per super user against ' + sv('rev_per_customer', money) + ' per customer') + '</div>'; }

    // 4 A92
    h += sec('4', 'The 92-day active base');
    h += '<p class="lede">' + V('cust_overview', 'purchase_rate', null, pct(co.purchase_rate, 2)) + ' of the A92 base purchased this week - ' + V('cust_overview', 'purchased', null, num(co.purchased)) + ' customers of ' + V('cust_overview', 'a92_base', null, num(co.a92_base)) + '.</p>';
    h += '<div class="grid wide">' + card('Net weekly change to the A92 base - last 13 weeks', 'Each bar is the week’s net change (new + reactivated - lapsed). The dashed line is the 13-week average. Hover for the flows.', '<div class="chart" id="ch-a92" data-source="a92_flow"></div>')
      + card('A92 base by tenure', 'Time since first order at the reporting Sunday.', tbl('tenure', 'bucket', [{ f: 'bucket', h: 'Tenure' }, { f: 'customers', h: 'Customers', v: (r) => num(r.customers) }, { f: 'share', h: 'Share', v: (r) => pct(r.share) }, { f: 'ad_pct', h: 'On AD', v: (r) => pct(r.ad_pct) }], rows('tenure'), { rowCls: (r) => (r.bucket === 'Total' ? 'tot' : '') }) + '<p class="note">Lifetime value by tenure is not yet rebuilt in the warehouse queries - a phase 2 item.</p>') + '</div>';

    // 5 RFM
    h += sec('5', 'Customers by RFM value bucket');
    if (ok('rfm_segments')) {
      const R = rows('rfm_segments');
      const f0 = R[0];
      const rc = [{ f: 'bucket', h: 'Bucket / segment', v: (r) => esc(r.kind === 'segment' ? r.segment : r.kind === 'total' ? 'Total customer file' : r.bucket) }, { f: 'customers', h: 'Customers', v: (r) => num(r.customers) }, { f: 'share_of_file', h: 'Share of file', v: (r) => pct(r.share_of_file) }, { f: 'wow', h: 'WoW', v: (r) => snum(r.wow), c: () => 'flat' }, { f: 'vs_ly', h: 'vs LY', v: (r) => snum(r.vs_ly), c: () => 'flat' }, { f: 'rev_per_cust_12m', h: 'Rev / cust 12m', v: (r) => dollars(r.rev_per_cust_12m) }, { f: 'orders_per_cust_12m', h: 'Orders / cust 12m', v: (r) => num(r.orders_per_cust_12m, 1) }, { f: 'bought_this_wk', h: 'Bought this wk', v: (r) => num(r.bought_this_wk) }, { f: 'penetration', h: 'Penetration', v: (r) => pct(r.penetration) }, { f: 'order_share', h: 'Order share', v: (r) => pct(r.order_share) }, { f: 'rev_share', h: 'Rev share', v: (r) => pct(r.rev_share) }, { f: 'aov', h: 'AOV', v: (r) => money(r.aov) }];
      h += card('RFM value buckets - base, movement and this week’s activity', 'Click a bucket to open its segments. A bucket line is the sum of its segments, with per-customer figures weighted by customers.', tbl('rfm_segments', 'sort', rc, R.filter((r) => !(r.bucket === 'Unmapped' && !(r.customers > 0))), { id: 'rfm-t', rowAttr: (r) => 'data-bucket="' + esc(r.bucket) + '" data-kind="' + esc(r.kind) + '"', rowCls: (r) => (r.kind === 'bucket' ? 'bucket' + (openBuckets.has(r.bucket) ? ' open' : '') : r.kind === 'total' ? 'tot' : 'child'), hide: (r) => r.kind === 'segment' && !openBuckets.has(r.bucket) }));
      h += '<p class="note">The file is every customer on the RFM base at ' + V('rfm_segments', 'file_date', { sort: f0.sort }, dateLabel(f0.file_date)) + ' (the prior Sunday), roughly twice the A92 base, because it includes dormant and lapsed customers. This week’s buying joins to the prior-Sunday segment, so membership is set before the trading week. Revenue and orders per customer are the trailing 365 days. vs LY is a ' + V('rfm_segments', 'ly_basis_days', { sort: f0.sort }, esc(f0.ly_basis_days)) + '-day proxy because snapshot history is retained for about a year.</p>';
    } else h += state('rfm_segments');

    // drill-down
    h += sec('', 'Drill-down - cohort by channel');
    if (ok('cohort_channel')) {
      const R = rows('cohort_channel');
      const cohorts = ['New', 'Reactivated', 'Returning', 'Channel total'].filter((c) => R.some((r) => r.cohort === c));
      const chans = ['Website', 'Mobile App', 'Schedule', 'CX', 'Cohort total'].filter((c) => R.some((r) => r.channel === c));
      let m = '<div class="tw" data-source="cohort_channel"><table class="t"><thead><tr><th>Cohort</th>' + chans.map((c) => '<th>' + esc(c) + '</th>').join('') + '</tr></thead><tbody>';
      for (const co2 of cohorts) m += '<tr' + (co2 === 'Channel total' ? ' class="tot"' : '') + '><td>' + esc(co2) + '</td>' + chans.map((ch) => { const r = R.find((x) => x.cohort === co2 && x.channel === ch); return '<td>' + (r ? money(r.aov) + '<span class="sm">' + num(r.orders) + ' orders</span>' : '') + '</td>'; }).join('') + '</tr>';
      h += card('AOV by customer cohort and channel', 'Each cell shows AOV with the order count beneath. Schedule = Auto Delivery scheduled orders.', m + '</tbody></table></div>');
    } else h += state('cohort_channel');
    return h;
  }

  // ================= AUTO DELIVERY =================
  dash.calc('ad_cohort_direction', {
    inputs: ['ad_cohort'],
    title: 'AD1 cohort direction',
    description: 'Oldest against newest mature AD1 cohort: share reaching AD2 and AD4+, and cohort size.',
    fn: (ad_cohort) => {
      const m = ad_cohort.filter((r) => r.mature === true || r.mature === 'true').sort((a, b) => a.sort - b.sort);
      if (m.length < 2) return [];
      const f = m[0], l = m[m.length - 1];
      return [{ first: f.month_label, last: l.month_label, r2_first: f.r2, r2_last: l.r2, d_r2: Math.round((l.r2 - f.r2) * 10) / 10, r4_first: f.r4, r4_last: l.r4, d_r4: Math.round((l.r4 - f.r4) * 10) / 10, n_first: f.n, n_last: l.n }];
    },
  });
  function rAD() {
    const t = T.autodelivery;
    let h = ptitle(t);
    const need = ['ad_move', 'ad_penetration'];
    if (!ready(need)) return h + state(need);
    const M = rows('ad_move'), P = one('ad_penetration');
    const good = [], watch = [];
    for (const r of M.filter((x) => isN(x.d_avg12) && x.sort !== 1)) {
      const s = '<b>' + esc(r.metric) + ' ' + V('ad_move', 'tw', { metric: r.metric }, num(r.tw)) + '</b>, ' + V('ad_move', 'd_avg12', { metric: r.metric }, frac(r.d_avg12)) + ' vs the 12-week average.';
      ((r.d_avg12 >= 0) !== !!r.inverted ? good : watch).push([Math.abs(r.d_avg12), s]);
    }
    if (ok('ad_cancel')) { const cr = rows('ad_cancel').find((r) => r.sort === 3); if (cr) (cr.tw <= cr.ly ? good : watch).push([1, '<b>Cancellation rate ' + V('ad_cancel', 'tw', { measure: cr.measure }, pct(cr.tw, 2)) + '</b> of active lines against ' + V('ad_cancel', 'ly', { measure: cr.measure }, pct(cr.ly, 2)) + ' in the same week last year.']); }
    const top = (a) => a.sort((x, y) => y[0] - x[0]).slice(0, 4).map((x) => x[1]);
    h += hlBoxes(top(good), top(watch));

    h += sec('1', 'Movement of the live Auto Delivery base');
    h += card('', 'Start + joiners - leavers = end, at customer level. A customer leaves only when they pause or cancel every group they hold, so these figures sit well below the group-level flows in section 2 - both are correct and they are not interchangeable. Reactivated AD is the residual, so the identity holds exactly. Both averages exclude this week.', wbr('ad_move', M, 'metric', false).replace('<th data-field="metric">Metric</th>', '<th data-field="metric">Metric (start + new + reactivated - pauses - cancellations = end)</th>'));
    h += '<div class="card" style="margin-top:var(--cds-gap-md)"><p class="lede">AD is <b>' + V('ad_penetration', 'ad_order_share', null, pct(P.ad_order_share)) + '</b> of orders and <b>' + V('ad_penetration', 'ad_revenue_share', null, pct(P.ad_revenue_share)) + '</b> of revenue. ' + V('ad_penetration', 'ad92_share', null, pct(P.ad92_share)) + ' of the active-92 base is on AD (' + V('ad_penetration', 'ad92', null, num(P.ad92)) + ' of ' + V('ad_penetration', 'a92', null, num(P.a92)) + '). ' + V('ad_penetration', 'new_to_ad', null, num(P.new_to_ad)) + ' customers placed their first-ever AD order this week (13-week average ' + V('ad_penetration', 'new_to_ad_avg13', null, num(P.new_to_ad_avg13, 0)) + '); ' + V('ad_penetration', 'existing_ad', null, num(P.existing_ad)) + ' were existing AD customers.</p></div>';

    // groups
    h += sec('2', 'Net movement in the Auto Delivery group base');
    const g = one('ad_groups');
    if (g) {
      const gv = (f, fmt) => V('ad_groups', f, null, fmt(g[f]));
      h += '<div class="grid tiles">' + tile('Gross inflows', gv('inflows', num), 'activations and reactivations') + tile('Gross outflows', gv('outflows', num), 'active groups cancelled, paused or moved out of Active') + tile('Net movement', '<span class="' + cls(g.net_change) + '">' + gv('net_change', snum) + '</span>', 'change in active groups') + tile('Churn on the base', gv('churn_on_base', (v) => pct(v, 2)), 'active groups cancelled over the opening base') + '</div>';
      const line = (lab, f, fmt, basis, c = '') => '<tr' + (c ? ' class="' + c + '"' : '') + '><td>' + lab + '</td><td>' + gv(f, fmt) + '</td><td class="flat" style="text-align:left">' + basis + '</td></tr>';
      h += card('', 'Inflows are groups entering Active (new activations and reactivations); outflows are groups leaving Active (cancelled, paused, or moved to another state such as Placeholder). Each move is counted once, on the day it happens, so opening + inflows - outflows = closing exactly. A paused group that is later cancelled had already left the active base when it paused, so it is shown below the table as a memo and not counted again. Skips and reschedules do not change the active state and are excluded.', '<div class="tw"><table class="t"><thead><tr><th>Movement</th><th>Groups</th><th style="text-align:left">Basis</th></tr></thead><tbody>' + line('Active AD groups, prior Sunday', 'opening', num, 'opening base') + line('New subscriptions activated', 'activated', num, 'in: groups activated in the week') + line('Reactivations', 'reactivated', num, 'in: paused or cancelled groups resumed') + line('Cancellations', 'cancelled', num, 'out: active groups cancelled') + line('Pauses', 'paused', num, 'out: active groups paused') + (isN(g.other_exits) ? line('Other exits', 'other_exits', num, 'out: active groups moved to another state, such as Placeholder') : '') + line('Net movement on counted flows', 'net_counted', snum, 'inflows less outflows') + (isN(g.unreconciled) && +g.unreconciled !== 0 ? line('Unreconciled', 'unreconciled', snum, 'check failed: counted flows do not tie to the change in the base', 'neg') : '') + line('Active AD groups, this Sunday', 'closing', num, 'closing base', 'tot') + '</tbody></table></div>' + (isN(g.paused_then_cancelled) ? '<p class="note">Memo: ' + gv('paused_then_cancelled', num) + ' already-paused groups were cancelled in the week. They left the active base when they paused, so they are not in the outflows above.</p>' : ''), ' style="margin-top:var(--cds-gap-md)"');
    } else h += state('ad_groups');

    // funnel and cohorts
    h += sec('3', 'AD acquisition and retention');
    if (ok('ad_funnel')) h += '<div class="grid tiles">' + rows('ad_funnel').map((r) => { const wm = { stage: r.stage }; return tile(esc(r.stage), V('ad_funnel', 'orders', wm, num(r.orders)) + ' <span class="pc-sub">orders</span>', V('ad_funnel', 'share_of_ad_orders', wm, pct(r.share_of_ad_orders)) + ' of AD orders · ' + V('ad_funnel', 'revenue', wm, money(r.revenue)) + ' · AOV ' + V('ad_funnel', 'aov', wm, money(r.aov))); }).join('') + '</div>';
    else h += state('ad_funnel');
    if (ok('ad_cohort')) {
      const C = rows('ad_cohort'), s0 = C[0];
      const dir = D('ad_cohort_direction'), d = dir.status === 'ok' && dir.data.length ? dir.data[0] : null;
      let txt = 'Across cohorts whose windows have closed, ' + V('ad_cohort', 'steady_r2', { month_label: s0.month_label }, pct(s0.steady_r2, 0)) + ' of new-to-AD customers place a 2nd AD order within 90 days, ' + V('ad_cohort', 'steady_r3', { month_label: s0.month_label }, pct(s0.steady_r3, 0)) + ' a 3rd and ' + V('ad_cohort', 'steady_r4', { month_label: s0.month_label }, pct(s0.steady_r4, 0)) + ' a 4th within 180 days. The fourth order is the stickiness threshold.';
      if (d) txt += ' Direction of travel on closed cohorts: the share placing a 4th AD order within 180 days is ' + V('ad_cohort_direction', 'r4_last', null, pct(d.r4_last, 0)) + ' for ' + V('ad_cohort_direction', 'last', null, esc(d.last)) + ' against ' + V('ad_cohort_direction', 'r4_first', null, pct(d.r4_first, 0)) + ' for ' + V('ad_cohort_direction', 'first', null, esc(d.first)) + ' (' + V('ad_cohort_direction', 'd_r4', null, pp(d.d_r4)) + '), while the 90-day AD2 rate moved ' + V('ad_cohort_direction', 'd_r2', null, pp(d.d_r2)) + '. Intake went from ' + V('ad_cohort_direction', 'n_first', null, num(d.n_first)) + ' to ' + V('ad_cohort_direction', 'n_last', null, num(d.n_last)) + ' a month.';
      h += '<div class="card" style="margin-top:var(--cds-gap-md)"><h4>AD1 cohort progression</h4><p class="note">Share of each month’s new-to-AD customers that placed a 2nd AD order within 90 days of their first AD order, and a 3rd and 4th AD order within 180 days. A cohort shows a rate only once its window has fully closed (the last day of the month plus 90 or 180 days), so every bar covers the same time and cohorts compare like for like. Blank means the window is still open.</p><p class="lede">' + txt + '</p><div class="legend"><span><i style="background:' + COH[0] + '"></i>AD2 within 90 days</span><span><i style="background:' + COH[1] + '"></i>AD3 within 180 days</span><span><i style="background:' + COH[2] + '"></i>AD4 within 180 days</span></div><div class="chart" id="ch-cohort" data-source="ad_cohort"></div>';
      h += tbl('ad_cohort', 'month_label', [{ f: 'month_label', h: 'AD1 cohort', v: (r) => esc(r.month_label) }, { f: 'n', h: 'New to AD', v: (r) => num(r.n) }, { f: 'r2', h: 'AD2 within 90d', v: (r) => pct(r.r2, 0) }, { f: 'r3', h: 'AD3 within 180d', v: (r) => pct(r.r3, 0) }, { f: 'r4', h: 'AD4 within 180d', v: (r) => pct(r.r4, 0) }], C) + '<p class="note">A dash means the window is still open at the reporting date. The 90-day window closes 90 days after the end of the cohort month and the 180-day window 180 days after it.</p></div>';
    } else h += state('ad_cohort');

    // order mix
    h += sec('4', 'Orders, baskets and share');
    h += card('Breakdown by order type', 'AD Scheduled fires automatically; AD Transactional and AD Reorder are customer-initiated. Transactional = non-AD.', tbl('ad_order_type', 'order_type', [{ f: 'order_type', h: 'Order type' }, { f: 'orders', h: 'Orders', v: (r) => num(r.orders) }, { f: 'pct_lw', h: 'vs LW', v: (r) => frac(r.pct_lw), c: (r) => cls(r.pct_lw) }, { f: 'pct_l13w', h: 'vs 12wk', v: (r) => frac(r.pct_l13w), c: (r) => cls(r.pct_l13w) }, { f: 'share', h: 'Share', v: (r) => pct(r.share) }, { f: 'revenue', h: 'Revenue', v: (r) => money(r.revenue) }, { f: 'aov', h: 'AOV', v: (r) => money(r.aov) }, { f: 'margin_pct', h: 'Margin %', v: (r) => pct(r.margin_pct) }, { f: 'items_per_order', h: 'Items / order', v: (r) => num(r.items_per_order, 2) }], rows('ad_order_type'))) + '<div class="grid wide" style="margin-top:var(--cds-gap-md)">'
      + card('AD vs non-AD orders', 'Movement columns track the AD figure.', tbl('ad_vs_nonad', 'metric', [{ f: 'label', h: 'Metric' }, { f: 'ad', h: 'AD', v: (r) => (r.unit === 'n' ? num(r.ad, 2) : fmtU(r.unit, r.ad)) }, { f: 'nonad', h: 'Non-AD', v: (r) => (r.unit === 'n' ? num(r.nonad, 2) : fmtU(r.unit, r.nonad)) }, { f: 'ad_d_lw', h: 'AD vs LW', v: (r) => (r.unit === 'pct' ? pp(r.ad_d_lw) : frac(r.ad_d_lw)), c: (r) => cls(r.ad_d_lw) }, { f: 'ad_d_l13w', h: 'AD vs 12wk', v: (r) => (r.unit === 'pct' ? pp(r.ad_d_l13w) : frac(r.ad_d_l13w)), c: (r) => cls(r.ad_d_l13w) }], rows('ad_vs_nonad')))
      + card('AD share on four lenses', 'Base to weekly customers is the cadence effect; customers to revenue is the basket effect. An order with both AD and non-AD lines counts wholly as AD.', tbl('ad_lenses', 'lens', [{ f: 'lens', h: 'Lens' }, { f: 'tw', h: 'This week', v: (r) => pct(r.tw, 2) }, { f: 'ly', h: 'Last year', v: (r) => pct(r.ly, 2) }, { f: 'yoy_bps', h: 'YoY', v: (r) => bpsRaw(r.yoy_bps), c: () => 'flat' }], rows('ad_lenses')))
      + card('Cancellation flow and rate', 'Two definitions, both labelled: groups cancelling at least one line (broad) and groups whose whole state flips to Cancelled (conservative).', tbl('ad_cancel', 'measure', [{ f: 'measure', h: 'Measure' }, { f: 'tw', h: 'This week', v: (r) => (r.unit === 'pct' ? pct(r.tw, 2) : num(r.tw)) }, { f: 'ly', h: 'LY week', v: (r) => (r.unit === 'pct' ? pct(r.ly, 2) : num(r.ly)) }, { f: 'yoy', h: 'YoY', v: (r) => (isN(r.yoy) ? bpsRaw(r.yoy) : ''), c: (r) => cls(r.yoy, false) }], rows('ad_cancel'))) + '</div>';
    h += '<p class="note">Skip and reschedule counts are not shown: the source action table stopped populating on 20 Sep 2026.</p>';

    // forward
    h += sec('5', 'Forward view on the Auto Delivery base');
    h += ph('Likelihood of cancellation and pause', 'Everything above reports what has already happened. The feedback asked for a forward view so the meeting can act on the base before it moves.', ['Cancellation and pause risk scored on observable signals: consecutive skips and reschedules, falling order value, a missed delivery promise, a lapsed payment method.', 'Groups approaching their next delivery with a risk flag, sized by revenue at stake.', 'Net add-to-order and remove-from-order activity - the earliest sign a basket is shrinking.', 'Expected net base movement for the coming week and month.'], 'The signals are already in product__auto_delivery_group__eod and the order tables. The gap is a scoring model and a weekly write-back of the score.');

    // brands
    h += sec('', 'Drill-down - brand detail within Auto Delivery');
    h += card('Top brands by AD revenue this week', 'Basket-level product revenue excl GST on AD orders. Share is of the top-eight total, not all AD revenue.', tbl('ad_brands', 'brand', [{ f: 'brand', h: 'Brand' }, { f: 'ad_revenue', h: 'AD revenue', v: (r) => money(r.ad_revenue) }, { f: 'rev_pct_lw', h: 'vs LW', v: (r) => frac(r.rev_pct_lw), c: (r) => cls(r.rev_pct_lw) }, { f: 'rev_pct_l13w', h: 'vs 12wk', v: (r) => frac(r.rev_pct_l13w), c: (r) => cls(r.rev_pct_l13w) }, { f: 'ad_orders', h: 'AD orders', v: (r) => num(r.ad_orders) }, { f: 'ord_pct_lw', h: 'vs LW', v: (r) => frac(r.ord_pct_lw), c: (r) => cls(r.ord_pct_lw) }, { f: 'ord_pct_l13w', h: 'vs 12wk', v: (r) => frac(r.ord_pct_l13w), c: (r) => cls(r.ord_pct_l13w) }, { f: 'ad_aov', h: 'AD AOV', v: (r) => money(r.ad_aov) }, { f: 'share_of_top8', h: 'Share of top 8', v: (r) => pct(r.share_of_top8) }], rows('ad_brands')));
    return h;
  }

  // ================= CATEGORY =================
  // Category and Inventory datasets carry shares as fractions (0.336 = 33.6%).
  const pf = (v, dp = 1) => (isN(v) ? pct(v * 100, dp) : NA);
  const ppf = (v, dp = 1) => (isN(v) ? pp(v * 100, dp) : NA);       // fraction points -> pp
  const fmtM = (v) => (isN(v) ? (+v < 0 ? MINUS : '') + '$' + (Math.abs(v) / 1e6).toFixed(2) + 'm' : NA);
  let catPeriod = 'TW';
  const BOOKS = ['Core Consumables', 'Health & Other Species', 'Hardlines'];
  const BOOK_OWNER = { 'Core Consumables': 'Vittoria Desiati', 'Health & Other Species': 'Lauren Porter', 'Hardlines': 'Luke Prusher' };
  const bookT = (bk) => esc(bk) + (BOOK_OWNER[bk] ? ' - ' + esc(BOOK_OWNER[bk]) : '');
  function rCategory() {
    const t = T.category;
    let h = ptitle(t);
    const need = ['cat_books', 'cat_subcats'];
    if (!ready(need)) return h + state(need);
    const B = rows('cat_books'), S = rows('cat_subcats');
    const good = [], watch = [];
    for (const r of B.filter((x) => x.book !== 'Total')) {
      const wb = { book: r.book };
      (r.rev_vs_bud >= 0 ? good : watch).push([Math.abs(r.rev_vs_bud), '<b>' + esc(r.book) + '</b> ' + V('cat_books', 'rev_vs_bud', wb, smoney(r.rev_vs_bud)) + ' vs ' + plan() + ' on revenue of ' + V('cat_books', 'revenue', wb, money(r.revenue)) + ', ' + V('cat_books', 'rev_vs_ly_pct', wb, frac(r.rev_vs_ly_pct)) + ' vs LY.']);
      (r.pm_vs_bud_pp >= 0 ? good : watch).push([Math.abs(r.pm_vs_bud_pp) * 1e6, '<b>' + esc(r.book) + ' PM ' + V('cat_books', 'pm_pct', wb, pf(r.pm_pct)) + '</b>, ' + V('cat_books', 'pm_vs_bud_pp', wb, ppf(r.pm_vs_bud_pp)) + ' against plan.']);
    }
    const tw = S.filter((r) => r.period === 'TW' && r.sub_category !== 'Total' && isN(r.rev_vs_bud));
    if (tw.length) {
      const hi = tw.reduce((a, b) => (b.rev_vs_bud > a.rev_vs_bud ? b : a)), lo = tw.reduce((a, b) => (b.rev_vs_bud < a.rev_vs_bud ? b : a));
      const ws = (r) => ({ period: r.period, book: r.book, sub_category: r.sub_category });
      if (hi.rev_vs_bud > 0) good.push([0, '<b>' + esc(hi.sub_category) + '</b> (' + esc(hi.book) + ') sits furthest over plan at ' + V('cat_subcats', 'rev_vs_bud', ws(hi), smoney(hi.rev_vs_bud)) + '.']);
      if (lo.rev_vs_bud < 0) watch.push([0, '<b>' + esc(lo.sub_category) + '</b> (' + esc(lo.book) + ') sits furthest under plan at ' + V('cat_subcats', 'rev_vs_bud', ws(lo), smoney(lo.rev_vs_bud)) + '.']);
    }
    const top = (a) => a.sort((x, y) => y[0] - x[0]).slice(0, 5).map((x) => x[1]);
    h += hlBoxes(top(good), top(watch));
    h += '<p class="note" style="margin-bottom:12px">Mirrors the category team’s Weekly Trading & Category KPI Report, now built from the warehouse on the same Monday refresh. Revenue and margin are basket-level product revenue and product margin excl GST, so the book total ties to Commercial. Books group sub-categories: Core Consumables = Food, Treats, Chilled, Litter, Better Bundle; Health & Other Species = Flea and Worming, Health, Grooming, Bird, Horse, Small Animal, Fish, Reptile; Hardlines = Toys, Training and Clean Up, Housing and Bedding, Smart Pet Products, Apparel and Accessories, Car and Travel Accessories, Feeding and Watering.</p>';

    h += sec('1', 'Category performance');
    h += card('', 'The reporting week by merchandise book. vs LY is the same 445 week last year; vs 12wk is against the average of the 12 weeks before. ' + plan() + ' is the category plan at sub-category grain. PLEX pen = private label and exclusive share of revenue; promo pen (TX) = share of non-Auto Delivery revenue sold with a discount applied, so it reads promotions rather than the standing AD discount.',
      tbl('cat_books', 'book', [{ f: 'book', h: 'Book' }, { f: 'revenue', h: 'Revenue', v: (r) => dollars(r.revenue) }, { f: 'rev_vs_ly_pct', h: 'vs LY', v: (r) => frac(r.rev_vs_ly_pct), c: (r) => cls(r.rev_vs_ly_pct) }, { f: 'rev_vs_l12w_pct', h: 'vs 12wk', v: (r) => frac(r.rev_vs_l12w_pct), c: (r) => cls(r.rev_vs_l12w_pct) }, { f: 'rev_vs_bud', h: 'vs ' + plan(), v: (r) => smoney(r.rev_vs_bud), c: (r) => cls(r.rev_vs_bud) }, { f: 'margin', h: 'Margin', v: (r) => dollars(r.margin) }, { f: 'margin_vs_bud', h: 'Margin vs ' + planS(), v: (r) => smoney(r.margin_vs_bud), c: (r) => cls(r.margin_vs_bud) }, { f: 'pm_pct', h: 'PM %', v: (r) => pf(r.pm_pct) }, { f: 'pm_vs_bud_pp', h: 'PM vs ' + planS(), v: (r) => ppf(r.pm_vs_bud_pp), c: (r) => cls(r.pm_vs_bud_pp) }, { f: 'pm_vs_ly_pp', h: 'PM vs LY', v: (r) => ppf(r.pm_vs_ly_pp), c: (r) => cls(r.pm_vs_ly_pp) }, { f: 'plex_pen_pct', h: 'PLEX pen', v: (r) => pf(r.plex_pen_pct) }, { f: 'promo_pen_tx_pct', h: 'Promo pen (TX)', v: (r) => pf(r.promo_pen_tx_pct) }], B, { rowCls: (r) => (r.book === 'Total' ? 'tot' : '') }));

    h += sec('2', 'Trading by category');
    const per = { TW: 'This week', MTD: 'Month to date', YTD: 'Year to date' };
    h += '<div class="pc-tabs" style="margin-bottom:var(--cds-gap-md)" id="cat-period">' + Object.entries(per).map(([k, l]) => '<button class="pc-tab" data-period="' + k + '" aria-selected="' + (catPeriod === k) + '">' + l + '</button>').join('') + '</div>';
    const books = [...BOOKS, ...(S.some((r) => r.period === catPeriod && r.book === 'Unmapped') ? ['Unmapped'] : [])];
    for (const bk of books) {
      const R = S.filter((r) => r.period === catPeriod && r.book === bk).sort((a, b) => (a.sub_category === 'Total') - (b.sub_category === 'Total') || a.sort - b.sort);
      if (!R.length) continue;
      h += card(bookT(bk), '', tbl('cat_subcats', 'period,book,sub_category', [{ f: 'sub_category', h: 'Sub-category', v: (r) => (r.sub_category === 'Total' ? esc(bk) + ' total' : esc(r.sub_category)) }, { f: 'revenue', h: 'Revenue', v: (r) => dollars(r.revenue) }, { f: 'rev_vs_ly_pct', h: 'vs LY', v: (r) => frac(r.rev_vs_ly_pct), c: (r) => cls(r.rev_vs_ly_pct) }, { f: 'rev_vs_l12w_pct', h: 'vs 12wk', v: (r) => (isN(r.rev_vs_l12w_pct) ? frac(r.rev_vs_l12w_pct) : '-'), c: (r) => cls(r.rev_vs_l12w_pct) }, { f: 'rev_vs_bud', h: 'vs ' + plan(), v: (r) => (isN(r.rev_vs_bud) ? smoney(r.rev_vs_bud) : NA), c: (r) => cls(r.rev_vs_bud) }, { f: 'margin', h: 'Margin', v: (r) => dollars(r.margin) }, { f: 'pm_pct', h: 'PM %', v: (r) => pf(r.pm_pct) }, { f: 'pm_vs_ly_pp', h: 'PM vs LY', v: (r) => ppf(r.pm_vs_ly_pp), c: (r) => cls(r.pm_vs_ly_pp) }, { f: 'units', h: 'Units', v: (r) => num(r.units, 0) }, { f: 'units_vs_ly_pct', h: 'Units vs LY', v: (r) => frac(r.units_vs_ly_pct), c: (r) => cls(r.units_vs_ly_pct) }, { f: 'asp', h: 'ASP', v: (r) => money(r.asp) }, { f: 'plex_pen_pct', h: 'PLEX pen', v: (r) => pf(r.plex_pen_pct) }, { f: 'promo_pen_tx_pct', h: 'Promo pen (TX)', v: (r) => pf(r.promo_pen_tx_pct) }, { f: 'ad_discount_pct', h: 'AD discount', v: (r) => pf(r.ad_discount_pct) }], R, { rowCls: (r) => (r.sub_category === 'Total' ? 'tot' : '') }), ' style="margin-bottom:var(--cds-gap-md)"');
    }
    h += '<p class="note">Month to date is the 445 period to date (in week 1 of a period it equals this week); year to date is the FY from week 1. vs 12wk applies to this week only. Units are eaches: packs sold x the unit-of-measure conversion (a 24-can carton = 24 units), so ASP is revenue per each. AD discount = Auto Delivery recurring discount as a share of AD revenue. A sub-category with no plan row shows n/a rather than a variance against zero.</p>';

    h += sec('3', 'Brand spotlight');
    if (ok('cat_brands')) {
      const BR = rows('cat_brands');
      h += '<div class="grid wide">' + BOOKS.map((bk) => { const R = BR.filter((r) => r.book === bk).sort((a, b) => (a.direction === b.direction ? a.rank - b.rank : a.direction === 'up' ? -1 : 1)); if (!R.length) return ''; const n = R[0].brands_above_floor; return card(bookT(bk) + ' <span class="pc-sub">(' + V('cat_brands', 'brands_above_floor', { book: bk, direction: R[0].direction, rank: R[0].rank }, n) + ' brands above the floor)</span>', '', tbl('cat_brands', 'book,direction,rank', [{ f: 'brand', h: 'Brand' }, { f: 'revenue', h: 'Revenue', v: (r) => dollars(r.revenue) }, { f: 'rev_vs_ly_pct', h: 'vs LY', v: (r) => frac(r.rev_vs_ly_pct), c: (r) => cls(r.rev_vs_ly_pct) }, { f: 'rev_vs_lw_pct', h: 'vs LW', v: (r) => frac(r.rev_vs_lw_pct), c: (r) => cls(r.rev_vs_lw_pct) }, { f: 'rev_vs_13w_pct', h: 'vs 13wk', v: (r) => frac(r.rev_vs_13w_pct), c: (r) => cls(r.rev_vs_13w_pct) }], R)); }).join('') + '</div>';
      h += '<p class="note">The three largest movers up and down in each book, ranked on revenue against the same 445 week last year. Floors are $15k a week for Core Consumables and Health & Other Species and $2k for Hardlines. Brands with no sales in the week last year are excluded. vs 13wk is against the average of the 13 weeks ending last week.</p>';
    } else h += state('cat_brands');

    h += sec('4', 'Promotional performance');
    if (ok('cat_promos')) {
      const P = rows('cat_promos');
      h += card('', 'One row per promotional wave, cut from the temporary price discount flag dates (a gap of more than three days starts a new wave). Always-on discounts longer than 35 days are excluded. Pre = average daily units over the 28 days before the flag on the same SKUs; during and post are against it, with transactional and Auto Delivery kept apart. A post window is cut short by any re-promotion, and a wave is only scored once a post window exists.',
        tbl('cat_promos', 'sort', [{ f: 'promotion', h: 'Promotion', v: (r) => esc(r.promotion) + '<span class="sm">' + esc(r.window_label) + ' · ' + esc(r.book || '') + '</span>' }, { f: 'funded_pct', h: 'Funded', v: (r) => pf(r.funded_pct, 0) }, { f: 'during_tx_vs_pre', h: 'During TX vs pre', v: (r) => frac(r.during_tx_vs_pre), c: (r) => cls(r.during_tx_vs_pre) }, { f: 'during_ad_vs_pre', h: 'During AD vs pre', v: (r) => frac(r.during_ad_vs_pre), c: (r) => cls(r.during_ad_vs_pre) }, { f: 'post_tx_vs_pre', h: 'Post TX vs pre', v: (r) => (r.status === 'running' ? 'running' : frac(r.post_tx_vs_pre)), c: (r) => cls(r.post_tx_vs_pre) }, { f: 'post_ad_vs_pre', h: 'Post AD vs pre', v: (r) => (r.status === 'running' ? '' : frac(r.post_ad_vs_pre)), c: (r) => cls(r.post_ad_vs_pre) }, { f: 'pm_during', h: 'PM % during', v: (r) => pf(r.pm_during) }, { f: 'pm_incl_funding', h: 'PM % incl funding', v: (r) => pf(r.pm_incl_funding) }, { f: 'cohort', h: 'Cohort' }], P));
      h += '<p class="note">Cohort is a rule, applied in order, not a judgement: Pending = still running; Loser = transactional units below the pre-promotion baseline both during and after; Winner = units back at or above baseline after the flag dropped, with margin incl funding at or above the book’s (Winner - low margin when below it); Giveaway = units below baseline after and margin incl funding below the book’s; Volume Driver = units below baseline after but a lift of 20% or more during; Churner = otherwise (a small lift, volume fell back, margin held). A short post window makes a call provisional. A funded share of zero does not always mean unfunded: some suppliers fund through a monthly claim never allocated to the promotion, so read margin incl funding as a floor.</p>';
    } else h += state('cat_promos');
    return h;
  }

  // ================= INVENTORY =================
  function rInventory() {
    const t = T.inventory;
    let h = ptitle(t);
    const need = ['inv_health', 'inv_books'];
    if (!ready(need)) return h + state(need);
    const H = one('inv_health'), IB = rows('inv_books');
    const hv = (f, fmt) => V('inv_health', f, null, fmt(H[f]));
    const good = [], watch = [];
    (H.slob_pct <= H.slob_guardrail_pct ? good : watch).push('<b>SLOB ' + hv('slob_pct', (v) => pf(v, 2)) + '</b> of stock against the ' + hv('slob_guardrail_pct', (v) => pf(v, 0)) + ' guardrail.');
    (H.fill_90d >= 0.95 ? good : watch).push('<b>90-day supplier fill ' + hv('fill_90d', pf) + '</b>.');
    watch.push('<b>Out-of-stock lost sales ' + hv('oos_lost_wk', money) + '</b> a week, ' + hv('poor_fill_lost', money) + ' of it on lines with supplier fill below 92%.');
    const tot = IB.find((r) => r.book === 'Total');
    if (tot) (tot.stock_vs_lw_pct <= 0 ? good : watch).push('<b>Stock at cost ' + V('inv_books', 'stock_at_cost', { book: 'Total' }, fmtM(tot.stock_at_cost)) + '</b>, ' + V('inv_books', 'stock_vs_lw_pct', { book: 'Total' }, frac(tot.stock_vs_lw_pct)) + ' on last week' + (tot.stock_vs_lw_pct <= 0 ? ', releasing working capital.' : '.'));
    h += hlBoxes(good, watch, 'Derived from this tab’s own figures by the sign of each movement against its guardrail or last week. The tables below are the source of truth.');
    h += '<div class="card"><p class="lede">Stock at cost <b>' + hv('stock_at_cost', fmtM) + '</b> as at ' + hv('as_at', dateLabel) + '; <b>' + hv('slob_pct', (v) => pf(v, 2)) + '</b> is SLOB (more than 285 days cover, or no sale) - ' + (H.slob_pct > H.slob_guardrail_pct ? 'above' : 'within') + ' the ' + hv('slob_guardrail_pct', (v) => pf(v, 0)) + ' guardrail.</p><p class="lede">Out-of-stock lost sales ' + hv('oos_lost_wk', money) + ' a week, of which ' + hv('poor_fill_lost', money) + ' sits on lines with supplier fill below 92%; 90-day fill rate ' + hv('fill_90d', pf) + '.</p></div>';

    const ibR = IB.filter((r) => r.book !== 'Unmapped' || r.stock_at_cost > 250000);
    h += sec('1', 'Out-of-stock lost sales and cause');
    h += card('', 'Lost = the 4-week average weekly sales of Released for Sale and Introduction item and warehouse lines flagged out of stock on the latest Sunday - a revenue basis, about 1% of sales (OOS % is lost sales over 6-week average weekly sales). Poor-fill = the share of that on lines where 90-day supplier fill is below 92% (orderable but under-delivered); the rest is an ordering gap or demand.', tbl('inv_books', 'book', [{ f: 'book', h: 'Book' }, { f: 'oos_lost_wk', h: 'Lost / wk', v: (r) => money(r.oos_lost_wk) }, { f: 'oos_rev_pct', h: 'OOS % of sales', v: (r) => pf(r.oos_rev_pct, 2), c: (r) => (r.oos_rev_pct >= 0.05 ? 'neg' : '') }, { f: 'oos_rev_pct_wow_pp', h: 'WoW', v: (r) => pp(r.oos_rev_pct_wow_pp, 2), c: (r) => cls(r.oos_rev_pct_wow_pp, false) }, { f: 'oos_rev_pct_l13w', h: '13wk avg', v: (r) => pf(r.oos_rev_pct_l13w, 2) }, { f: 'poor_fill_lost', h: 'Poor-fill $', v: (r) => money(r.poor_fill_lost) }, { f: 'poor_fill_pct', h: 'Poor-fill %', v: (r) => pf(r.poor_fill_pct), c: (r) => (r.poor_fill_pct >= 0.4 ? 'neg' : '') }, { f: 'fill_90d', h: 'Fill 90d', v: (r) => pf(r.fill_90d) }], ibR, { rowCls: (r) => (r.book === 'Total' ? 'tot' : '') }));

    h += sec('2', 'Availability by warehouse');
    if (ok('inv_oos_wh')) {
      const W = rows('inv_oos_wh');
      h += '<div class="grid wide">' + card('Out of stock by warehouse - SKU basis', 'Active-for-ordering items with no stock at week end.', tbl('inv_oos_wh', 'warehouse', [{ f: 'warehouse', h: 'Warehouse' }, { f: 'active_items', h: 'Active items', v: (r) => num(r.active_items, 0) }, { f: 'oos_items', h: 'OOS items', v: (r) => num(r.oos_items, 0) }, { f: 'oos_pct', h: 'OOS %', v: (r) => pf(r.oos_pct), c: (r) => (r.oos_pct >= 0.1 ? 'neg' : '') }], W, { rowCls: (r) => (r.sort >= 9 || /national/i.test(r.warehouse) ? 'tot' : '') }) + W.filter((r) => r.caveat).map((r) => '<p class="note" style="color:var(--color-warn)">' + V('inv_oos_wh', 'caveat', { warehouse: r.warehouse }, esc(r.caveat)) + '</p>').join(''))
        + card('OOS % by book and warehouse', 'Shaded where 7% or more; red at 10% or more.', oosMatrix()) + '</div>';
      h += '<p class="note">Two out-of-stock bases sit on this tab and must not be compared. Availability here counts SKUs unavailable at week end (around 7-8% of active items); lost sales above measure revenue forgone (about 1% of sales). A wide SKU gap on a slow-moving tail costs little revenue, so the two differ by construction.</p>';
    } else h += state('inv_oos_wh');

    h += sec('3', 'Stock and SLOB');
    h += '<div class="grid wide">' + card('Stock and SLOB by book', 'SLOB = stock with more than 285 days cover on the 6-week sell rate (or no sale). Active = still-saleable lifecycle; Exit = discontinued, phasing out or write-off. Red when SLOB is above the 20% guardrail.', tbl('inv_books', 'book', [{ f: 'book', h: 'Book' }, { f: 'stock_at_cost', h: 'Stock at cost', v: (r) => fmtM(r.stock_at_cost) }, { f: 'slob', h: 'SLOB', v: (r) => fmtM(r.slob) }, { f: 'slob_pct', h: 'SLOB %', v: (r) => pf(r.slob_pct), c: (r) => (r.slob_pct > 0.2 ? 'neg' : '') }, { f: 'active_slob', h: 'Active SLOB', v: (r) => fmtM(r.active_slob) }, { f: 'exit_slob', h: 'Exit SLOB', v: (r) => fmtM(r.exit_slob) }], ibR, { rowCls: (r) => (r.book === 'Total' ? 'tot' : '') }))
      + card('Stock value vs last week and last year', 'A fall in stock is a working-capital release. There is no inventory plan in the warehouse yet, so there is no vs-plan column.', tbl('inv_books', 'book', [{ f: 'book', h: 'Book' }, { f: 'stock_at_cost', h: 'Stock at cost', v: (r) => fmtM(r.stock_at_cost) }, { f: 'stock_vs_lw_pct', h: 'vs LW', v: (r) => frac(r.stock_vs_lw_pct), c: (r) => cls(r.stock_vs_lw_pct, false) }, { f: 'stock_vs_ly_pct', h: 'vs LY', v: (r) => frac(r.stock_vs_ly_pct), c: (r) => cls(r.stock_vs_ly_pct, false) }], ibR, { rowCls: (r) => (r.book === 'Total' ? 'tot' : '') })) + '</div>';

    const um = IB.find((r) => r.book === 'Unmapped');
    if (um && um.stock_at_cost <= 250000) h += '<p class="note">Totals include ' + V('inv_books', 'stock_at_cost', { book: 'Unmapped' }, fmtM(um.stock_at_cost)) + ' of stock in sub-categories outside the three books (for example Other and inactive categories), not shown as its own row.</p>';

    h += sec('4', 'Stock by days of cover');
    h += card('This week', 'Days of cover = stock on hand divided by the 6-week sell rate. The last bucket is the SLOB tail.', tbl('inv_cover', 'bucket', [{ f: 'bucket', h: 'Days cover' }, { f: 'stock_at_cost', h: 'Stock at cost', v: (r) => fmtM(r.stock_at_cost) }, { f: 'stock_mix_pct', h: 'Stock mix', v: (r) => pf(r.stock_mix_pct) }, { f: 'wkly_sales_6wk', h: 'Weekly sales (6wk)', v: (r) => money(r.wkly_sales_6wk) }, { f: 'sales_mix_pct', h: 'Sales mix', v: (r) => pf(r.sales_mix_pct) }, { f: 'wks_cover', h: 'Weeks cover', v: (r) => num(r.wks_cover, 1) }, { f: 'dsoh', h: 'DSOH', v: (r) => num(r.dsoh, 0) }], rows('inv_cover'))) + '<div style="height:var(--cds-gap-md)"></div>'
      + card('Last 6 weeks ($m at cost)', 'Each prior week is recalculated the same way from that Sunday. Shading is scaled within each row. Change compares the latest week with six weeks ago: growth in the two shortest-cover buckets is the direction of target.', coverHeat());

    h += sec('5', 'SLOB by lifecycle stage');
    if (ok('inv_slob_lifecycle')) {
      const L = rows('inv_slob_lifecycle').sort((a, b) => a.stage_sort - b.stage_sort || a.book_sort - b.book_sort);
      const stages = [...new Set(L.map((r) => r.stage))];
      h += '<div class="grid">' + stages.map((st) => card(esc(st), '', tbl('inv_slob_lifecycle', 'stage,book', [{ f: 'book', h: 'Book' }, { f: 'slob', h: 'SLOB', v: (r) => fmtM(r.slob) }, { f: 'pct_book_stock', h: '% of book stock', v: (r) => pf(r.pct_book_stock) }, { f: 'wks_cover', h: 'Weeks cover', v: (r) => num(r.wks_cover, 1) }], L.filter((r) => r.stage === st && r.book !== 'Unmapped')))).join('') + '</div><p class="note">Uses the 12-week sell rate. Released-for-sale SLOB is the concern (live range not selling); exit SLOB is expected clearance.</p>';
    } else h += state('inv_slob_lifecycle');

    h += sec('6', 'Range productivity');
    h += '<div class="grid wide">' + card('SKU and variant productivity', 'Visible variants that sold in the last 30 days, against the same point last year.', tbl('inv_range', 'measure', [{ f: 'measure', h: 'Range' }, { f: 'variants', h: 'Variants', v: (r) => num(r.variants, 0) }, { f: 'share', h: 'Share', v: (r) => pf(r.share) }, { f: 'vs_ly_pct', h: 'vs LY', v: (r) => frac(r.vs_ly_pct), c: () => 'flat' }, { f: 'rev_per_productive_30d', h: 'Rev / productive (30d)', v: (r) => (isN(r.rev_per_productive_30d) ? dollars(r.rev_per_productive_30d) : '') }], rows('inv_range')))
      + card('Revenue concentration (last 30 days)', 'SKUs ranked by revenue and cut into bands of 20 / 30 / 30 / 20% of SKUs. Re-cut each week, so there is no vs LY.', tbl('inv_concentration', 'band', [{ f: 'band', h: 'Band' }, { f: 'skus', h: 'SKUs', v: (r) => num(r.skus, 0) }, { f: 'pct_skus', h: '% of SKUs', v: (r) => pf(r.pct_skus) }, { f: 'revenue', h: 'Revenue', v: (r) => money(r.revenue) }, { f: 'pct_revenue', h: '% of revenue', v: (r) => pf(r.pct_revenue) }], rows('inv_concentration'))) + '</div>';
    return h;
  }
  function coverHeat() {
    if (!ok('inv_cover_trend')) return state('inv_cover_trend');
    const R = rows('inv_cover_trend');
    const weeks = [...new Set(R.map((r) => r.week_end_row))].sort();
    const buckets = [...new Set(R.sort((a, b) => a.sort - b.sort).map((r) => r.bucket))];
    let h = '<div class="tw" data-source="inv_cover_trend"><table class="t"><thead><tr><th>Days cover</th>' + weeks.map((w) => '<th>' + esc(R.find((r) => r.week_end_row === w).wk_label) + '</th>').join('') + '<th>Change</th><th>Mix change</th></tr></thead><tbody>';
    for (const b of buckets) {
      const cr = weeks.map((w) => R.find((r) => r.week_end_row === w && r.bucket === b));
      const vals = cr.filter(Boolean).map((r) => +r.stock_at_cost), lo = Math.min(...vals), hi = Math.max(...vals);
      const last = cr[cr.length - 1] || {}, isTot = /total/i.test(b), shortB = /^0-50|^51-90/.test(b);
      h += '<tr' + (isTot ? ' class="tot"' : '') + '><td>' + esc(b) + '</td>' + cr.map((r) => { if (!r) return '<td></td>'; const t = hi > lo && !isTot ? (r.stock_at_cost - lo) / (hi - lo) : 0; return '<td' + (isTot ? '' : ' style="background:color-mix(in srgb, var(--pc-teal) ' + Math.round(6 + t * 30) + '%, transparent)"') + '>' + (r.stock_at_cost / 1e6).toFixed(2) + '</td>'; }).join('') + '<td class="' + (isTot ? '' : cls(last.change_6w, shortB)) + '">' + smoney(last.change_6w) + '</td><td class="flat">' + (isTot ? '' : pp(last.mix_change_pp)) + '</td></tr>';
    }
    return h + '</tbody></table></div>';
  }
  function oosMatrix() {
    if (!ok('inv_oos_matrix')) return state('inv_oos_matrix');
    const R = rows('inv_oos_matrix');
    const books = [...new Map(R.filter((r) => r.book !== 'Unmapped').sort((a, b) => a.book_sort - b.book_sort).map((r) => [r.book, 1])).keys()];
    const whs = [...new Map(R.sort((a, b) => a.wh_sort - b.wh_sort).map((r) => [r.warehouse, 1])).keys()];
    let h = '<div class="tw" data-source="inv_oos_matrix"><table class="t"><thead><tr><th>Book</th>' + whs.map((w) => '<th>' + esc(w) + '</th>').join('') + '</tr></thead><tbody>';
    for (const b of books) h += '<tr' + (b === 'Total' ? ' class="tot"' : '') + '><td>' + esc(b) + '</td>' + whs.map((w) => { const r = R.find((x) => x.book === b && x.warehouse === w); if (!r) return '<td></td>'; const v = +r.oos_pct; const bg = v >= 0.1 ? 'color-mix(in srgb, var(--color-bad) 18%, transparent)' : v >= 0.07 ? 'color-mix(in srgb, var(--color-warn) 18%, transparent)' : 'transparent'; return '<td style="background:' + bg + '">' + pf(v) + '</td>'; }).join('') + '</tr>';
    return h + '</tbody></table></div>';
  }

  // ================= MEDIA & FUNNEL =================
  // Media datasets carry rates as percent (11.60) and rate moves in pp; level changes as fractions.
  function rMedia() {
    const t = T.media;
    let h = ptitle(t);
    const need = ['mf_headline', 'mf_channel'];
    if (!ready(need)) return h + state(need);
    const Hd = one('mf_headline'), C = rows('mf_channel'), F = rows('mf_funnel');
    const hv = (f, fmt) => V('mf_headline', f, null, fmt(Hd[f]));
    const good = [], watch = [];
    (Hd.cvr_vs_l12w_pp >= 0 ? good : watch).push([3, '<b>Conversion ' + hv('cvr', (v) => pct(v, 2)) + '</b>, ' + hv('cvr_vs_l12w_pp', (v) => pp(v, 2)) + ' vs the 12-week average.']);
    (Hd.orders_vs_l12w_pct >= 0 ? good : watch).push([3, '<b>Orders ' + hv('orders', num) + '</b>, ' + hv('orders_vs_l12w_pct', frac) + ' vs the 12-week average.']);
    (Hd.sessions_vs_l12w_pct >= 0 ? good : watch).push([3, '<b>Sessions ' + hv('sessions', num) + '</b>, ' + hv('sessions_vs_l12w_pct', frac) + ' vs the 12-week average.']);
    const ch = C.filter((r) => r.channel !== 'Total' && isN(r.d_orders));
    if (ch.length) {
      const lo = ch.reduce((a, b) => (b.d_orders < a.d_orders ? b : a)), hi = ch.reduce((a, b) => (b.d_orders > a.d_orders ? b : a));
      if (hi.d_orders > 0) good.push([2, '<b>' + esc(hi.channel) + '</b> adds the most orders against the 12-week average: ' + V('mf_channel', 'd_orders', { channel: hi.channel }, snum(hi.d_orders, 0)) + '.']);
      if (lo.d_orders < 0) watch.push([2, '<b>' + esc(lo.channel) + '</b> sits lowest on order contribution: ' + V('mf_channel', 'd_orders', { channel: lo.channel }, snum(lo.d_orders, 0)) + ' against the 12-week average.']);
    }
    const ft = F.find((r) => r.channel === 'Total');
    if (ft) for (const [f, lab, inv] of [['cart_to_checkout', 'Cart to checkout', false], ['add_to_cart', 'Add to cart', false], ['bounce', 'Bounce rate', true]]) { const d = ft[f + '_pp']; if (isN(d)) ((d >= 0) !== inv ? good : watch).push([1, '<b>' + lab + ' ' + V('mf_funnel', f, { channel: 'Total' }, pct(ft[f])) + '</b>, ' + V('mf_funnel', f + '_pp', { channel: 'Total' }, pp(d, 2)) + ' (web).']); }
    const top = (a) => a.sort((x, y) => y[0] - x[0]).slice(0, 5).map((x) => x[1]);
    h += hlBoxes(top(good), top(watch));

    // traffic
    h += sec('', 'Traffic overview');
    h += '<div class="grid tiles">' + tile('Sessions', hv('sessions', num), 'Pet Circle web and app, likely human', pill('vs LW', hv('sessions_vs_lw_pct', frac), cls(Hd.sessions_vs_lw_pct)) + pill('vs 12wk', hv('sessions_vs_l12w_pct', frac), cls(Hd.sessions_vs_l12w_pct)))
      + tile('Unique visitors', hv('unique_visitors', num), 'device-based, all business lines', pill('vs LW', hv('unique_visitors_vs_lw_pct', frac), cls(Hd.unique_visitors_vs_lw_pct)))
      + tile('Page views', hv('page_views', num), 'all business lines', pill('vs LW', hv('page_views_vs_lw_pct', frac), cls(Hd.page_views_vs_lw_pct)))
      + tile('Web / app sessions', hv('web_sessions', num) + ' / ' + hv('app_sessions', num), 'all business lines, including ' + hv('sessions_gap', num) + ' Pharmacy, Insurance and BonnoDog sessions') + '</div>';
    h += '<div class="grid wide" style="margin-top:var(--cds-gap-md)">' + card('Sessions and orders - last 13 weeks', 'Bars are Pet Circle sessions; hover for orders and conversion. The dashed line is the 13-week average.', '<div class="chart" id="ch-mfweekly" data-source="mf_weekly"></div>')
      + card('Sessions by device', 'Mobile web and the app are counted separately; app sessions carry no device type, so they are identified by platform.', tbl('mf_device', 'device', [{ f: 'device', h: 'Device' }, { f: 'sessions', h: 'Sessions', v: (r) => num(r.sessions) }, { f: 'vs_lw_pct', h: 'vs LW', v: (r) => frac(r.vs_lw_pct), c: (r) => cls(r.vs_lw_pct) }, { f: 'share', h: 'Share', v: (r) => pct(r.share) }], rows('mf_device'))) + '</div>';

    // 1
    h += sec('1', 'Sessions, conversion rate and orders');
    h += '<div class="grid tiles">' + tile('Sessions', hv('sessions', num), '12-week average ' + hv('sessions_l12w', (v) => num(v, 0)), pill('vs 12wk', hv('sessions_vs_l12w_pct', frac), cls(Hd.sessions_vs_l12w_pct))) + tile('Conversion rate', hv('cvr', (v) => pct(v, 2)), '12-week average ' + hv('cvr_l12w', (v) => pct(v, 2)), pill('vs 12wk', hv('cvr_vs_l12w_pp', (v) => pp(v, 2)), cls(Hd.cvr_vs_l12w_pp))) + tile('Orders', hv('orders', num), '12-week average ' + hv('orders_l12w', (v) => num(v, 0)), pill('vs 12wk', hv('orders_vs_l12w_pct', frac), cls(Hd.orders_vs_l12w_pct))) + '</div>';
    h += card('Orders by channel', 'Session-attributed transactional orders. They will not tie to the Commercial order count: about 10% of website orders cannot be traced to a session, and Auto Delivery scheduled orders raise no session at all. Read this as channel performance, not the company order count.', tbl('mf_channel', 'channel', [{ f: 'channel', h: 'Channel' }, { f: 'sessions', h: 'Sessions', v: (r) => num(r.sessions) }, { f: 'sessions_vs_l12w_pct', h: 'vs 12wk', v: (r) => frac(r.sessions_vs_l12w_pct), c: (r) => cls(r.sessions_vs_l12w_pct) }, { f: 'cvr', h: 'Conversion', v: (r) => pct(r.cvr, 2) }, { f: 'cvr_vs_l12w_pp', h: 'vs 12wk', v: (r) => pp(r.cvr_vs_l12w_pp, 2), c: (r) => cls(r.cvr_vs_l12w_pp) }, { f: 'orders', h: 'Orders', v: (r) => num(r.orders, 0) }, { f: 'orders_share', h: 'Share of orders', v: (r) => pct(r.orders_share) }, { f: 'd_orders', h: 'Orders vs 12wk', v: (r) => snum(r.d_orders, 0), c: (r) => cls(r.d_orders) }], C, { rowCls: (r) => (r.channel === 'Total' ? 'tot' : '') }), ' style="margin-top:var(--cds-gap-md)"');

    // 2 bridge
    h += sec('2', 'Orders bridge - traffic versus conversion');
    const tot = C.find((r) => r.channel === 'Total');
    if (tot) h += '<p class="lede">Orders moved from a 12-week average of <b>' + V('mf_channel', 'orders_l12w', { channel: 'Total' }, num(tot.orders_l12w, 0)) + '</b> to <b>' + V('mf_channel', 'orders', { channel: 'Total' }, num(tot.orders, 0)) + '</b> this week (' + V('mf_channel', 'd_orders', { channel: 'Total' }, snum(tot.d_orders, 0)) + '): traffic contributed ' + V('mf_channel', 'vol_effect', { channel: 'Total' }, snum(tot.vol_effect, 0)) + ' and conversion ' + V('mf_channel', 'rate_effect', { channel: 'Total' }, snum(tot.rate_effect, 0)) + '.</p>';
    h += card('', 'Traffic effect = change in sessions x the 12-week conversion rate. Conversion effect = change in conversion rate x 12-week sessions. Interaction is the cross-term. On every row the three add to the change in orders, and the channel rows add to the total.', tbl('mf_channel', 'channel', [{ f: 'channel', h: 'Channel' }, { f: 'orders_l12w', h: 'Orders 12wk avg', v: (r) => num(r.orders_l12w, 0) }, { f: 'orders', h: 'Orders this week', v: (r) => num(r.orders, 0) }, { f: 'd_orders', h: 'Change', v: (r) => snum(r.d_orders, 0), c: (r) => cls(r.d_orders) }, { f: 'vol_effect', h: 'Traffic effect', v: (r) => snum(r.vol_effect, 0), c: (r) => cls(r.vol_effect) }, { f: 'rate_effect', h: 'Conversion effect', v: (r) => snum(r.rate_effect, 0), c: (r) => cls(r.rate_effect) }, { f: 'interaction', h: 'Interaction', v: (r) => snum(r.interaction, 0), c: () => 'flat' }], [...C].sort((a, b) => (a.channel === 'Total') - (b.channel === 'Total') || b.d_orders - a.d_orders), { rowCls: (r) => (r.channel === 'Total' ? 'tot' : '') }));

    // 3 funnel
    h += sec('3', 'Web funnel by channel');
    if (ok('mf_funnel')) {
      const cell = (r, f) => (isN(r[f]) ? pct(r[f]) + (isN(r[f + '_pp']) ? '<span class="sm ' + cls(r[f + '_pp']) + '">' + pp(r[f + '_pp'], 2) + '</span>' : '') : NA);
      const ft0 = F[0] || {};
      h += card('', 'Web only - the app raises no on-site funnel events, so Mobile App reads n/a. Each cell shows the rate with its move against the 12-week average beneath. Cart to checkout = visited checkout / visited cart; cart to thanks = strict cart to checkout x checkout to thanks. The cart counter broke in ' + V('mf_funnel', 'cart_base_excluded_weeks', { channel: ft0.channel }, esc(ft0.cart_base_excluded_weeks || 'no weeks')) + ', so the cart rates compare against the ' + V('mf_funnel', 'cart_base_weeks', { channel: ft0.channel }, ft0.cart_base_weeks) + ' clean weeks only.', tbl('mf_funnel', 'channel', [{ f: 'channel', h: 'Channel' }, { f: 'visited_cart', h: 'Visited cart', v: (r) => cell(r, 'visited_cart') }, { f: 'cart_to_checkout', h: 'Cart to checkout', v: (r) => cell(r, 'cart_to_checkout') }, { f: 'checkout_to_thanks', h: 'Checkout to thanks', v: (r) => cell(r, 'checkout_to_thanks') }, { f: 'cart_to_thanks', h: 'Cart to thanks', v: (r) => cell(r, 'cart_to_thanks') }, { f: 'session_mix', h: 'Session mix', v: (r) => pct(r.session_mix) + (isN(r.session_mix_pp) && r.channel !== 'Total' ? '<span class="sm flat">' + pp(r.session_mix_pp, 2) + '</span>' : '') }], F, { rowCls: (r) => (r.channel === 'Total' ? 'tot' : '') }));
    } else h += state('mf_funnel');

    // 4-6
    h += sec('4', 'Paid search performance');
    if (ok('mf_sem_category')) {
      const SM = rows('mf_sem_category'), st = SM.find((r) => r.campaign_category === 'Total');
      const sw = (r, f, fmt) => V('mf_sem_category', f, { campaign_category: r.campaign_category }, fmt(r[f]));
      const cats = SM.filter((r) => r.campaign_category !== 'Total' && r.campaign_category !== 'Brand');
      const hiRoas = cats.filter((r) => isN(r.platform_roas)).sort((a, b) => b.platform_roas - a.platform_roas)[0];
      const loIs = cats.filter((r) => isN(r.search_is) && r.spend > 5000).sort((a, b) => a.search_is - b.search_is)[0];
      if (st) h += '<p class="lede">Paid search spent ' + sw(st, 'spend', money) + ' this week (' + sw(st, 'spend_vs_l12w_pct', frac) + ' on the 12-week average). Google search impression share was ' + sw(st, 'search_is', (v) => pct(v, 1)) + ' against ' + sw(st, 'search_is_l12w', (v) => pct(v, 1)) + ' on average, and almost all of the share we miss is lost on ad rank (' + sw(st, 'rank_lost_is', (v) => pct(v, 1)) + ') rather than budget (' + sw(st, 'budget_lost_is', (v) => pct(v, 1)) + ').' + (hiRoas ? ' ' + sw(hiRoas, 'campaign_category', esc) + ' returns the most per dollar at ' + sw(hiRoas, 'platform_roas', (v) => num(v, 2) + 'x') + '.' : '') + (loIs ? ' ' + sw(loIs, 'campaign_category', esc) + ' has the lowest share among the larger categories at ' + sw(loIs, 'search_is', (v) => pct(v, 1)) + '.' : '') + '</p>';
      const isCell = (r) => (isN(r.search_is) ? pct(r.search_is, 1) + '<span class="sm ' + cls(r.search_is_vs_l12w_pp) + '">' + pp(r.search_is_vs_l12w_pp, 1) + ' vs 12wk</span>' : NA);
      const lostCell = (r) => (isN(r.search_is) ? '<div class="isbar" title="Won ' + pct(r.search_is, 1) + ', lost to budget ' + pct(r.budget_lost_is, 1) + ', lost to rank ' + pct(r.rank_lost_is, 1) + '"><span style="width:' + (+r.search_is || 0) + '%;background:var(--pc-c1)"></span><span style="width:' + (+r.budget_lost_is || 0) + '%;background:var(--pc-c4)"></span><span style="width:' + (+r.rank_lost_is || 0) + '%;background:var(--pc-lav)"></span></div><span class="sm">budget ' + pct(r.budget_lost_is, 1) + ' · rank ' + pct(r.rank_lost_is, 1) + '</span>' : NA);
      h += card('Paid search by category - Google and Bing', '', '<div class="legend"><span><i style="background:var(--pc-c1)"></i>Impression share won</span><span><i style="background:var(--pc-c4)"></i>Lost to budget</span><span><i style="background:var(--pc-lav)"></i>Lost to ad rank</span></div>' + tbl('mf_sem_category', 'campaign_category', [
        { f: 'campaign_category', h: 'Category', v: (r) => esc(r.campaign_category) + (isN(r.shopping_spend_share) && r.campaign_category !== 'Total' ? '<span class="sm">' + pct(r.shopping_spend_share, 0) + ' Shopping</span>' : '') },
        { f: 'spend', h: 'Spend', v: (r) => money(r.spend) + '<span class="sm ' + cls(r.spend_vs_l12w_pct, false) + '">' + frac(r.spend_vs_l12w_pct) + ' vs 12wk</span>' },
        { f: 'clicks', h: 'Clicks', v: (r) => num(r.clicks) + '<span class="sm">CPC ' + dollars2(r.cpc) + '</span>' },
        { f: 'platform_revenue', h: 'Platform revenue', v: (r) => money(r.platform_revenue) },
        { f: 'platform_roas', h: 'ROAS', v: (r) => (isN(r.platform_roas) ? num(r.platform_roas, 2) + 'x' : NA) + '<span class="sm">12wk ' + (isN(r.platform_roas_l12w) ? num(r.platform_roas_l12w, 2) + 'x' : NA) + '</span>', c: (r) => (r.campaign_category === 'Brand' ? 'flat' : cls(r.platform_roas - r.platform_roas_l12w)) },
        { f: 'platform_new_customers', h: 'New customers', v: (r) => num(r.platform_new_customers, 0) + '<span class="sm">' + (isN(r.cost_per_new_customer) ? dollars(r.cost_per_new_customer) + ' each' : '') + '</span>' },
        { f: 'search_is', h: 'Impression share', v: isCell },
        { f: 'rank_lost_is', h: 'Share lost', v: lostCell }], SM, { rowCls: (r) => (r.campaign_category === 'Total' ? 'tot' : '') }) +
        '<p class="note">Spend, clicks and campaign category come from the ad platforms in the warehouse; YouTube and Demand Gen campaigns are left out as they are video, not search' + (st && st.excluded_spend ? ' (' + sw(st, 'excluded_spend', money) + ' this week)' : '') + ', so the total reconciles to the paid search channels in section 5 less that spend. Revenue, orders and new customers are what Google and Bing report for their own clicks, so they overlap with other channels and run higher than session-attributed figures; Bing Shopping reports revenue but not orders or new customers. Brand ROAS is demand capture from people already searching for Pet Circle and is not comparable with the category rows. Impression share is Google search only (Bing does not report it), from the raw Google Ads transfer outside the business layer, weighted by eligible impressions; Brand blends brand search (about 89%) with Brand Shopping (about 32%).</p>');
    } else h += state('mf_sem_category');
    h += sec('5', 'Social, SEO and other channels');
    if (ok('mf_acq_channels')) {
      const AC = rows('mf_acq_channels'), A = (c) => AC.find((r) => r.acquisition_channel === c);
      const ps = A('Paid Social'), seo = A('Organic Search'), aT = A('Total');
      const av = (r, f, fmt) => V('mf_acq_channels', f, { acquisition_channel: r.acquisition_channel }, fmt(r[f]));
      if (ps && seo) h += '<p class="lede"><b>Paid Social</b> brought ' + av(ps, 'sessions', (v) => num(v, 0)) + ' sessions (' + av(ps, 'sessions_vs_l12w_pct', frac) + ' on the 12-week average) and ' + av(ps, 'orders', (v) => num(v, 0)) + ' orders on ' + av(ps, 'spend', money) + ' of spend, ' + av(ps, 'cost_per_order', dollars2) + ' per order against ' + av(ps, 'cost_per_order_l12w', dollars2) + ' on average. <b>Organic search</b> brought ' + av(seo, 'sessions', (v) => num(v, 0)) + ' sessions (' + av(seo, 'sessions_vs_l12w_pct', frac) + ') and ' + av(seo, 'orders', (v) => num(v, 0)) + ' orders at ' + av(seo, 'cvr', (v) => pct(v, 2)) + ' conversion, with ' + av(seo, 'new_customers', (v) => num(v, 0)) + ' new customers.</p>';
      const L = AC.filter((r) => r.acquisition_channel !== 'Total' && r.sessions >= 100).sort((a, b) => b.sessions - a.sessions);
      if (aT) L.push(aT);
      h += card('Every acquisition channel on one basis', '', tbl('mf_acq_channels', 'acquisition_channel', [
        { f: 'acquisition_channel', h: 'Channel', v: (r) => esc(r.acquisition_channel) + '<span class="sm">' + esc(r.acquisition_channel_group) + '</span>' },
        { f: 'sessions', h: 'Sessions', v: (r) => num(r.sessions, 0) + '<span class="sm ' + cls(r.sessions_vs_l12w_pct) + '">' + frac(r.sessions_vs_l12w_pct) + ' vs 12wk</span>' },
        { f: 'orders', h: 'Orders', v: (r) => num(r.orders, 0) + '<span class="sm ' + cls(r.orders_vs_l12w_pct) + '">' + frac(r.orders_vs_l12w_pct) + '</span>' },
        { f: 'cvr', h: 'Conversion', v: (r) => pct(r.cvr, 2) + '<span class="sm ' + cls(r.cvr_vs_l12w_pp) + '">' + pp(r.cvr_vs_l12w_pp, 2) + '</span>' },
        { f: 'new_customers', h: 'New customers', v: (r) => num(r.new_customers, 0) },
        { f: 'revenue', h: 'Revenue', v: (r) => money(r.revenue) },
        { f: 'revenue_per_session', h: 'Revenue / session', v: (r) => dollars2(r.revenue_per_session) },
        { f: 'spend', h: 'Spend', v: (r) => (isN(r.spend) ? money(r.spend) : '<span class="flat">no cost feed</span>') },
        { f: 'cost_per_new_customer', h: 'Cost / new customer', v: (r) => (isN(r.cost_per_new_customer) ? dollars(r.cost_per_new_customer) : '') },
        { f: 'roas', h: 'ROAS', v: (r) => (isN(r.roas) ? num(r.roas, 2) + 'x' : '') }], L, { rowCls: (r) => (r.acquisition_channel === 'Total' ? 'tot' : '') }) +
        '<p class="note">Acquisition channel as defined in the warehouse online session table (human traffic, Pet Circle only), web and app together - the channel totals reconcile exactly to the sessions and orders above. Orders and revenue are those placed in a session from that channel (session-attributed, last touch), so channels that work earlier in the journey - Paid Social above all - read low on this basis. Spend comes from the ad platforms in the warehouse (Google and Bing for paid search, Facebook for Paid Social, Criteo for Display); the other channels have no cost feed, and the Total ROAS spreads paid spend over all revenue. Revenue is product revenue on the orders matched to sessions, so it does not tie to the Commercial scorecard. Channels under 100 sessions are left out.</p>');
      h += '<div class="grid" style="margin-top:var(--cds-gap-md)">';
      if (ok('mf_social')) {
        const SO = rows('mf_social'), st = SO.find((r) => r.campaign_category === 'Total');
        const sv = (f, fmt) => V('mf_social', f, { campaign_category: 'Total' }, fmt(st[f]));
        h += card('Paid Social (Facebook)', '', '<div class="grid tiles">' + tile('Spend', sv('spend', money), '12-week average ' + sv('spend_l12w', money)) + tile('Clicks', sv('clicks', (v) => num(v, 0)), sv('ctr', (v) => pct(v, 2)) + ' of ' + sv('impressions', (v) => num(v, 0)) + ' impressions') + tile('Cost per click', sv('cpc', dollars2), 'CPM ' + sv('cpm', dollars2)) + tile('Cost per new customer', av(ps, 'cost_per_new_customer', dollars), av(ps, 'new_customers', (v) => num(v, 0)) + ' new customers, session-attributed') + '</div>' +
          tbl('mf_social', 'campaign_category', [{ f: 'campaign_category', h: 'Campaigns' }, { f: 'spend', h: 'Spend', v: (r) => money(r.spend) }, { f: 'spend_l12w', h: '12-wk avg', v: (r) => money(r.spend_l12w) }, { f: 'impressions', h: 'Impressions', v: (r) => num(r.impressions) }, { f: 'ctr', h: 'CTR', v: (r) => pct(r.ctr, 2) }, { f: 'cpc', h: 'CPC', v: (r) => dollars2(r.cpc) }], SO, { rowCls: (r) => (r.campaign_category === 'Total' ? 'tot' : '') }) +
          '<p class="note">Facebook reports about ' + sv('clicks', (v) => num(v, 0)) + ' clicks against ' + av(ps, 'sessions', (v) => num(v, 0)) + ' Paid Social sessions on site, so most clicks never become a tracked session. Facebook’s own reported conversions are not in the warehouse yet, so there is no platform ROAS to set beside the session-attributed one.</p>');
      } else h += state('mf_social');
      const ai = A('AI LLM Organic Search');
      h += card('Organic search and AI search', '', '<div class="grid tiles">' + tile('Organic sessions', av(seo, 'sessions', (v) => num(v, 0)), '', pill('vs 12wk', av(seo, 'sessions_vs_l12w_pct', frac), cls(seo.sessions_vs_l12w_pct))) + tile('Organic orders', av(seo, 'orders', (v) => num(v, 0)), av(seo, 'cvr', (v) => pct(v, 2)) + ' conversion', pill('vs 12wk', av(seo, 'orders_vs_l12w_pct', frac), cls(seo.orders_vs_l12w_pct))) + tile('Organic revenue', av(seo, 'revenue', money), av(seo, 'revenue_per_session', dollars2) + ' per session; ' + av(seo, 'new_customers', (v) => num(v, 0)) + ' new customers') + (ai ? tile('AI search (organic)', av(ai, 'sessions', (v) => num(v, 0)), av(ai, 'orders', (v) => num(v, 0)) + ' orders from ChatGPT-style assistants', pill('vs 12wk', av(ai, 'sessions_vs_l12w_pct', frac), cls(ai.sessions_vs_l12w_pct))) : '') + '</div><p class="note">Brand versus non-brand organic search and ranking on priority terms need Search Console data, which is not in the warehouse.</p>');
      h += '</div>';
      if (ok('mf_acq_weekly')) {
        const W = rows('mf_acq_weekly'), wk = [...new Set(W.map((r) => r.week_start))].sort();
        const groups = ['SEO', 'Social', 'Other', 'AI LLM', 'Push', 'SMS', 'Email', 'Direct', 'SEM'].filter((g) => W.some((r) => r.channel_group === g));
        let t = '<div class="tw" data-source="mf_acq_weekly"><table class="t"><thead><tr><th>Sessions by channel group</th>' + wk.map((x) => '<th>' + dateLabel(x) + '</th>').join('') + '</tr></thead><tbody>';
        for (const g of groups) { const R = wk.map((x) => W.find((r) => r.channel_group === g && r.week_start === x)); const vals = R.map((r) => (r ? +r.sessions : NaN)).filter((x) => !isNaN(x)); const lo = Math.min(...vals), hi = Math.max(...vals); t += '<tr><td>' + esc(g) + '</td>' + R.map((r) => { if (!r) return '<td></td>'; const k = hi > lo ? (r.sessions - lo) / (hi - lo) : 0.5; return '<td style="background:color-mix(in srgb, var(--pc-teal) ' + Math.round(6 + k * 30) + '%, transparent)">' + num(r.sessions) + '</td>'; }).join('') + '</tr>'; }
        h += card('13-week trend', 'Shading is scaled within each row, so each group’s own trajectory reads across; darker means more sessions. Weeks are week commencing.', t + '</tbody></table></div>', ' style="margin-top:var(--cds-gap-md)"');
      } else h += state('mf_acq_weekly');
    } else h += state('mf_acq_channels');
    h += sec('6', 'CRM performance');
    const cp = one('mf_coupons');
    if (cp) {
      const cv = (f, fmt) => V('mf_coupons', f, { coupon: cp.coupon }, fmt(cp[f]));
      h += '<div class="grid tiles">' + tile('Coupon orders', cv('orders', num), cv('orders_share', pct) + ' of all orders; ' + cv('new_customer_orders', num) + ' were a first order', pill('vs LW', cv('orders_vs_lw_pct', frac), 'flat') + pill('vs 12wk', cv('orders_vs_l12w_pct', frac), 'flat'))
        + tile('Coupon cost', cv('discount', money), cv('discount_pct_of_rev', pct) + ' of the revenue on those orders', pill('vs 12wk', cv('discount_vs_l12w_pct', frac), cls(cp.discount_vs_l12w_pct, false)))
        + tile('Product margin on coupon orders', cv('pm_pct_after', pct), 'after the coupon; ' + cv('pm_pct_before', pct) + ' before it', pill('vs 12wk', cv('pm_pct_after_vs_l12w_pp', (v) => pp(v, 1)), cls(cp.pm_pct_after_vs_l12w_pp))) + '</div>';
      h += '<p class="note">Coupon value is the order-level coupon amount excl GST from the warehouse. Coupon codes are not yet linked to orders in the warehouse, so a code- or campaign-level breakdown is not possible until that link is added.</p>';
    } else h += state('mf_coupons');
    h += ph('Owned channels - email, SMS and push', 'Called out in the feedback as the largest gap on this tab. Email and SMS appear above only as session sources.', ['Sends, delivery, open and click rates, orders and revenue for email, SMS and push.', 'Campaign-level breakdown so a single send can be read against the weekly total.', 'Coupon effectiveness by code or campaign: incremental orders and margin after the discount.', 'Push re-engagement, which is absent from the channel split today.'], 'Send and engagement data sit in the CRM platform (Braze). The coupon code-to-order link needs adding to the warehouse for the code-level view.');

    // region + landing + drill-down
    h += sec('', 'By region');
    h += card('', 'Sessions reconcile exactly to the channel total.', tbl('mf_region', 'region', [{ f: 'region', h: 'Region' }, { f: 'sessions', h: 'Sessions', v: (r) => num(r.sessions) }, { f: 'sessions_vs_l12w_pct', h: 'vs 12wk', v: (r) => frac(r.sessions_vs_l12w_pct), c: (r) => cls(r.sessions_vs_l12w_pct) }, { f: 'mix', h: 'Mix', v: (r) => pct(r.mix) }, { f: 'orders', h: 'Orders', v: (r) => num(r.orders, 0) }, { f: 'cvr', h: 'Conversion', v: (r) => pct(r.cvr, 2) }, { f: 'cvr_pp', h: 'vs 12wk', v: (r) => pp(r.cvr_pp, 2), c: (r) => cls(r.cvr_pp) }], rows('mf_region')));
    h += sec('', 'Drill-down - landing surface');
    h += '<div class="decision"><b>Open decision:</b> is the landing surface view needed at this level? It is kept here at the foot of the tab so the call can be made on the real thing.</div>';
    h += card('Where sessions land first', 'Read conversion alongside mix: a product-page arrival is often mid-research. Cart, Checkout and Thanks appear when a returning session resumes at that step, so their rates are structurally high. Funnel rates are web only.', tbl('mf_landing', 'surface', [{ f: 'surface', h: 'Landing surface' }, { f: 'sessions', h: 'Sessions', v: (r) => num(r.sessions) }, { f: 'sessions_vs_l12w_pct', h: 'vs 12wk', v: (r) => frac(r.sessions_vs_l12w_pct), c: (r) => cls(r.sessions_vs_l12w_pct) }, { f: 'mix', h: 'Mix', v: (r) => pct(r.mix) }, { f: 'mix_pp', h: 'Mix vs 12wk', v: (r) => pp(r.mix_pp, 2), c: () => 'flat' }, { f: 'cvr', h: 'Conversion', v: (r) => pct(r.cvr, 2) }, { f: 'cvr_pp', h: 'vs 12wk', v: (r) => pp(r.cvr_pp, 2), c: (r) => cls(r.cvr_pp) }, { f: 'atc', h: 'Add to cart', v: (r) => (isN(r.atc) ? pct(r.atc) : NA) }, { f: 'cart', h: 'Cart', v: (r) => (isN(r.cart) ? pct(r.cart) : NA) }, { f: 'checkout', h: 'Checkout', v: (r) => (isN(r.checkout) ? pct(r.checkout) : NA) }, { f: 'orders', h: 'Orders', v: (r) => num(r.orders, 0) }], rows('mf_landing')));
    h += sec('', 'Drill-down - bounce rate and add to cart');
    if (ok('mf_funnel')) h += card('', 'Held below the meeting line. Bounce is web sessions with at most one page view over web sessions, so a rise is a step away from the funnel. Add to cart is web sessions adding to the basket. Read these when a conversion move above needs explaining.', tbl('mf_funnel', 'channel', [{ f: 'channel', h: 'Channel' }, { f: 'bounce', h: 'Bounce rate', v: (r) => (isN(r.bounce) ? pct(r.bounce) : NA) }, { f: 'bounce_pp', h: 'vs 12wk', v: (r) => (isN(r.bounce_pp) ? pp(r.bounce_pp, 2) : ''), c: (r) => cls(r.bounce_pp, false) }, { f: 'add_to_cart', h: 'Add to cart', v: (r) => (isN(r.add_to_cart) ? pct(r.add_to_cart) : NA) }, { f: 'add_to_cart_pp', h: 'vs 12wk', v: (r) => (isN(r.add_to_cart_pp) ? pp(r.add_to_cart_pp, 2) : ''), c: (r) => cls(r.add_to_cart_pp) }], F, { rowCls: (r) => (r.channel === 'Total' ? 'tot' : '') }));
    h += '<p class="note"><b>Source and caveats.</b> Every view on this tab except paid media comes from business_layer.online__session: Pet Circle business line, likely human sessions, orders = converting sessions. Channels follow its acquisition channel group, with all app sessions shown as Mobile App; Other = push, AI LLM and other. Landing surfaces use its landing page definitions, with root-URL arrivals counted as Homepage, sign-in and account pages as Account, and brand and pet-type URLs matched to the product__brand and pet__species lists; help and policy pages fall in Other. Region is the visitor state, with ACT, Tasmania, NT and overseas as Other. None of these are reconciled to the Commercial scorecard. Rates are always re-derived from summed counts.</p>';
    return h;
  }
  function mfChart(el) {
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = rows('mf_weekly').sort((a, b) => (a.week_end_row < b.week_end_row ? -1 : 1));
    if (!R.length || !el.clientWidth) return;
    const W = el.clientWidth, H = 220, m = { t: 12, r: 8, b: 26, l: 48 };
    const x = d3.scaleBand(R.map((r) => r.week_end_row), [m.l, W - m.r]).padding(0.25);
    const y = d3.scaleLinear([0, d3.max(R, (r) => +r.cube_sessions) * 1.08], [H - m.b, m.t]).nice();
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    svg.append('g').attr('transform', 'translate(0,' + (H - m.b) + ')').call(d3.axisBottom(x).tickFormat((d) => dateLabel(d)).tickSizeOuter(0)).call(noAxisFont).call((g) => g.selectAll('.tick text').attr('display', (d, i) => (W < 700 && i % 2 ? 'none' : null)));
    svg.append('g').attr('transform', 'translate(' + m.l + ',0)').call(d3.axisLeft(y).ticks(4).tickFormat((v) => Math.round(v / 1e3) + 'k')).call(noAxisFont).call((g) => g.select('.domain').remove());
    svg.append('g').selectAll('rect').data(R).join('rect').attr('x', (r) => x(r.week_end_row)).attr('width', x.bandwidth()).attr('y', (r) => y(r.cube_sessions)).attr('height', (r) => y(0) - y(r.cube_sessions)).attr('rx', 3).attr('fill', PCC[0]).attr('opacity', (r, i) => (i === R.length - 1 ? 1 : 0.6));
    const avg = d3.mean(R, (r) => +r.cube_sessions);
    svg.append('line').attr('x1', m.l).attr('x2', W - m.r).attr('y1', y(avg)).attr('y2', y(avg)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '4 3');
    const tp = tipFor(el);
    svg.append('g').selectAll('rect').data(R).join('rect').attr('x', (r) => x(r.week_end_row) - x.step() * 0.12).attr('width', x.step()).attr('y', m.t).attr('height', H - m.t - m.b).attr('fill', 'transparent')
      .on('mousemove', (ev, r) => { const [mx, my] = d3.pointer(ev, el); tp.innerHTML = '<span class="k">w/e ' + dateLabel(r.week_end_row) + '</span><br>Sessions ' + num(r.cube_sessions) + '<br>Orders ' + num(r.orders) + '<br>Conversion ' + pct(r.cvr, 2); place(el, tp, mx, my); })
      .on('mouseleave', () => { tp.style.display = 'none'; });
  }

  // ================= PRICE =================
  // Indices are ratios (1.00 = parity); shares are percent; level changes are fractions.
  const idx = (v) => (isN(v) ? (+v).toFixed(3) : NA);
  const sidx = (v) => (isN(v) ? sg(v, Math.abs(+v).toFixed(3)) : NA);
  function rPrice() {
    const t = T.price;
    let h = ptitle(t);
    const need = ['pr_index', 'pr_subcats'];
    if (!ready(need)) return h + state(need);
    const I = rows('pr_index'), S = rows('pr_subcats');
    const good = [], watch = [];
    for (const r of I) { const w = { pricing_group: r.pricing_group }; ((r.ad_index <= 1 || r.ad_index_wow < 0) ? good : watch).push('<b>' + esc(r.pricing_group) + ' index ' + V('pr_index', 'ad_index', w, idx(r.ad_index)) + '</b>, ' + (r.ad_index <= 1 ? 'under' : 'over') + ' parity' + (r.ad_index > 1 && r.ad_index_wow < 0 ? ' but closing, ' : ' and ') + V('pr_index', 'ad_index_wow', w, sidx(r.ad_index_wow)) + ' on last week.'); }
    const st = S.find((r) => r.book === 'Total' && r.sub_category === 'Total');
    if (st) watch.push('<b>' + V('pr_subcats', 'revenue_at_risk', { book: 'Total', sub_category: 'Total' }, money(st.revenue_at_risk)) + '</b> of last week’s revenue sits on lines priced above the cheapest in market.');
    const ir = rows('pr_irritants')[0];
    if (ir) watch.push('<b>' + V('pr_irritants', 'n_lines', { sort: ir.sort }, ir.n_lines) + ' KVI lines out of policy</b>, ' + V('pr_irritants', 'n_12w_plus', { sort: ir.sort }, ir.n_12w_plus) + ' of them for twelve weeks or more.');
    h += hlBoxes(good, watch);
    h += '<div class="decision"><b>Open decision:</b> the direction for pricing and promotion is still being set with James and Nihan. This tab carries price competitiveness, the KVI watch list and the discount and funding picture as a starting point; promotional performance sits on the Category tab.</div>';

    h += sec('1', 'Price competitiveness');
    h += '<div class="grid tiles">' + I.map((r) => { const w = { pricing_group: r.pricing_group }; return tile(esc(r.pricing_group) + ' · ' + V('pr_index', 'matched_skus', w, num(r.matched_skus, 0)) + ' matched', V('pr_index', 'ad_index', w, idx(r.ad_index)), 'snapshot ' + V('pr_index', 'snapshot_date', w, dateLabel(r.snapshot_date)), pill('WoW', V('pr_index', 'ad_index_wow', w, sidx(r.ad_index_wow)), cls(r.ad_index_wow, false)) + pill('vs 12wk', V('pr_index', 'ad_index_vs_avg12', w, sidx(r.ad_index_vs_avg12)), cls(r.ad_index_vs_avg12, false))).replace(/<\/div>$/, '<div class="spark" data-prspark="' + esc(r.pricing_group) + '" data-source="pr_index_trend"></div></div>'); }).join('') + '</div>';
    h += '<p class="note">Worm = the last 13 weekly snapshots of each index on its own scale, with the 13-week average dashed; read it for direction rather than level. Hover for the weekly figure.</p>';
    if (ok('pr_index_comp')) {
      const PC = rows('pr_index_comp'), G = I.map((r) => r.pricing_group);
      const comps = [...new Map(PC.slice().sort((a, b) => a.comp_sort - b.comp_sort).map((r) => [r.competitor, r])).values()];
      const cell = (g, c) => { const r = PC.find((q) => q.pricing_group === g && q.competitor === c); if (!r) return NA; const w = { pricing_group: g, competitor: c }; return '<b class="' + cls(r.ad_index - 1, false) + '">' + V('pr_index_comp', 'ad_index', w, idx(r.ad_index)) + '</b><span class="sm">' + V('pr_index_comp', 'ad_index_wow', w, sidx(r.ad_index_wow)) + ' WoW · ' + V('pr_index_comp', 'matched_skus', w, num(r.matched_skus, 0)) + ' SKUs</span>'; };
      let ct = tbl('pr_index_comp', 'competitor', [{ f: 'competitor', h: 'Against' }, ...G.map((g) => ({ f: 'ad_index', h: g, v: (r) => cell(g, r.competitor) }))], comps);
      const hl = '<tr class="tot" data-key="cheapest"><td>Cheapest of the four (headline)</td>' + I.map((r) => '<td>' + V('pr_index', 'ad_index', { pricing_group: r.pricing_group }, idx(r.ad_index)) + '<span class="sm">' + V('pr_index', 'ad_index_wow', { pricing_group: r.pricing_group }, sidx(r.ad_index_wow)) + ' WoW</span></td>').join('') + '</tr>';
      ct = ct.replace(/<\/tbody><\/table><\/div>$/, hl + '</tbody></table></div>');
      h += card('Index by competitor', 'Each cell compares our Auto Delivery price with that one competitor on the SKUs both sell, weighted the same way as the headline. Above 1.000 we are dearer. Against any single competitor we usually sit lower than the headline, because the headline takes the cheapest of the four on every SKU.', ct, ' style="margin-top:var(--cds-gap-md)"');
    } else h += state('pr_index_comp');
    h += '<p class="note">Index = our Auto Delivery price divided by the cheapest Auto Delivery price in market (Petbarn, Petstock, PetO, Budget Pet Products; Amazon AU carries no AD price), revenue-weighted on trailing 12-week sales, on SKUs where both prices exist on the Sunday snapshot. KVI, Core and Tail are the multi-track pricing groups. Source: the warehouse competitor price feed. Levels read a little higher than the category team’s report on the same feed - this build matches about 5% more SKUs and some scrapes compare different pack sizes - so read the week-on-week movement with more weight than the level.</p>';

    h += sec('2', 'By category - where a price move would matter most');
    const books = [...BOOKS, ...(S.some((r) => r.book === 'Unmapped') ? ['Unmapped'] : [])];
    for (const bk of books) {
      const R = S.filter((r) => r.book === bk).sort((a, b) => (a.sub_category === 'Total') - (b.sub_category === 'Total') || a.sort - b.sort);
      if (!R.length) continue;
      const tr = R.find((r) => r.sub_category === 'Total');
      h += card(esc(bk) + (tr ? ' <span class="pc-sub">(' + V('pr_subcats', 'revenue_at_risk', { book: bk, sub_category: 'Total' }, money(tr.revenue_at_risk)) + ' at risk, ' + V('pr_subcats', 'share_of_risk', { book: bk, sub_category: 'Total' }, pct(tr.share_of_risk, 0)) + ' of the total)</span>' : ''), '', tbl('pr_subcats', 'book,sub_category', [{ f: 'sub_category', h: 'Sub-category', v: (r) => (r.sub_category === 'Total' ? esc(bk) + ' total' : esc(r.sub_category)) }, { f: 'ad_index', h: 'AD index', v: (r) => idx(r.ad_index), c: (r) => (r.ad_index > 1 ? 'neg' : 'pos') }, { f: 'skus_above', h: 'SKUs above market', v: (r) => num(r.skus_above, 0) + ' / ' + num(r.skus_matched, 0) }, { f: 'kvi_above', h: 'Of which KVI', v: (r) => num(r.kvi_above, 0) }, { f: 'revenue_at_risk', h: 'Revenue at risk', v: (r) => dollars(r.revenue_at_risk) }, { f: 'share_of_risk', h: 'Share of risk', v: (r) => pct(r.share_of_risk) }], R, { rowCls: (r) => (r.sub_category === 'Total' ? 'tot' : '') }), ' style="margin-bottom:var(--cds-gap-md)"');
    }
    h += '<p class="note">Revenue at risk = last week’s revenue on SKUs where our Auto Delivery price sits above the cheapest in market. It is exposure, not lost margin - it sizes where a price move would matter most.</p>';

    h += sec('3', 'KVI irritants');
    if (ok('pr_irritants')) {
      const K = rows('pr_irritants'), k0 = K[0];
      if (k0) h += '<p class="lede">' + V('pr_irritants', 'n_lines', { sort: k0.sort }, k0.n_lines) + ' KVI lines sit above the cheapest price in market, carrying ' + V('pr_irritants', 'revenue_total', { sort: k0.sort }, money(k0.revenue_total)) + ' of last week’s revenue; ' + V('pr_irritants', 'n_12w_plus', { sort: k0.sort }, k0.n_12w_plus) + ' have been out of policy for twelve weeks or more.</p>';
      h += card('', 'KVI SKUs priced above the cheapest in market, ranked by consecutive weekly snapshots out of policy (looking back up to 26 weeks; one in-policy Sunday resets the streak). Reason codes such as competitor promotion or margin floor live in Reactev and are not in the warehouse.', tbl('pr_irritants', 'sort', [{ f: 'sku_name', h: 'SKU', v: (r) => esc(r.sku_name) + '<span class="sm">' + esc(r.brand) + ' · ' + esc(r.book) + '</span>' }, { f: 'our_ad_price', h: 'Our AD price', v: (r) => money(r.our_ad_price) }, { f: 'cheapest_price', h: 'Cheapest in market', v: (r) => money(r.cheapest_price) }, { f: 'cheapest_competitor', h: 'Where' }, { f: 'gap_pct', h: 'Gap', v: (r) => '+' + (+r.gap_pct).toFixed(1) + '%', c: () => 'neg' }, { f: 'revenue_lw', h: 'Revenue (LW)', v: (r) => dollars(r.revenue_lw) }, { f: 'weeks_out', h: 'Weeks out', v: (r) => r.weeks_out + (r.weeks_out_capped ? '+' : '') }], K));
    } else h += state('pr_irritants');

    h += sec('4', 'Discounts and supplier funding');
    if (ok('pr_discounts')) {
      const Dd = rows('pr_discounts'), dt = Dd.find((r) => r.book === 'Total');
      if (dt) { const dv = (f, fmt) => V('pr_discounts', f, { book: 'Total' }, fmt(dt[f])); h += '<p class="lede">Customers received ' + dv('total_discount', money) + ' of discounts this week, ' + dv('discount_pct', pct) + ' of gross revenue and ' + dv('discount_vs_ly_pct', frac) + ' on the same week last year. Without them product margin would have been ' + dv('pm_pct_ex_discount', pct) + ' against ' + dv('pm_pct', pct) + ' actual. Supplier co-funding recovers ' + dv('cofund_recovery_pct', pct) + ' of the temporary price discount.</p>'; }
      h += card('Discount and funding waterfall by book', 'Product revenue (as on Commercial) is gross revenue less the temporary price discount (TPD). The Auto Delivery recurring discount, AD incentive, price match, coupons and other discounts are given after that and sit outside product revenue.', tbl('pr_discounts', 'book', [{ f: 'book', h: 'Book' }, { f: 'gross_revenue', h: 'Gross revenue', v: (r) => money(r.gross_revenue) }, { f: 'tpd_discount', h: 'TPD', v: (r) => money(r.tpd_discount) }, { f: 'product_revenue', h: 'Product revenue', v: (r) => money(r.product_revenue) }, { f: 'ad_recurring_discount', h: 'AD recurring', v: (r) => money(r.ad_recurring_discount) }, { f: 'ad_incentive_discount', h: 'AD incentive', v: (r) => money(r.ad_incentive_discount) }, { f: 'price_match_discount', h: 'Price match', v: (r) => money(r.price_match_discount) }, { f: 'coupon_discount', h: 'Coupons', v: (r) => money(r.coupon_discount) }, { f: 'other_discount', h: 'Other', v: (r) => money(r.other_discount) }, { f: 'total_discount', h: 'Total discount', v: (r) => money(r.total_discount) }, { f: 'discount_pct', h: '% of gross', v: (r) => pct(r.discount_pct) }, { f: 'cofunding', h: 'TPD co-funding', v: (r) => money(r.cofunding) }, { f: 'pm_pct', h: 'PM %', v: (r) => pct(r.pm_pct) }, { f: 'pm_pct_ex_discount', h: 'PM % without discounts', v: (r) => pct(r.pm_pct_ex_discount) }], Dd, { rowCls: (r) => (r.book === 'Total' ? 'tot' : '') }));
      h += '<p class="note">PM % without discounts adds back every customer-facing discount, so the gap to actual is the full margin cost of discounting. Earlier reports quoted a smaller drag because they treated product revenue as already net of the Auto Delivery discount; the line data shows it is not. Co-funding counts temporary price discount funding only, not Auto Delivery rebates, so read it as a floor.</p>';
    } else h += state('pr_discounts');

    h += sec('5', 'Price match');
    const pm = one('pr_price_match');
    if (pm) { const pv = (f, fmt) => V('pr_price_match', f, null, fmt(pm[f])); h += '<div class="grid tiles">' + tile('Price-match discount', pv('price_match_discount', money), 'on ' + pv('orders_with_price_match', num) + ' orders (' + pv('share_of_orders', (v) => pct(v, 2)) + ' of all orders)', pill('vs LW', pv('vs_lw_pct', frac), cls(pm.vs_lw_pct, false)) + pill('vs 12wk', pv('vs_l12w_pct', frac), cls(pm.vs_l12w_pct, false))) + tile('Average match per order', pv('avg_match_per_order', money), '') + tile('Most-matched competitor', pv('top_competitor', esc), pv('top_competitor_share', pct) + ' of price-match value, across ' + pv('competitors_matched', num) + ' competitors named') + '</div>'; }
    else h += state('pr_price_match');
    h += ph('Still to shape with James and Nihan', 'Content the feedback left open for this tab.', ['Discount depth and realised price index by category, week on week.', 'Price changes made this week and their early read on volume.', 'Reason codes for KVI lines held above market, once Reactev data lands in the warehouse.'], 'Agree the content first; the price and discount data is already in the warehouse.');
    return h;
  }
  function prSpark(el) {
    const g = el.dataset.prspark; const R = rows('pr_index_trend').filter((r) => r.pricing_group === g).sort((a, b) => (a.snapshot_date < b.snapshot_date ? -1 : 1));
    el.querySelectorAll('svg').forEach((s) => s.remove());
    if (R.length < 2 || !el.clientWidth) return;
    const W = el.clientWidth, H = 38, vals = R.map((r) => +r.ad_index);
    const x = d3.scaleLinear([0, R.length - 1], [3, W - 3]), y = d3.scaleLinear(d3.extent(vals), [H - 4, 4]);
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    const mean = d3.mean(vals);
    svg.append('line').attr('x1', 0).attr('x2', W).attr('y1', y(mean)).attr('y2', y(mean)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '3 3');
    svg.append('path').attr('d', d3.line((d, i) => x(i), (d) => y(d))(vals)).attr('fill', 'none').attr('stroke', PCC[0]).attr('stroke-width', 2).attr('stroke-linecap', 'round').attr('stroke-linejoin', 'round');
    svg.append('circle').attr('cx', x(R.length - 1)).attr('cy', y(vals[vals.length - 1])).attr('r', 3).attr('fill', PCC[0]);
    const dot = svg.append('circle').attr('r', 3.5).attr('fill', PCC[0]).attr('stroke', 'var(--color-panel)').attr('stroke-width', 2).style('display', 'none');
    const tp = tipFor(el);
    svg.append('rect').attr('width', W).attr('height', H).attr('fill', 'transparent').on('mousemove', (ev) => { const [mx] = d3.pointer(ev); const i = Math.max(0, Math.min(R.length - 1, Math.round(x.invert(mx)))); dot.style('display', null).attr('cx', x(i)).attr('cy', y(vals[i])); tp.innerHTML = '<span class="k">' + esc(g) + ' · ' + dateLabel(R[i].snapshot_date) + '</span><br>Index ' + idx(vals[i]); place(el, tp, x(i), y(vals[i])); }).on('mouseleave', () => { dot.style('display', 'none'); tp.style.display = 'none'; });
  }
  function prChart(el) {
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = rows('pr_index_trend');
    if (!R.length || !el.clientWidth) return;
    const groups = rows('pr_index').map((r) => r.pricing_group);
    const dates = [...new Set(R.map((r) => r.snapshot_date))].sort();
    const W = el.clientWidth, H = 220, m = { t: 12, r: 12, b: 26, l: 48 };
    const x = d3.scalePoint(dates, [m.l, W - m.r]);
    const ext = d3.extent([1, ...R.map((r) => +r.ad_index)]);
    const y = d3.scaleLinear([ext[0] - 0.01, ext[1] + 0.01], [H - m.b, m.t]).nice();
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    svg.append('g').attr('transform', 'translate(0,' + (H - m.b) + ')').call(d3.axisBottom(x).tickFormat((d) => dateLabel(d)).tickSizeOuter(0)).call(noAxisFont).call((g) => g.selectAll('.tick text').attr('display', (d, i) => (W < 700 && i % 2 ? 'none' : null)));
    svg.append('g').attr('transform', 'translate(' + m.l + ',0)').call(d3.axisLeft(y).ticks(5).tickFormat((v) => v.toFixed(2))).call(noAxisFont).call((g) => g.select('.domain').remove());
    svg.append('line').attr('x1', m.l).attr('x2', W - m.r).attr('y1', y(1)).attr('y2', y(1)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '4 3');
    groups.forEach((g, i) => { const pts = dates.map((d) => R.find((r) => r.snapshot_date === d && r.pricing_group === g)).filter(Boolean); svg.append('path').attr('d', d3.line((r) => x(r.snapshot_date), (r) => y(r.ad_index))(pts)).attr('fill', 'none').attr('stroke', PCC[i]).attr('stroke-width', 2).attr('stroke-linecap', 'round').attr('stroke-linejoin', 'round'); });
    const rule = svg.append('line').attr('y1', m.t).attr('y2', H - m.b).attr('stroke', 'var(--cds-chart-axis)').style('display', 'none');
    const tp = tipFor(el);
    svg.append('rect').attr('x', m.l).attr('y', m.t).attr('width', W - m.l - m.r).attr('height', H - m.t - m.b).attr('fill', 'transparent')
      .on('mousemove', (ev) => { const [mx, my] = d3.pointer(ev, el); const d = dates.reduce((a, b) => (Math.abs(x(b) - mx) < Math.abs(x(a) - mx) ? b : a)); rule.style('display', null).attr('x1', x(d)).attr('x2', x(d)); tp.innerHTML = '<span class="k">' + dateLabel(d) + '</span><br>' + groups.map((g, i) => { const r = R.find((q) => q.snapshot_date === d && q.pricing_group === g); return '<i style="display:inline-block;width:8px;height:8px;border-radius:2px;background:' + PCC[i] + '"></i> ' + esc(g) + ' ' + (r ? idx(r.ad_index) : NA); }).join('<br>'); place(el, tp, x(d), my); })
      .on('mouseleave', () => { rule.style('display', 'none'); tp.style.display = 'none'; });
  }

  // ================= CX =================
  dash.calc('cx_contacts_worm', {
    inputs: ['cx_contacts_weekly', 'cx_contacts'],
    title: 'Contacts 13-week trend',
    description: 'Weekly contacts, contact rate per 1,000 closed orders and Luna share for the last 13 weeks, with the latest week taken from the headline tiles so each worm ends on its tile figure.',
    fn: (cx_contacts_weekly, cx_contacts) => {
      const k = cx_contacts[0] || {};
      return cx_contacts_weekly.map((r) => (r.week_end === k.week_end
        ? { week_end: r.week_end, contacts: +k.contacts_tw, per_1k_orders: +k.per_1k_orders_tw, ai_engaged_pct: +k.ai_engaged_pct }
        : { week_end: r.week_end, contacts: +r.contacts, per_1k_orders: +r.per_1k_orders, ai_engaged_pct: +r.ai_engaged_pct }))
        .sort((a, b) => (a.week_end < b.week_end ? -1 : 1));
    },
  });
  dash.calc('cx_csat_worm', {
    inputs: ['cx_csat_handler_weekly', 'cx_csat_handler'],
    title: 'CSAT 13-week trend by handler',
    description: 'Weekly CSAT and ratings for each handler over the last 13 weeks, with the latest week and the 13-week level taken from the CSAT tiles so each worm agrees with its tile.',
    fn: (cx_csat_handler_weekly, cx_csat_handler) => cx_csat_handler_weekly.map((r) => {
      const t = cx_csat_handler.find((h) => h.handler === r.handler) || {};
      const latest = r.week_end === t.week_end;
      return { week_end: r.week_end, handler: r.handler, ratings: latest ? +t.ratings_tw : +r.ratings, csat_pct: latest ? (t.ratings_tw ? +t.csat_pct_tw : null) : +r.csat_pct, csat_pct_13w: +t.csat_pct_13w };
    }).sort((a, b) => (a.handler === b.handler ? (a.week_end < b.week_end ? -1 : 1) : (a.handler < b.handler ? -1 : 1))),
  });
  function rCX() {
    const t = T.cx;
    let h = ptitle(t);
    h += '<div class="decision"><b>Provisional figures:</b> the CX numbers on this tab are provisional. They are built from the Gladly data held in the warehouse, so they will differ from CX numbers extracted directly from Gladly. Functionality to reduce the gap is being built.</div>';
    const need = ['cx_nps', 'cx_nps_weekly'];
    if (!ready(need)) return h + state(need);
    const n = one('cx_nps'), nv = (f, fmt) => V('cx_nps', f, null, fmt(n[f]));
    const dr = ok('cx_driver') ? one('cx_driver') : null;
    const TH = ok('cx_themes') ? rows('cx_themes') : [];
    const good = [], watch = [];
    (n.nps_vs_target >= 0 ? good : watch).push('<b>NPS ' + nv('nps', (v) => num(v, 1)) + '</b> over 13 weeks, ' + nv('nps_vs_target', (v) => snum(v, 1)) + ' against the target of ' + nv('target', (v) => num(v, 0)) + '.');
    (n.last4_vs_window >= 0 ? good : watch).push('Last four weeks <b>' + nv('last4_nps', (v) => num(v, 1)) + '</b>, ' + nv('last4_vs_window', (v) => snum(v, 1)) + ' against the 13-week window.');
    if (dr) watch.push('<b>' + V('cx_driver', 'theme', null, esc(dr.theme)) + '</b> over-indexes ' + V('cx_driver', 'over_index', null, num(dr.over_index, 1) + 'x') + ' among at-risk customers, with ' + V('cx_driver', 'actionable_pct', null, dr.actionable_pct + '%') + ' of its comments pointing to a specific fix.');
    const ps = TH.filter((r) => r.call === 'Protected strength').sort((a, b) => b.comments - a.comments)[0];
    if (ps) good.push('<b>' + V('cx_themes', 'theme', { code: ps.code }, esc(ps.theme)) + '</b> is the most-mentioned strength: ' + V('cx_themes', 'comments', { code: ps.code }, num(ps.comments, 0)) + ' comments, ' + V('cx_themes', 'promoter_rate', { code: ps.code }, num(ps.promoter_rate, 1)) + ' per 100 promoter comments.');
    h += hlBoxes(good, watch, 'Derived from this tab’s own figures, not curated commentary. Everything here is a rolling 13-week window: at about 110 responses a week a single week carries roughly plus or minus 6 points.');

    h += sec('1', 'Net promoter score');
    const band = (lab, f, pf, foot) => tile(lab, nv(f, (v) => num(v, 0)), nv(pf, (v) => pct(v, 1)) + ' of responses, ' + foot);
    h += '<div class="grid tiles">' + tile('NPS, this week', nv('tw_nps', (v) => num(v, 1)), 'on ' + nv('tw_n', (v) => num(v, 0)) + ' responses; 13 weeks ' + nv('nps', (v) => num(v, 1)), pill('vs target', nv('tw_vs_target', (v) => snum(v, 1)), cls(n.tw_vs_target)) + pill('vs LW', nv('tw_vs_lw', (v) => snum(v, 1)), cls(n.tw_vs_lw)) + pill('vs 12wk', nv('tw_vs_l12', (v) => snum(v, 1)), cls(n.tw_vs_l12))) + band('Promoters', 'tw_promoters', 'tw_promoter_pct', 'scoring 9 or 10') + band('Passives', 'tw_passives', 'tw_passive_pct', 'scoring 7 or 8') + band('Detractors', 'tw_detractors', 'tw_detractor_pct', 'scoring 0 to 6') + '</div>';
    const segs = [['Promoters', 'tw_promoter_pct', 'var(--pc-c1)'], ['Passives', 'tw_passive_pct', 'var(--pc-lav)'], ['Detractors', 'tw_detractor_pct', 'var(--pc-neg)']];
    h += '<div class="card" style="margin-top:var(--cds-gap-md)"><div class="bandbar">' + segs.map(([l, f, c]) => '<span style="width:' + (+n[f]) + '%;background:' + c + '" title="' + l + ' ' + pct(n[f]) + '"></span>').join('') + '</div><div class="legend">' + segs.map(([l, f, c]) => '<span><i style="background:' + c + '"></i>' + l + ' ' + nv(f, (v) => pct(v, 1)) + '</span>').join('') + '</div>' +
      '<p class="note">The tiles and bar are for the reporting week, ' + nv('tw_start', dateLabel) + ' to ' + nv('week_end', dateLabel) + '. vs 12wk compares with the 12 weeks before it pooled (' + nv('l12_nps', (v) => num(v, 1)) + ' on ' + nv('l12_n', (v) => num(v, 0)) + ' responses); at about 110 responses a week, a single week moves by roughly plus or minus 6 points on sampling alone. The 13-week figure (' + nv('window_start', dateLabel) + ' to ' + nv('window_end', dateLabel) + ') is shown for context. NPS is promoters less detractors as a share of responses, from the pre-scored bands in the warehouse. The bands are on all responses; the themes below are on the ' + nv('comments', (v) => num(v, 0)) + ' that left a comment. The target of ' + nv('target', (v) => num(v, 0)) + ' is held in this tab’s query because the warehouse has no NPS target.</p></div>';
    h += card('Weekly NPS across the window', 'Read the level, not the week-to-week step - a single week’s base is too thin to be a signal on its own. Hover for the response count.', '<div class="legend"><span><i style="background:' + PCC[0] + '"></i>NPS</span><span><i style="background:var(--cds-chart-reference)"></i>Target</span></div><div class="chart" id="ch-cxweekly" data-source="cx_nps_weekly"></div>', ' style="margin-top:var(--cds-gap-md)"');

    h += sec('2', 'What the comments say');
    if (dr) {
      const dv = (f, fmt) => V('cx_driver', f, null, fmt(dr[f]));
      h += '<p class="lede"><b>' + dv('theme', esc) + '</b> is the theme most over-represented among at-risk customers with material volume, at ' + dv('over_index', (v) => num(v, 1) + 'x') + ': ' + dv('at_risk_rate', (v) => num(v, 1)) + ' mentions per 100 at-risk comments against ' + dv('promoter_rate', (v) => num(v, 1)) + ' per 100 promoter comments. ' + dv('neg_pct', (v) => v + '%') + ' of its comments read negative and ' + dv('actionable_pct', (v) => v + '%') + ' point to a specific fix. Its weekly mention rate moves ' + (dr.r_vs_nps < 0 ? 'opposite to' : 'with') + ' NPS across the window at r = ' + dv('r_vs_nps', (v) => (+v).toFixed(2).replace('-', MINUS)) + ', directional on ' + dv('weeks', (v) => v) + ' points and not a causal claim. The rate in the last six weeks is ' + dv('second_half_rate', (v) => num(v, 1)) + ' per 100 comments against ' + dv('first_half_rate', (v) => num(v, 1)) + ' in the first six.</p>';
    }
    h += card('Themes ranked by over-index against promoter comments', '<span class="legend"><span><i style="background:var(--pc-pol-neg)"></i>Negative</span><span><i style="background:var(--pc-pol-mix)"></i>Mixed</span><span><i style="background:var(--pc-c1)"></i>Positive</span><span>Polarity mix = share of each theme’s comments by what the customer wrote</span></span>', tbl('cx_themes', 'code', [
      { f: 'theme', h: 'Theme' }, { f: 'at_risk_n', h: 'At-risk n', v: (r) => num(r.at_risk_n, 0) }, { f: 'at_risk_rate', h: 'Per 100', v: (r) => num(r.at_risk_rate, 1) },
      { f: 'promoter_n', h: 'Promoter n', v: (r) => num(r.promoter_n, 0) }, { f: 'promoter_rate', h: 'Per 100', v: (r) => num(r.promoter_rate, 1) },
      { f: 'over_index', h: 'Over-index', v: (r) => (isN(r.over_index) ? num(r.over_index, 1) + 'x' : 'at-risk only'), c: (r) => (r.over_index === null || r.over_index > 1 ? 'neg' : r.over_index < 0.8 ? 'pos' : 'flat') },
      { f: 'neg_pct', h: 'Polarity mix', v: (r) => { const n = +r.neg_pct || 0, m = +r.mixed_pct || 0, p = Math.max(0, 100 - n - m); return '<div class="polbar" role="img" aria-label="' + n + '% negative, ' + m + '% mixed, ' + p + '% positive" title="' + n + '% negative, ' + m + '% mixed, ' + p + '% positive"><span style="width:' + n + '%;background:var(--pc-pol-neg)"></span><span style="width:' + m + '%;background:var(--pc-pol-mix)"></span><span style="width:' + p + '%;background:var(--pc-c1)"></span></div>'; } }, { f: 'actionable_pct', h: 'Actionable', v: (r) => r.actionable_pct + '%' },
      { f: 'comments', h: 'Comments', v: (r) => num(r.comments, 0) }, { f: 'call', h: 'Call', v: (r) => esc(r.call) }], TH));
    if (dr) h += '<p class="note">At-risk pools detractors and passives (' + V('cx_driver', 'at_risk_comments', null, num(dr.at_risk_comments, 0)) + ' comments) because passives read like detractors on content, and pooling lifts the base enough to carry a theme split. Promoter base ' + V('cx_driver', 'promoter_comments', null, num(dr.promoter_comments, 0)) + '. Over-index is the at-risk mention rate divided by the promoter mention rate: above 1.0 a theme drives dissatisfaction, below 1.0 it drives advocacy. Read it with the comment count - a theme can top the ranking on a handful of comments, so only themes with ' + V('cx_driver', 'material_min', null, dr.material_min) + ' or more comments become a priority; smaller ones above 1.0 are marked Watch, 0.8 to 1.0 Neutral and below 0.8 Protected strength. Each comment counts once, on its main theme. Polarity is judged on what the customer wrote, not on the score, which is how a complaint inside a 9 or 10 is caught. Delivery speed and delivery execution are separate codes - merged, they average two opposite signals. Themes are coded by Claude each Monday against a fixed rubric (about 85% agreement with the original hand-checked coding on a blind sample); it is an analytical classification, not a governed warehouse metric.</p>';

    h += '<div class="grid wide" style="margin-top:var(--cds-gap-md)">';
    if (ok('cx_clusters')) {
      const C = rows('cx_clusters'), shown = C.filter((r) => r.code !== 'ONE_OFF'), tail = C.find((r) => r.code === 'ONE_OFF'), mx = Math.max(0, ...shown.map((r) => +r.share_of_neg || 0));
      h += card('Where the negative comments cluster', '', tbl('cx_clusters', 'code', [{ f: 'cluster', h: 'Sub-issue' }, { f: 'share_of_neg', h: 'Share of negative comments', v: (r) => '<div class="hbar" title="' + pct(r.share_of_neg) + ' of negative and mixed comments"><span style="width:' + (mx ? (100 * r.share_of_neg / mx).toFixed(1) : 0) + '%"></span></div>' }, { f: 'comments', h: 'Comments', v: (r) => num(r.comments, 0) }], shown) + '<p class="note">Negative and mixed comments only' + (dr ? ' (' + V('cx_driver', 'neg_mixed_comments', null, num(dr.neg_mixed_comments, 0)) + ' of ' + V('cx_driver', 'coded_comments', null, num(dr.coded_comments, 0)) + ')' : '') + ', each comment’s generic sub-issue folded into a named cluster.' + (tail ? ' A further ' + V('cx_clusters', 'share_of_neg', { code: 'ONE_OFF' }, pct(tail.share_of_neg)) + ' sit in a long tail of one-off sub-issues and are not shown.' : '') + '</p>');
    } else h += state('cx_clusters');
    if (ok('cx_segments')) {
      const S = rows('cx_segments').sort((a, b) => a.sort - b.sort);
      h += card('NPS by order mode and customer status', '', tbl('cx_segments', 'segment', [{ f: 'segment', h: 'Segment' }, { f: 'n', h: 'Responses', v: (r) => num(r.n, 0) }, { f: 'nps', h: 'NPS', v: (r) => (r.suppressed ? 'under 50' : num(r.nps, 1)) }], S) + '<p class="note">On the order the survey was sent against. Read Auto Delivery here next to the Auto Delivery tab rather than on its own. Cells under 50 responses are suppressed.</p>');
    } else h += state('cx_segments');
    h += '</div>';

    h += sec('3', 'Contacts by contact reason');
    if (ready(['cx_contacts', 'cx_contact_reasons'])) {
      const k = one('cx_contacts'), kv = (f, fmt) => V('cx_contacts', f, null, fmt(k[f]));
      const CR = rows('cx_contact_reasons');
      const worm = (html, f) => html.replace(/<\/div>$/, '<div class="spark" data-cxspark="' + f + '" data-source="cx_contacts_worm"></div></div>');
      h += '<div class="grid tiles">' + worm(tile('Contacts this week', kv('contacts_tw', (v) => num(v, 0)), 'valid inbound contacts; last week ' + kv('contacts_lw', (v) => num(v, 0)), pill('vs 12wk', kv('contacts_vs_avg12_pct', frac), cls(k.contacts_vs_avg12_pct, false))), 'contacts') +
        worm(tile('Contact rate per 1,000 closed orders', kv('per_1k_orders_tw', (v) => num(v, 1)), 'on ' + kv('orders_tw', (v) => num(v, 0)) + ' closed orders; 12-week rate ' + kv('per_1k_orders_avg12', (v) => num(v, 1)), pill('vs 12wk', kv('d_per_1k_vs_avg12', (v) => snum(v, 1)), cls(k.d_per_1k_vs_avg12, false))), 'per_1k_orders') +
        worm(tile('Engaged by Luna', kv('ai_engaged_pct', (v) => pct(v, 1)), 'of conversations the Gladly AI assistant took part in'), 'ai_engaged_pct') + '</div>';
      const mv = CR.filter((r) => isN(r.d_avg12)).slice().sort((a, b) => b.d_avg12 - a.d_avg12);
      const up = mv.filter((r) => r.d_avg12 > 0).slice(0, 3), dn = mv.filter((r) => r.d_avg12 < 0).reverse().slice(0, 3);
      const mvTxt = (r) => V('cx_contact_reasons', 'reason', { reason: r.reason }, esc(r.reason)) + ' ' + V('cx_contact_reasons', 'd_avg12', { reason: r.reason }, snum(r.d_avg12, 0)) + ' (' + V('cx_contact_reasons', 'pct_vs_avg12', { reason: r.reason }, frac(r.pct_vs_avg12, 0)) + ')';
      h += '<p class="lede" style="margin-top:var(--cds-gap-md)"><b>Moving most against the 12-week average.</b> Up: ' + (up.map(mvTxt).join('; ') || 'none') + '. Down: ' + (dn.map(mvTxt).join('; ') || 'none') + '.</p>';
      const mx = Math.max(0, ...CR.map((r) => +r.share_tw || 0));
      h += card('Contacts by reason - week ending ' + dateLabel(k.week_end), '', tbl('cx_contact_reasons', 'reason', [
        { f: 'reason', h: 'Reason', v: (r) => esc(r.reason) + '<span class="sm">' + esc(r.reason_group) + '</span>' },
        { f: 'share_tw', h: 'Share of contacts', v: (r) => '<div class="hbar" title="' + pct(r.share_tw) + ' of contacts"><span style="width:' + (mx ? (100 * r.share_tw / mx).toFixed(1) : 0) + '%;background:var(--pc-c1)"></span></div>' },
        { f: 'tw', h: 'This week', v: (r) => num(r.tw, 0) + '<span class="sm">' + pct(r.share_tw) + '</span>' },
        { f: 'avg12', h: '12-wk avg', v: (r) => num(r.avg12, 0) },
        { f: 'pct_vs_avg12', h: 'Vs 12-wk avg', v: (r) => frac(r.pct_vs_avg12, 0) + '<span class="sm">' + snum(r.d_avg12, 0) + '</span>', c: (r) => cls(r.pct_vs_avg12, false) },
        { f: 'per_1k_orders_tw', h: 'Per 1k closed orders', v: (r) => num(r.per_1k_orders_tw, 1) }], CR.slice().sort((a, b) => b.tw - a.tw)) +
        '<p class="note">Worms = the last 13 weeks of each tile on its own scale, with the 13-week average dashed; hover for the weekly figure. Contacts and the contact rate are the governed Contact Rate measures: inbound Gladly contacts started in the week, less those abandoned within 10 seconds, per 1,000 customer orders closed. They count customer demand, including contacts Luna handles, so they differ from Looker\'s contacts fulfilled (those an agent responded to). The reason table counts conversations - one conversation can hold several contacts. Reasons come from the topics agents tag, rolled up to these reasons by a fixed mapping that leaves out process tags (survey suppression, data collection, escalation routing, spam, social and WOW moments); a conversation with several topics counts once under each of its reasons, so the reasons add to more than the total. More is shown in red because contacts are a cost and usually a symptom. Returns tagging changed in early August (one return topic retired), so its 12-week average still carries the old tagging and overstates the drop.</p>');
    } else h += state(['cx_contacts', 'cx_contact_reasons']);

    h += sec('4', 'CSAT by channel, and Luna versus a person');
    if (ready(['cx_csat_handler', 'cx_csat_channel'])) {
      const HD = rows('cx_csat_handler'), hr = (k) => HD.find((r) => r.handler === k);
      const lo = hr('Luna only'), lp = hr('Luna then a person'), po = hr('Person only'), al = hr('All');
      const CH = rows('cx_csat_channel'), cr = (c, g) => CH.find((r) => r.channel === c && r.handler_group === g);
      const wp = cr('All channels', 'With a person');
      const hv = (r, f, fmt) => V('cx_csat_handler', f, { handler: r.handler }, fmt(r[f]));
      const csatTxt = (r, f, nf) => (r[nf] ? pct(r[f], 1) : NA);
      if (lo && wp) h += '<p class="lede">Luna handled ' + hv(lo, 'conv_share_tw', (v) => pct(v, 1)) + ' of conversations end to end this week (' + hv(lo, 'conv_share_13w', (v) => pct(v, 1)) + ' across the 13 weeks). Where Luna resolved alone, ' + hv(lo, 'csat_pct_13w', (v) => pct(v, 1)) + ' of customers rated it 4 or 5, against ' + V('cx_csat_channel', 'csat_pct_13w', { channel: 'All channels', handler_group: 'With a person' }, pct(wp.csat_pct_13w, 1)) + ' when a person handled the conversation, with or without Luna first.</p>';
      const htile = (r, label, foot) => tile(label, hv(r, 'csat_pct_13w', (v) => (r.ratings_13w ? pct(v, 1) : NA)), hv(r, 'ratings_13w', (v) => num(v, 0)) + ' ratings over 13 weeks (' + hv(r, 'response_rate_13w', (v) => pct(v, 1)) + ' response); ' + hv(r, 'conv_share_13w', (v) => pct(v, 1)) + ' of conversations' + (foot || ''), r.ratings_tw && !r.suppressed_tw ? pill('this week', hv(r, 'csat_pct_tw', (v) => pct(v, 1)), 'flat') : '');
      const cworm = (html, g) => html.replace(/<\/div>$/, '<div class="spark" data-csatspark="' + esc(g) + '" data-source="cx_csat_worm"></div></div>');
      h += '<div class="grid tiles">' + (lo ? cworm(htile(lo, 'Luna only · CSAT'), 'Luna only') : '') + (lp ? cworm(htile(lp, 'Luna then a person · CSAT'), 'Luna then a person') : '') + (po ? cworm(htile(po, 'Person only · CSAT', '; mostly phone, since email is rarely surveyed'), 'Person only') : '') + (al ? cworm(tile('All conversations · CSAT', hv(al, 'csat_pct_13w', (v) => pct(v, 1)), hv(al, 'ratings_13w', (v) => num(v, 0)) + ' ratings over 13 weeks (' + hv(al, 'response_rate_13w', (v) => pct(v, 1)) + ' response)', al.ratings_tw && !al.suppressed_tw ? pill('this week', hv(al, 'csat_pct_tw', (v) => pct(v, 1)), 'flat') : ''), 'All') : '') + '</div>';
      h += '<p class="note">Worms = weekly CSAT for the last 13 weeks, with the 13-week CSAT on the tile dashed. Hover for the weekly figure and rating count; weeks with fewer than 30 ratings are marked indicative there. The latest week is still collecting ratings.</p>';
      const chans = [...new Set(CH.map((r) => r.channel))].filter((c) => CH.some((r) => r.channel === c && r.ratings_13w > 0));
      const cell = (c, g) => { const r = cr(c, g); if (!r || !r.ratings_13w) return '<td class="flat">no ratings</td>'; const w = { channel: c, handler_group: g }; return '<td>' + (r.suppressed_13w ? '<span class="flat">' + V('cx_csat_channel', 'csat_pct_13w', w, pct(r.csat_pct_13w, 0)) + '</span>' : V('cx_csat_channel', 'csat_pct_13w', w, pct(r.csat_pct_13w, 1))) + '<span class="sm">' + V('cx_csat_channel', 'ratings_13w', w, num(r.ratings_13w, 0)) + (r.ratings_13w === 1 ? ' rating' : ' ratings') + (r.suppressed_13w ? ', too few to read' : '') + '</span></td>'; };
      let t = '<div class="tw" data-source="cx_csat_channel"><table class="t"><thead><tr><th>Channel</th><th>Luna only</th><th>With a person</th><th>All rated</th><th>Conversations</th></tr></thead><tbody>';
      for (const c of chans) { const a = cr(c, 'All rated'); t += '<tr' + (c === 'All channels' ? ' class="tot"' : '') + '><td>' + esc(c) + '</td>' + cell(c, 'Luna only') + cell(c, 'With a person') + cell(c, 'All rated') + '<td>' + (a ? num(a.conversations_13w, 0) : NA) + '</td></tr>'; }
      h += card('CSAT by channel - 13 weeks', 'CSAT is the share of post-conversation ratings scoring 4 or 5 out of 5. With a person covers conversations a person finished, whether or not Luna took part first. Grey figures rest on fewer than 30 ratings and should not be read on their own.', t + '</tbody></table></div>', ' style="margin-top:var(--cds-gap-md)"');
      if (ok('cx_csat_weekly')) {
        const W = rows('cx_csat_weekly'), wk = [...new Set(W.map((r) => r.week_start))].sort(), wr = (x, g) => W.find((r) => r.week_start === x && r.handler_group === g);
        const row = (lab, g, f, fmt) => '<tr><td>' + lab + '</td>' + wk.map((x) => { const r = wr(x, g); return '<td>' + (r && isN(r[f]) ? fmt(r[f], r) : NA) + '</td>'; }).join('') + '</tr>';
        const cfmt = (v, r) => (r.ratings < 30 ? '<span class="flat">' + pct(v, 0) + '</span>' : pct(v, 0));
        h += card('Weekly - Luna’s share and CSAT', 'Luna’s share is the share of all conversations that Luna finished without a person. Weekly CSAT rests on few ratings, so grey weeks (under 30 ratings) are indicative only; read the 13-week figures above for the level.', '<div class="tw" data-source="cx_csat_weekly"><table class="t"><thead><tr><th>Week commencing</th>' + wk.map((x) => '<th>' + dateLabel(x) + '</th>').join('') + '</tr></thead><tbody>' + row('Luna’s share of conversations', 'All', 'luna_only_share', (v) => pct(v, 1)) + row('CSAT, Luna only', 'Luna only', 'csat_pct', cfmt) + row('CSAT, with a person', 'With a person', 'csat_pct', cfmt) + row('Ratings received', 'All', 'ratings', (v) => num(v, 0)) + '</tbody></table></div>', ' style="margin-top:var(--cds-gap-md)"');
      } else h += state('cx_csat_weekly');
      h += '<p class="note">Source: Gladly conversations in the warehouse (cx__conversation). Luna is the Gladly AI assistant, identified by the agent Gladly Sidekick on the conversation; the rating is the customer’s score for the agent who finished the conversation. This is a different survey from the company NPS above and the two are never blended.</p>';
    } else h += state(['cx_csat_handler', 'cx_csat_channel']);
    h += '<p class="note">Source: the company NPS survey in the warehouse (customer__customer_review). Agent NPS on CX conversations is a different instrument with no bands or comments and is never blended in. Comment text carries personal details and never reaches this page: only theme codes and generic sub-issue words do.</p>';
    return h;
  }
  function cxChart(el) {
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = rows('cx_nps_weekly').slice().sort((a, b) => (a.week_start < b.week_start ? -1 : 1));
    if (!R.length || !el.clientWidth) return;
    const W = el.clientWidth, H = 220, m = { t: 12, r: 22, b: 26, l: 40 };
    const x = d3.scalePoint(R.map((r) => r.week_start), [m.l, W - m.r]);
    const tg = R[0].target;
    const ext = d3.extent([...(isN(tg) ? [tg] : []), ...R.map((r) => +r.nps)]);
    const y = d3.scaleLinear([ext[0] - 3, ext[1] + 3], [H - m.b, m.t]).nice();
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    svg.append('g').attr('transform', 'translate(0,' + (H - m.b) + ')').call(d3.axisBottom(x).tickFormat((d) => dateLabel(d)).tickSizeOuter(0)).call(noAxisFont).call((g) => g.selectAll('.tick text').attr('display', (d, i) => (W < 700 && i % 2 ? 'none' : null)));
    svg.append('g').attr('transform', 'translate(' + m.l + ',0)').call(d3.axisLeft(y).ticks(5)).call(noAxisFont).call((g) => g.select('.domain').remove());
    if (isN(tg)) svg.append('line').attr('x1', m.l).attr('x2', W - m.r).attr('y1', y(tg)).attr('y2', y(tg)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '4 3');
    svg.append('path').attr('d', d3.line((r) => x(r.week_start), (r) => y(r.nps))(R)).attr('fill', 'none').attr('stroke', PCC[0]).attr('stroke-width', 2).attr('stroke-linecap', 'round').attr('stroke-linejoin', 'round');
    svg.selectAll('circle.pt').data(R).join('circle').attr('class', 'pt').attr('cx', (r) => x(r.week_start)).attr('cy', (r) => y(r.nps)).attr('r', 2.5).attr('fill', PCC[0]);
    const rule = svg.append('line').attr('y1', m.t).attr('y2', H - m.b).attr('stroke', 'var(--cds-chart-axis)').style('display', 'none');
    const tp = tipFor(el);
    svg.append('rect').attr('x', m.l).attr('y', m.t).attr('width', W - m.l - m.r).attr('height', H - m.t - m.b).attr('fill', 'transparent')
      .on('mousemove', (ev) => { const [mx, my] = d3.pointer(ev, el); const r = R.reduce((a, b) => (Math.abs(x(b.week_start) - mx) < Math.abs(x(a.week_start) - mx) ? b : a)); rule.style('display', null).attr('x1', x(r.week_start)).attr('x2', x(r.week_start)); tp.innerHTML = '<span class="k">Week of ' + dateLabel(r.week_start) + '</span><br>NPS ' + num(r.nps, 1) + ' on ' + num(r.n, 0) + ' responses<br><span class="k">Detractors ' + pct(r.detractor_pct) + ', passives ' + pct(r.passive_pct) + '</span>'; place(el, tp, x(r.week_start), my); })
      .on('mouseleave', () => { rule.style('display', 'none'); tp.style.display = 'none'; });
  }

  // ================= OPERATIONS =================
  let opsFc = 'ALL';
  const FCN = { ALL: 'National', EC: 'Eastern Creek', BNE: 'Crestmead', MEL: 'Tarneit', PER: 'Bibra Lake' };
  function rOps() {
    const t = T.operations;
    let h = ptitle(t);
    const need = ['ops_meta', 'ops_labour', 'ops_prod', 'ops_service', 'ops_difot', 'ops_amr'];
    if (!ready(need)) return h + state(need);
    const m = one('ops_meta');
    const LB = rows('ops_labour'), PR = rows('ops_prod'), SV = rows('ops_service'), DF = rows('ops_difot'), AM = rows('ops_amr');
    const weeks = [...new Set(LB.map((r) => r.week_start))].sort();
    const wl = (w) => dateLabel(w);
    const L0 = (fc) => LB.find((r) => r.fc === fc && r.is_latest), P0 = (fc) => PR.find((r) => r.fc === fc && r.is_latest), S0 = (fc) => SV.find((r) => r.fc === fc && r.is_latest);
    const lw = (fc) => ({ fc: fc, week_start: m.ops_week_start });
    const nat = L0('ALL'), am = AM.find((r) => r.is_latest);
    const dn = DF.filter((r) => r.fc === 'ALL' && r.is_latest);
    // highlights
    const good = [], watch = [];
    (nat.cpo_vs_tgt <= 0 ? good : watch).push('<b>Cost per order ' + V('ops_labour', 'cpo', lw('ALL'), dollars2(nat.cpo)) + '</b>, ' + V('ops_labour', 'cpo_vs_tgt', lw('ALL'), sdollars2(nat.cpo_vs_tgt)) + ' against budget, on ' + V('ops_labour', 'orders', lw('ALL'), num(nat.orders, 0)) + ' orders closed.');
    for (const r of dn) (r.vs_target_pp >= 0 ? good : watch).push('<b>' + esc(r.order_type_name) + ' DIFOT ' + V('ops_difot', 'difot_pct', { fc: 'ALL', order_type: r.order_type, week_start: r.week_start }, pct(r.difot_pct, 2)) + '</b>, ' + V('ops_difot', 'vs_target_pp', { fc: 'ALL', order_type: r.order_type, week_start: r.week_start }, pp(r.vs_target_pp, 2)) + ' against the ' + r.target_pct + '% target.');
    if (am) (am.vs_target_pp >= 0 ? good : watch).push('<b>AMR uptime ' + V('ops_amr', 'uptime_pct', { week_start: am.week_start }, pct(am.uptime_pct, 1)) + '</b> at Eastern Creek against a ' + am.target_pct + '% target.');
    const sites = ['EC', 'BNE', 'MEL', 'PER'].map(L0).filter((r) => r && r.cpo_vs_tgt > 0.25);
    for (const r of sites) watch.push('<b>' + esc(r.fc_name) + '</b> cost per order ' + V('ops_labour', 'cpo', lw(r.fc), dollars2(r.cpo)) + ', ' + V('ops_labour', 'cpo_vs_tgt', lw(r.fc), sdollars2(r.cpo_vs_tgt)) + ' over budget.');
    h += hlBoxes(good, watch, 'Derived from the ops team’s own figures against budget or target, not curated commentary.');
    const calw = one('cal');
    if (m.held || (calw && m.week_end !== calw.week_end)) h += '<div class="stale" style="display:block">Operations is showing the week of ' + V('ops_meta', 'ops_week_label', null, esc(m.ops_week_label)) + ', behind the rest of this dashboard: the ops team’s dashboard had not rolled to this dashboard’s week when it was last read. A Tuesday top-up reads it again.</div>';
    h += '<div class="decision"><b>Source:</b> every figure in sections 1 to 3 and 5 is read from the ops team’s own weekly dashboard (' + V('ops_meta', 'source_refreshed', null, esc(m.source_refreshed)) + ' refresh), not re-derived, so finance and ops quote one set of numbers. Delivery promise (section 4) is computed from the warehouse. This will move to the business layer once the ops data is modelled there.</div>';
    h += '<div class="pc-tabs" style="margin-bottom:var(--cds-gap-md)">' + Object.entries(FCN).map(([k, l]) => '<button class="pc-tab" data-fc="' + k + '" aria-selected="' + (opsFc === k) + '">' + l + '</button>').join('') + '</div>';
    const fc = opsFc, L = L0(fc), P = P0(fc), S = S0(fc), w = lw(fc);
    const vl = (f, fmt) => V('ops_labour', f, w, fmt(L[f])), vp = (f, fmt) => V('ops_prod', f, w, fmt(P[f])), vs = (f, fmt) => V('ops_service', f, w, fmt(S[f]));
    const pwPill = (ds, f, fmt, row, good) => pill('vs prior week', V(ds, f + '_vs_pw', w, fmt(row[f + '_vs_pw'])), cls(row[f + '_vs_pw'], good));

    h += sec('1', 'Cost per order and labour');
    h += '<div class="grid tiles">' + tile('Cost per order', vl('cpo', dollars2), 'budget ' + vl('cpo_tgt', dollars2), pill('vs budget', vl('cpo_vs_tgt', sdollars2), cls(L.cpo_vs_tgt, false)) + pwPill('ops_labour', 'cpo', sdollars2, L, false)) +
      tile('Labour cost', vl('cost', money), 'budget ' + vl('cost_tgt', money), pill('vs budget', vl('cost_vs_tgt', smoney), cls(L.cost_vs_tgt, false)) + pwPill('ops_labour', 'cost', smoney, L, false)) +
      tile('Orders closed', vl('orders', (v) => num(v, 0)), '', pwPill('ops_labour', 'orders', (v) => snum(v, 0), L, true)) +
      tile('Cost per hour', vl('cph', dollars2), '', pwPill('ops_labour', 'cph', sdollars2, L, false)) +
      tile('Contractor mix', vl('contractor_mix', (v) => pct(v, 1)), 'share of labour hours', pwPill('ops_labour', 'contractor_mix', pp, L, false)) + '</div>';
    let pv = '<div class="tw" data-source="ops_labour"><table class="t"><thead><tr><th>Fulfilment centre</th>' + weeks.map((x) => '<th>' + wl(x) + '</th>').join('') + '<th>Budget</th><th>Change vs first wk</th></tr></thead><tbody>';
    for (const f of ['ALL', 'EC', 'BNE', 'MEL', 'PER']) {
      const R = weeks.map((x) => LB.find((r) => r.fc === f && r.week_start === x)); const last = R[R.length - 1];
      pv += '<tr' + (f === 'ALL' ? ' class="tot"' : '') + '><td>' + FCN[f] + '</td>' + R.map((r) => '<td>' + (r ? dollars2(r.cpo) : NA) + '</td>').join('') + '<td>' + dollars2(last.cpo_tgt) + '</td><td class="' + cls(last.cpo_vs_first, false) + '">' + frac(last.cpo_vs_first) + '</td></tr>';
    }
    h += '<div class="grid" style="grid-template-columns:minmax(0,1fr);margin-top:var(--cds-gap-md)">' + card('Cost per order by fulfilment centre - ' + weeks.length + ' week trend', 'Budget is the current week’s, from the ops team’s per-site budget.', pv + '</tbody></table></div>');
    const fn = [['Outbound', 'out_cost'], ['Inbound', 'in_cost'], ['Dock', 'dock_cost'], ['Weekend', 'wknd_cost'], ['Support', 'supp_cost']];
    const own = fn.reduce((a, [, f]) => a + (+L[f] || 0), 0);
    h += card('Labour cost by function', 'Own-staff labour only. Contractor cost sits outside this split because the agency invoice is already fully loaded and is never on-costed.', '<div class="tw" data-source="ops_labour"><table class="t"><thead><tr><th>Function</th><th>Cost</th><th>Share</th><th>Vs prior week</th></tr></thead><tbody>' + fn.map(([l, f]) => '<tr><td>' + l + '</td><td>' + vl(f, money) + '</td><td>' + pct(own ? 100 * L[f] / own : null) + '</td><td class="' + cls(L[f + '_vs_pw'], false) + '">' + V('ops_labour', f + '_vs_pw', w, smoney(L[f + '_vs_pw'])) + '</td></tr>').join('') + '</tbody></table></div>') + '</div>';

    h += sec('2', 'Productivity');
    h += '<div class="grid tiles">' + tile('Outbound cost per order', vp('out_cpo', dollars2), '', pwPill('ops_prod', 'out_cpo', sdollars2, P, false)) + tile('Manual pick cost per line', vp('man_cpl', dollars2), '', pwPill('ops_prod', 'man_cpl', sdollars2, P, false)) + tile('AMR pick cost per line', vp('amr_cpl', dollars2), fc === 'ALL' || fc === 'EC' ? '' : 'no AMR at this site', pwPill('ops_prod', 'amr_cpl', sdollars2, P, false)) + tile('Pack cost per carton', vp('pack_cpc', dollars2), '', pwPill('ops_prod', 'pack_cpc', sdollars2, P, false)) +
      tile('Manual pick rate', vp('man_uph', (v) => num(v, 1) + '/hr'), '', pwPill('ops_prod', 'man_uph', (v) => snum(v, 1) + '/hr', P, true)) + tile('AMR pick rate', vp('amr_uph', (v) => num(v, 1) + '/hr'), '', pwPill('ops_prod', 'amr_uph', (v) => snum(v, 1) + '/hr', P, true)) + tile('Lines per order', vp('lines_per_order', (v) => num(v, 2)), '', pwPill('ops_prod', 'lines_per_order', (v) => snum(v, 2), P, true)) + '</div>';
    h += '<p class="note">Rates are per Deputy paid hour, the ops team’s settled denominator. AMR figures are Eastern Creek only; the other sites have no AMR.</p>';
    h += '<div class="grid tiles" style="margin-top:var(--cds-gap-md)">' + tile('Receipts arrived', vs('receipts', (v) => num(v, 0)), 'inbound', pwPill('ops_service', 'receipts', (v) => snum(v, 0), S, true)) + tile('Lines received', vs('inb_lines', (v) => num(v, 0)), '', pwPill('ops_service', 'inb_lines', (v) => snum(v, 0), S, true)) + tile('Outstanding receipts', vs('outstanding_receipts', (v) => num(v, 0)), 'live tail still to be put away') + tile('Mixed container share', vs('mixed_pct', (v) => pct(v, 1)), 'indicative level, sound trend', pwPill('ops_service', 'mixed_pct', pp, S, false)) + '</div>';

    h += sec('3', 'Service');
    h += '<div class="grid tiles">' + tile('24 hour pack rate', vs('pack24_pct', (v) => pct(v, 1)), '', pwPill('ops_service', 'pack24_pct', pp, S, true)) + tile('Delivered within 24 hours', vs('d24_pct', (v) => pct(v, 1)), 'newest week understates and self-corrects', pwPill('ops_service', 'd24_pct', pp, S, true)) +
      (am ? tile('AMR uptime', V('ops_amr', 'uptime_pct', { week_start: am.week_start }, pct(am.uptime_pct, 1)), 'Eastern Creek; low day ' + V('ops_amr', 'low_day_pct', { week_start: am.week_start }, pct(am.low_day_pct, 1)), pill('vs target', V('ops_amr', 'vs_target_pp', { week_start: am.week_start }, pp(am.vs_target_pp, 1)), cls(am.vs_target_pp))) : '') + '</div>';

    h += sec('4', 'Delivery promise');
    if (ok('ops_delivery')) {
      const DV = rows('ops_delivery'), dw = [...new Set(DV.map((r) => r.week_start))].sort();
      const dwk = [...dw].reverse().find((x) => DV.filter((r) => r.week_start === x).every((r) => r.mature)) || dw[dw.length - 1];
      const cur = ['EC', 'BNE', 'MEL', 'PER', 'ALL'].map((f) => DV.find((r) => r.fc === f && r.week_start === dwk)).filter(Boolean);
      h += '<div class="grid" style="grid-template-columns:minmax(0,1fr)">' + card('Delivery promise by warehouse' + (one('cal') && dwk !== one('cal').week_start ? ' - week of ' + dateLabel(dwk) + ' (latest settled week)' : ''), '', tbl('ops_delivery', 'fc,week_start', [{ f: 'fc_name', h: 'Warehouse' }, { f: 'n_promise', h: 'Orders with a promise', v: (r) => num(r.n_promise, 0) }, { f: 'promise_pct', h: 'On or before promise', v: (r) => pct(r.promise_pct) }, { f: 'metro_pct', h: 'Metro', v: (r) => pct(r.metro_pct) }, { f: 'promise_pct_vs_pw', h: 'Vs prior wk', v: (r) => pp(r.promise_pct_vs_pw), c: (r) => cls(r.promise_pct_vs_pw) }, { f: 'ctd_med', h: 'Click to delivery, days', v: (r) => num(r.ctd_med, 1) + '<span class="sm">p20 ' + num(r.ctd_p20, 1) + ' · p80 ' + num(r.ctd_p80, 1) + '</span>' }], cur, { rowCls: (r) => (r.fc === 'ALL' ? 'tot' : '') }) + '<p class="note">Share of fulfilment orders delivered on or before the promised date, bucketed on the promise date at fulfilment order grain, split by the fulfilment order’s own warehouse. National is pooled from the counts, never an average of site rates. Computed from the warehouse each Monday.</p>');
      let tv = '<div class="tw" data-source="ops_delivery"><table class="t"><thead><tr><th>Warehouse</th>' + dw.map((x) => '<th>' + dateLabel(x) + '</th>').join('') + '<th>Change vs first wk</th></tr></thead><tbody>';
      for (const f of ['ALL', 'EC', 'BNE', 'MEL', 'PER']) { const R = dw.map((x) => DV.find((r) => r.fc === f && r.week_start === x)); const last = R[R.length - 1]; tv += '<tr' + (f === 'ALL' ? ' class="tot"' : '') + '><td>' + FCN[f] + '</td>' + R.map((r) => '<td>' + (r ? pct(r.promise_pct) : NA) + '</td>').join('') + '<td class="' + cls(last && last.promise_pct_vs_first) + '">' + pp(last && last.promise_pct_vs_first) + '</td></tr>'; }
      h += card('Delivery promise rate - ' + dw.length + ' week trend', '', tv + '</tbody></table></div>') + '</div>';
    } else h += state('ops_delivery');

    h += sec('5', 'DIFOT by order type - ' + esc(FCN[fc]));
    const D0 = DF.filter((r) => r.fc === fc && r.is_latest);
    h += '<div class="grid" style="grid-template-columns:minmax(0,1fr)">' + card('', '', tbl('ops_difot', 'fc,order_type,week_start', [{ f: 'order_type_name', h: 'Order type' }, { f: 'orders', h: 'Orders', v: (r) => num(r.orders, 0) }, { f: 'difot_pct', h: 'DIFOT', v: (r) => pct(r.difot_pct, 2) }, { f: 'target_pct', h: 'Target', v: (r) => r.target_pct + '%' }, { f: 'vs_target_pp', h: 'Vs target', v: (r) => pp(r.vs_target_pp, 2), c: (r) => cls(r.vs_target_pp) }, { f: 'difot_pct_vs_pw', h: 'Vs prior wk', v: (r) => pp(r.difot_pct_vs_pw, 2), c: (r) => cls(r.difot_pct_vs_pw) }, { f: 'fulfilment_misses', h: 'Fulfilment misses', v: (r) => num(r.fulfilment_misses, 0) }, { f: 'logistics_misses', h: 'Logistics misses', v: (r) => num(r.logistics_misses, 0) }, { f: 'fulfilment_share_pct', h: 'Fulfilment share', v: (r) => pct(r.fulfilment_share_pct) }], D0) + '<p class="note">Miss ownership: fulfilment is a parcel handed over on or after the promise date; logistics is everything else. One row per fulfilment order, on the promise date.</p>');
    let dt = '<div class="tw" data-source="ops_difot"><table class="t"><thead><tr><th>Order type</th>' + weeks.map((x) => '<th>' + wl(x) + '</th>').join('') + '<th>Target</th></tr></thead><tbody>';
    for (const r0 of D0) { const R = weeks.map((x) => DF.find((r) => r.fc === fc && r.order_type === r0.order_type && r.week_start === x)); dt += '<tr><td>' + esc(r0.order_type_name) + '</td>' + R.map((r) => '<td class="' + (r && r.difot_pct < r.target_pct ? 'neg' : '') + '">' + (r ? pct(r.difot_pct, 1) : NA) + '</td>').join('') + '<td>' + r0.target_pct + '%</td></tr>'; }
    h += card('DIFOT trend by order type', 'Weeks below target are shown in red.', dt + '</tbody></table></div>') + '</div>';

    h += '<p class="note" style="margin-top:var(--cds-gap-lg)"><b>How to read this tab.</b> Several measures are immature on the newest week by design: delivered within 24 hours counts every order created that week, so the newest week understates and corrects upward; inbound is mid-flight. Fulfilment rate and order accuracy are absent on purpose - the ops team has both on hold pending an agreed definition. Contractor cost is never on-costed and sits outside the by-function split. Source: the Fulfilment & Logistics weekly review dashboard (owner: the ops team), read each Monday with a Tuesday top-up.</p>';
    return h;
  }

  // ================= PHASE 2 TABS =================
  const LATER = {
    cx: ['NPS and voice of the customer', 'First on the agenda after Commercial. The CX feedback asked for NPS and CSAT by channel and by Luna vs human, and contacts by reason with the weekly variance against the last 12 weeks.', ['NPS with promoter, passive and detractor bands against target, on a rolling 13-week window.', 'What the comments say: themes ranked by how far they over-index among at-risk customers.', 'CSAT by channel and Luna vs human.', 'Contacts by reason with the weekly variance against the last 12 weeks.'], 'NPS scores are in customer__customer_review. Comment themes need a weekly classification step whose results land in a warehouse table (comment text carries personal details and must never reach this page). CSAT and contact reasons need a source feed.'],
    media: ['Sessions, conversion and orders by channel', 'The feedback asked for three funnel metrics - sessions, conversion rate and orders by channel - a cleaner orders bridge, and placeholders for SEM, social and SEO, and CRM.', ['Sessions, conversion and orders by channel, with an orders bridge that shows totals.', 'Paid search by category: spend, payback and impression share.', 'Social, SEO and other channels.', 'CRM: SMS, email and push performance, campaigns, coupon spend and effectiveness.', 'Bounce rate and add to cart in a drill-down at the foot.'], 'The funnel cube (product_ad_hoc.master_journeys) is in the warehouse. Media cost, impression share and CRM engagement are not, and need extracts landed there.'],
    category: ['Category performance', 'To mirror the category team’s own dashboard: overall performance as on Commercial, split by the three major category groupings on revenue, margin dollars and performance vs plan - the area category managers speak to.', ['Category scorecard vs plan and LY.', 'Brand spotlight and movers.', 'Category update: available, new and slow-moving SKUs.'], 'Today these figures are read from the Weekly Trading & Category KPI Report artifact. The rebuild queries the warehouse directly so the tab refreshes with the rest.'],
    price: ['Pricing and promotion', 'No strong view yet on the content - to be developed with James and Nihan.', ['Price index and discount depth by category.', 'TPD, coupon and cofunding impact on product margin.', 'Price-match activity.'], 'Content to be agreed before the build.'],
    inventory: ['Inventory planning', 'Stock health and availability for the inventory planning review.', ['SLOB against the guardrail and stock at cost.', 'Out-of-stock lost sales (revenue basis) and out of stock by warehouse (SKU basis), clearly separated.', 'SKU and variant productivity.'], 'Sources are in the warehouse (inventory holding status, item trading report). Known issue: the QLD Crestmead ranging flag break understates national out of stock.'],
    operations: ['Supply chain operations', 'Labour, cost per order, productivity, service and DIFOT for the supply chain review.', ['Cost per order and labour vs target by fulfilment centre.', 'Productivity: pick rates, inbound, AMR uptime.', 'Service: 24-hour pack rate, DIFOT, delivery promise, click to delivery.'], 'Today this tab is a copy of the ops team’s WBR payload, which has been running weeks stale. The durable fix is for that payload to land in a shared warehouse table so this tab can read it on the same Monday refresh (with a possible Tuesday top-up once Operations settles).'],
  };
  function rLater(id) {
    const t = T[id], x = LATER[id];
    return ptitle(t) + ph(x[0], x[1], x[2], x[3]) + '<p class="note">This tab is part of phase 2 of the move to an automatically refreshed dashboard. Until then the previous dashboard remains the reference for it.</p>';
  }

  // ================= charts =================
  function tipFor(el) { let tp = el.querySelector('.tip'); if (!tp) { tp = document.createElement('div'); tp.className = 'tip'; el.appendChild(tp); } return tp; }
  function place(el, tp, x, y) { tp.style.display = 'block'; const w = tp.offsetWidth, W = el.clientWidth; tp.style.left = Math.max(0, Math.min(W - w, x + 10)) + 'px'; tp.style.top = Math.max(0, y - 10 - tp.offsetHeight) + 'px'; }
  function noAxisFont(g) { g.attr('font-size', null).attr('font-family', null); g.selectAll('text').attr('fill', 'var(--color-fg-muted)').style('font-size', 'var(--cds-font-size-caption)'); g.selectAll('line,path').attr('stroke', 'var(--cds-chart-axis)'); }
  function spark(el) {
    const f = el.dataset.spark; const R = rows('scorecard_weekly').sort((a, b) => (a.week_end < b.week_end ? -1 : 1));
    el.querySelectorAll('svg').forEach((s) => s.remove());
    if (!R.length || !el.clientWidth) return;
    const W = el.clientWidth, H = 38, vals = R.map((r) => +r[f]);
    const x = d3.scaleLinear([0, R.length - 1], [3, W - 3]), y = d3.scaleLinear(d3.extent(vals), [H - 4, 4]);
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    const mean = d3.mean(vals);
    svg.append('line').attr('x1', 0).attr('x2', W).attr('y1', y(mean)).attr('y2', y(mean)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '3 3');
    svg.append('path').attr('d', d3.line((d, i) => x(i), (d) => y(d))(vals)).attr('fill', 'none').attr('stroke', PCC[0]).attr('stroke-width', 2).attr('stroke-linecap', 'round').attr('stroke-linejoin', 'round');
    svg.append('circle').attr('cx', x(R.length - 1)).attr('cy', y(vals[vals.length - 1])).attr('r', 3).attr('fill', PCC[0]);
    const dot = svg.append('circle').attr('r', 3.5).attr('fill', PCC[0]).attr('stroke', 'var(--color-panel)').attr('stroke-width', 2).style('display', 'none');
    const tp = tipFor(el), unit = { product_margin_pct: 'pct', units_per_order: 'n2', orders: 'n' }[f] || '$';
    svg.append('rect').attr('width', W).attr('height', H).attr('fill', 'transparent').on('mousemove', (ev) => { const [mx] = d3.pointer(ev); const i = Math.max(0, Math.min(R.length - 1, Math.round(x.invert(mx)))); dot.style('display', null).attr('cx', x(i)).attr('cy', y(vals[i])); tp.innerHTML = '<span class="k">' + esc(R[i].wk_label) + ' · w/e ' + dateLabel(R[i].week_end) + '</span><br>' + (unit === 'pct' ? pct(vals[i]) : unit === 'n2' ? num(vals[i], 2) : unit === 'n' ? num(vals[i]) : money(vals[i])); place(el, tp, x(i), y(vals[i])); }).on('mouseleave', () => { dot.style('display', 'none'); tp.style.display = 'none'; });
  }
  function cxSpark(el) {
    const f = el.dataset.cxspark; const W0 = D('cx_contacts_worm');
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = W0.status === 'ok' ? (W0.data || []).filter((r) => isN(r[f])) : [];
    if (R.length < 2 || !el.clientWidth) return;
    const W = el.clientWidth, H = 38, vals = R.map((r) => +r[f]);
    const x = d3.scaleLinear([0, R.length - 1], [3, W - 3]), y = d3.scaleLinear(d3.extent(vals), [H - 4, 4]);
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    const mean = d3.mean(vals);
    svg.append('line').attr('x1', 0).attr('x2', W).attr('y1', y(mean)).attr('y2', y(mean)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '3 3');
    svg.append('path').attr('d', d3.line((d, i) => x(i), (d) => y(d))(vals)).attr('fill', 'none').attr('stroke', PCC[0]).attr('stroke-width', 2).attr('stroke-linecap', 'round').attr('stroke-linejoin', 'round');
    svg.append('circle').attr('cx', x(R.length - 1)).attr('cy', y(vals[vals.length - 1])).attr('r', 3).attr('fill', PCC[0]);
    const dot = svg.append('circle').attr('r', 3.5).attr('fill', PCC[0]).attr('stroke', 'var(--color-panel)').attr('stroke-width', 2).style('display', 'none');
    const tp = tipFor(el), fmt = { contacts: (v) => num(v, 0) + ' contacts', per_1k_orders: (v) => num(v, 1) + ' per 1,000 orders', ai_engaged_pct: (v) => pct(v, 1) + ' engaged by Luna' }[f] || ((v) => num(v, 1));
    svg.append('rect').attr('width', W).attr('height', H).attr('fill', 'transparent').on('mousemove', (ev) => { const [mx] = d3.pointer(ev); const i = Math.max(0, Math.min(R.length - 1, Math.round(x.invert(mx)))); dot.style('display', null).attr('cx', x(i)).attr('cy', y(vals[i])); tp.innerHTML = '<span class="k">w/e ' + dateLabel(R[i].week_end) + '</span><br>' + fmt(vals[i]); place(el, tp, x(i), y(vals[i])); }).on('mouseleave', () => { dot.style('display', 'none'); tp.style.display = 'none'; });
  }
  function csatSpark(el) {
    const g = el.dataset.csatspark; const W0 = D('cx_csat_worm');
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = W0.status === 'ok' ? (W0.data || []).filter((r) => r.handler === g && isN(r.csat_pct)) : [];
    if (R.length < 2 || !el.clientWidth) return;
    const W = el.clientWidth, H = 38, vals = R.map((r) => +r.csat_pct), ref = R[0].csat_pct_13w;
    const x = d3.scaleLinear([0, R.length - 1], [4, W - 4]), y = d3.scaleLinear(d3.extent([...vals, ...(isN(ref) ? [+ref] : [])]), [H - 4, 4]);
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    if (isN(ref)) svg.append('line').attr('x1', 0).attr('x2', W).attr('y1', y(+ref)).attr('y2', y(+ref)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '3 3');
    svg.append('path').attr('d', d3.line((d, i) => x(i), (d) => y(d))(vals)).attr('fill', 'none').attr('stroke', PCC[0]).attr('stroke-width', 2).attr('stroke-linecap', 'round').attr('stroke-linejoin', 'round');
    svg.append('circle').attr('cx', x(R.length - 1)).attr('cy', y(vals[vals.length - 1])).attr('r', 3).attr('fill', PCC[0]);
    const dot = svg.append('circle').attr('r', 3.5).attr('fill', PCC[0]).attr('stroke', 'var(--color-panel)').attr('stroke-width', 2).style('display', 'none');
    const tp = tipFor(el);
    svg.append('rect').attr('width', W).attr('height', H).attr('fill', 'transparent').on('mousemove', (ev) => { const [mx] = d3.pointer(ev); const i = Math.max(0, Math.min(R.length - 1, Math.round(x.invert(mx)))); dot.style('display', null).attr('cx', x(i)).attr('cy', y(vals[i])); tp.innerHTML = '<span class="k">w/e ' + dateLabel(R[i].week_end) + '</span><br>CSAT ' + pct(vals[i], 1) + ' on ' + num(R[i].ratings, 0) + (+R[i].ratings === 1 ? ' rating' : ' ratings') + (+R[i].ratings < 30 ? ' (indicative)' : ''); place(el, tp, x(i), y(vals[i])); }).on('mouseleave', () => { dot.style('display', 'none'); tp.style.display = 'none'; });
  }
  function fyChart(el) {
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = rows('fy_weeks').sort((a, b) => a.wk - b.wk);
    if (!R.length || !el.clientWidth) return;
    const W = el.clientWidth, H = 220, m = { t: 10, r: 8, b: 26, l: 48 };
    const x = d3.scaleBand(R.map((r) => r.fy_wk), [m.l, W - m.r]).padding(0.25);
    const hi = d3.max(R, (r) => Math.max(+r.actual || 0, +r.budget || 0)), lo = d3.min(R, (r) => Math.min(isN(r.actual) ? +r.actual : Infinity, +r.budget || Infinity));
    const y = d3.scaleLinear([lo * 0.9, hi * 1.02], [H - m.b, m.t]).nice();
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    svg.append('g').attr('transform', 'translate(0,' + (H - m.b) + ')').call(d3.axisBottom(x).tickFormat((d) => d.replace(/^FY\d+ /, '')).tickSizeOuter(0)).call(noAxisFont);
    svg.append('g').attr('transform', 'translate(' + m.l + ',0)').call(d3.axisLeft(y).ticks(4).tickFormat((v) => '$' + (v / 1e6).toFixed(1) + 'M')).call(noAxisFont).call((g) => g.select('.domain').remove());
    svg.append('g').selectAll('rect').data(R.filter((r) => isN(r.actual))).join('rect').attr('x', (r) => x(r.fy_wk)).attr('width', x.bandwidth()).attr('y', (r) => y(r.actual)).attr('height', (r) => y.range()[0] - y(r.actual)).attr('rx', 3).attr('fill', PCC[0]);
    svg.append('g').selectAll('line').data(R).join('line').attr('x1', (r) => x(r.fy_wk) - 2).attr('x2', (r) => x(r.fy_wk) + x.bandwidth() + 2).attr('y1', (r) => y(r.budget)).attr('y2', (r) => y(r.budget)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-width', 2);
    const tp = tipFor(el);
    svg.append('g').selectAll('rect').data(R).join('rect').attr('x', (r) => x(r.fy_wk) - x.step() * 0.12).attr('width', x.step()).attr('y', m.t).attr('height', H - m.t - m.b).attr('fill', 'transparent')
      .on('mousemove', (ev, r) => { const [mx, my] = d3.pointer(ev, el); tp.innerHTML = '<span class="k">' + esc(r.fy_wk) + ' · w/e ' + dateLabel(r.week_end) + '</span><br>Actual ' + (isN(r.actual) ? money(r.actual) : 'not traded') + '<br>' + plan() + ' ' + money(r.budget) + (isN(r.d_bud_pct) ? '<br>vs plan ' + frac(r.d_bud_pct) : ''); place(el, tp, mx, my); })
      .on('mouseleave', () => { tp.style.display = 'none'; });
  }
  function a92Chart(el) {
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = rows('a92_flow').sort((a, b) => (a.week_end < b.week_end ? -1 : 1));
    if (!R.length || !el.clientWidth) return;
    const W = el.clientWidth, H = 220, m = { t: 14, r: 8, b: 26, l: 44 };
    const x = d3.scaleBand(R.map((r) => r.week_end), [m.l, W - m.r]).padding(0.3);
    const ext = d3.extent([0, ...R.map((r) => +r.net_change), +R[0].avg_net_13w]);
    const y = d3.scaleLinear([ext[0] * 1.15, Math.max(ext[1], 0) * 1.15 + 1], [H - m.b, m.t]).nice();
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    svg.append('g').attr('transform', 'translate(0,' + (H - m.b) + ')').call(d3.axisBottom(x).tickFormat((d) => dateLabel(d)).tickSizeOuter(0)).call(noAxisFont).call((g) => g.selectAll('.tick text').attr('display', (d, i) => (R.length > 8 && i % 2 ? 'none' : null)));
    svg.append('g').attr('transform', 'translate(' + m.l + ',0)').call(d3.axisLeft(y).ticks(4).tickFormat((v) => (v / 1e3).toFixed(1) + 'k')).call(noAxisFont).call((g) => g.select('.domain').remove());
    svg.append('line').attr('x1', m.l).attr('x2', W - m.r).attr('y1', y(0)).attr('y2', y(0)).attr('stroke', 'var(--cds-chart-axis)');
    svg.append('g').selectAll('rect').data(R).join('rect').attr('x', (r) => x(r.week_end)).attr('width', x.bandwidth()).attr('y', (r) => y(Math.max(0, r.net_change))).attr('height', (r) => Math.abs(y(r.net_change) - y(0))).attr('rx', 3).attr('fill', PCC[0]).attr('opacity', (r, i) => (i === R.length - 1 ? 1 : 0.55));
    svg.append('line').attr('x1', m.l).attr('x2', W - m.r).attr('y1', y(R[0].avg_net_13w)).attr('y2', y(R[0].avg_net_13w)).attr('stroke', 'var(--cds-chart-reference)').attr('stroke-dasharray', '4 3');
    const tp = tipFor(el);
    svg.append('g').selectAll('rect').data(R).join('rect').attr('x', (r) => x(r.week_end) - x.step() * 0.15).attr('width', x.step()).attr('y', m.t).attr('height', H - m.t - m.b).attr('fill', 'transparent')
      .on('mousemove', (ev, r) => { const [mx, my] = d3.pointer(ev, el); tp.innerHTML = '<span class="k">' + esc(r.wk_label) + ' · w/e ' + dateLabel(r.week_end) + '</span><br>Net ' + snum(r.net_change) + '<br>New ' + num(r.new_customers) + ' · Reactivated ' + num(r.reactivated) + '<br>Lapsed ' + num(r.lapsed) + '<br>Closing base ' + num(r.closing); place(el, tp, mx, my); })
      .on('mouseleave', () => { tp.style.display = 'none'; });
  }
  function cohortChart(el) {
    el.querySelectorAll('svg').forEach((s) => s.remove());
    const R = rows('ad_cohort');
    if (!R.length || !el.clientWidth) return;
    const W = el.clientWidth, H = 220, m = { t: 12, r: 8, b: 26, l: 44 };
    const keys = ['r2', 'r3', 'r4'], lab = { r2: 'AD2 within 90d', r3: 'AD3 within 180d', r4: 'AD4 within 180d' }, win = { r2: 'window_90_closes', r3: 'window_180_closes', r4: 'window_180_closes' };
    const x = d3.scaleBand(R.map((r) => r.month_label), [m.l, W - m.r]).padding(0.2);
    const xi = d3.scaleBand(keys, [0, x.bandwidth()]).padding(0.12);
    const y = d3.scaleLinear([0, 100], [H - m.b, m.t]);
    const svg = d3.select(el).append('svg').attr('width', '100%').attr('height', H).attr('viewBox', '0 0 ' + W + ' ' + H);
    svg.append('g').attr('transform', 'translate(0,' + (H - m.b) + ')').call(d3.axisBottom(x).tickSizeOuter(0)).call(noAxisFont).call((g) => g.selectAll('.tick text').attr('display', (d, i) => (W < 600 && i % 2 ? 'none' : null)));
    svg.append('g').attr('transform', 'translate(' + m.l + ',0)').call(d3.axisLeft(y).ticks(4).tickFormat((v) => v + '%')).call(noAxisFont).call((g) => g.select('.domain').remove());
    const g = svg.append('g').selectAll('g').data(R).join('g').attr('transform', (r) => 'translate(' + x(r.month_label) + ',0)');
    g.selectAll('rect').data((r) => keys.map((k, i) => ({ k, i, v: isN(r[k]) ? +r[k] : null })).filter((d) => d.v !== null)).join('rect').attr('x', (d) => xi(d.k)).attr('width', xi.bandwidth()).attr('y', (d) => y(d.v)).attr('height', (d) => y(0) - y(d.v)).attr('rx', 2).attr('fill', (d) => COH[d.i]);
    const tp = tipFor(el);
    svg.append('g').selectAll('rect').data(R).join('rect').attr('x', (r) => x(r.month_label)).attr('width', x.bandwidth()).attr('y', m.t).attr('height', H - m.t - m.b).attr('fill', 'transparent')
      .on('mousemove', (ev, r) => { const [mx, my] = d3.pointer(ev, el); tp.innerHTML = '<span class="k">' + esc(r.month_label) + '</span><br>' + num(r.n) + ' new to AD<br>' + keys.map((k, i) => '<i style="display:inline-block;width:8px;height:8px;border-radius:2px;background:' + COH[i] + '"></i> ' + lab[k] + ' ' + (isN(r[k]) ? pct(r[k], 0) : 'window open until ' + dateLabel(r[win[k]]))).join('<br>'); place(el, tp, mx, my); })
      .on('mouseleave', () => { tp.style.display = 'none'; });
  }
  function charts() {
    const p = document.getElementById(current); if (!p || p.hidden) return;
    p.querySelectorAll('[data-spark]').forEach(spark);
    p.querySelectorAll('[data-prspark]').forEach(prSpark);
    p.querySelectorAll('[data-cxspark]').forEach(cxSpark);
    p.querySelectorAll('[data-csatspark]').forEach(csatSpark);
    const c = (id, f) => { const el = p.querySelector('#' + id); if (el) f(el); };
    c('ch-fyweeks', fyChart); c('ch-mfweekly', mfChart); c('ch-prindex', prChart); c('ch-cxweekly', cxChart); c('ch-a92', a92Chart); c('ch-cohort', cohortChart);
    if (current === 'commercial' && window.pcExplorer) window.pcExplorer.mount(p);
  }

  document.getElementById('operations').addEventListener('click', (e) => { const b = e.target.closest('[data-fc]'); if (!b) return; opsFc = b.dataset.fc; draw(); });
  document.getElementById('category').addEventListener('click', (e) => { const b = e.target.closest('[data-period]'); if (!b) return; catPeriod = b.dataset.period; draw(); });
  // ---------- RFM expand ----------
  document.getElementById('customer').addEventListener('click', (e) => {
    const tr = e.target.closest('#rfm-t tr.bucket'); if (!tr) return;
    const b = tr.dataset.bucket;
    if (openBuckets.has(b)) openBuckets.delete(b); else openBuckets.add(b);
    tr.classList.toggle('open');
    tr.parentElement.querySelectorAll('tr').forEach((r) => { if (r.dataset.kind === 'segment' && r.dataset.bucket === b) r.hidden = !openBuckets.has(b); });
  });

  // ---------- header ----------
  // The latest Sunday that should have been published by now (Sydney): the most recent Sunday before today,
  // or the one before that until 10am Monday, so the page only calls itself late once the 8am refresh has had time to land.
  function expectedWeekEnd() {
    const p = {};
    new Intl.DateTimeFormat('en-US', { timeZone: 'Australia/Sydney', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23', weekday: 'short' }).formatToParts(new Date()).forEach((x) => { p[x.type] = x.value; });
    const dow = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 }[p.weekday] || 1;
    let back = dow;
    if (dow === 1 && Number(p.hour) < 10) back += 7;
    return new Date(Date.UTC(+p.year, +p.month - 1, +p.day - back)).toISOString().slice(0, 10);
  }
  const longDate = (iso) => new Date(iso + 'T00:00:00Z').toLocaleDateString('en-AU', { timeZone: 'UTC', weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
  function header() {
    const c = one('cal');
    document.querySelectorAll('.pc-head [data-source="cal"]').forEach((el) => { el.classList.toggle('dash-skeleton', !c); el.textContent = c ? c[el.dataset.field] : '—'; });
    const st = document.getElementById('pc-stale');
    if (c) {
      const exp = expectedWeekEnd();
      if (c.week_end < exp) {
        const behind = Math.round((Date.parse(exp + 'T00:00:00Z') - Date.parse(c.week_end + 'T00:00:00Z')) / 604800000);
        st.style.display = 'block';
        st.innerHTML = 'This page is showing ' + V('cal', 'fy_wk', null, esc(c.fy_wk)) + ' (' + V('cal', 'period_str', null, esc(c.period_str)) + '), ' + (behind > 1 ? behind + ' weeks' : 'one week') + ' behind. The week ending ' + esc(longDate(exp)) + ' has not been published yet, so every figure below is from the earlier week. The weekly refresh runs from 8am on Mondays.';
      } else st.style.display = 'none';
    }
  }

  // ---------- draw ----------
  const R_ = { highlights: rHighlights, commercial: rCommercial, customer: rCustomer, autodelivery: rAD, category: rCategory, inventory: rInventory, media: rMedia, price: rPrice, cx: rCX, operations: rOps };
  function draw() {
    header();
    for (const t of TABS) {
      const el = document.getElementById(t.id);
      let html;
      try { html = R_[t.id] ? R_[t.id]() : rLater(t.id); } catch (err) { html = ptitle(t) + '<div class="fail">Failed to draw</div>'; setTimeout(() => { throw err; }); }
      el.innerHTML = html;
    }
    charts();
  }
  const start = location.hash.slice(1);
  show(TABS.some((t) => t.id === start) ? start : 'highlights', false);
  dash.onData(draw);
})();
