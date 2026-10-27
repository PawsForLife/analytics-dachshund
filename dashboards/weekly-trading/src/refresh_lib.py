#!/usr/bin/env python3
"""Weekly refresh helpers for the Pet Circle Weekly Trading Dashboard.
  wrap <sql_file>                -> prints the wrapped query to run (rows as one JSON string + its MD5)
  unwrap <raw_answer> <out.json> -> checks the MD5 and row count, writes the row objects
  gate <out_dir>                 -> freshness and cross-dataset checks; exit 1 on any failure
"""
import json, sys, hashlib, glob, os, re
def wrap(sql):
    sql = sql.strip().rstrip(';')
    return ("WITH x AS (SELECT TO_JSON_STRING(ARRAY_AGG(t)) AS j, COUNT(*) AS n FROM (\n" + sql +
            "\n) t) SELECT j, TO_HEX(MD5(j)) AS h, n FROM x")
def unwrap(raw, out):
    a = json.load(open(raw))
    if isinstance(a, dict) and isinstance(a.get('content'), list): a = json.loads(a['content'][0]['text'])
    if not a.get('jobComplete', True): sys.exit('FAIL query not complete')
    names = [f['name'] for f in a['schema']['fields']]
    row = {k: c['v'] for k, c in zip(names, a['rows'][0]['f'])}
    j, h, n = row['j'], row['h'], int(row['n'])
    if hashlib.md5(j.encode('utf-8')).hexdigest() != h: sys.exit('FAIL checksum mismatch - the answer was not copied exactly; re-copy it')
    rows = json.loads(j)
    if len(rows) != n: sys.exit(f'FAIL row count {len(rows)} != {n}')
    if n == 0: sys.exit('FAIL no rows')
    if n >= 3000: sys.exit('FAIL 3000 rows: truncated')
    json.dump(rows, open(out, 'w'), separators=(',', ':'))
    print('ok', out, n, 'rows')
def explorer_ties(L, sc, probs):
    """Commercial explorer (commercial_explorer): its totals must equal the scorecard and every waterfall must add up."""
    ex = L('commercial_explorer')
    tot = {(r['metric'], r['split'], r['period']): r for r in ex if r['is_total']}
    smap = {'revenue': 'product_revenue', 'margin': 'product_margin', 'orders': 'orders', 'customers': 'purchasing_customers', 'aov': 'aov'}
    bmap = {'lw': 'lw', 'l12': 'l13w', 'ly': 'ly'}
    tol = {'revenue': 1.0, 'margin': 1.0, 'orders': 2, 'customers': 2, 'aov': 0.01}
    splits = {'revenue': ['book', 'category', 'brand', 'channel', 'status', 'state'], 'margin': ['book', 'category', 'brand', 'channel', 'status', 'state'],
              'orders': ['channel', 'status', 'state'], 'customers': ['channel', 'status', 'state'], 'aov': ['channel', 'status', 'state']}
    bad = []
    for m, k in smap.items():
        s = sc[k]
        for sp in splits[m]:
            for p in ['lw', 'l12', 'ly'] + (['plan'] if m in ('revenue', 'margin') and sp in ('book', 'category') else []):
                t = tot.get((m, sp, p))
                if not t: bad.append(f'{m}/{sp}/{p} missing'); continue
                if abs(t['cur'] - s['tw']) > tol[m]: bad.append(f'{m}/{sp}/{p} this week {t["cur"]} vs scorecard {s["tw"]}')
                if p == 'plan':
                    if s.get('bud') is None or abs(t['base'] - s['bud']) > 0.005 * abs(s['bud']): bad.append(f'{m}/{sp} plan {t["base"]} vs scorecard {s.get("bud")}')
                elif abs(t['base'] - s[bmap[p]]) > tol[m]: bad.append(f'{m}/{sp}/{p} comparison {t["base"]} vs scorecard {s[bmap[p]]}')
                if m in ('revenue', 'margin', 'orders'):
                    seg = sum(r['delta'] for r in ex if (r['metric'], r['split'], r['period']) == (m, sp, p) and not r['is_total'])
                    if abs(seg - t['delta']) > max(1.0, tol[m] * 2): bad.append(f'{m}/{sp}/{p} waterfall adds to {round(seg, 2)}, total change {t["delta"]}')
    if bad: probs.append('commercial explorer does not tie to the scorecard (' + str(len(bad)) + '): ' + '; '.join(bad[:5]))
def gate(d):
    L = lambda k: json.load(open(os.path.join(d, k + '.json')))
    probs = []
    cal = L('cal')[0]; we = cal['week_end']
    import datetime, zoneinfo
    today = datetime.datetime.now(zoneinfo.ZoneInfo('Australia/Sydney')).date()
    last_sun = today - datetime.timedelta(days=(today.weekday() + 1) % 7)
    if we != last_sun.isoformat(): probs.append(f'cal reports week ending {we}; the latest completed week is {last_sun} - warehouse calendar not rolled yet')
    for f in sorted(glob.glob(os.path.join(d, '*.json'))):
        rows = json.load(open(f)); k = os.path.basename(f)[:-5]
        wk = max(str(r.get('report_week_end') or r.get('week_end') or '') for r in rows)
        if wk != we: probs.append(f'{k}: reports week {wk}, expected {we}')
        txt = open(f, encoding='utf-8').read()
        if re.search('[–—‘’“”]', txt): probs.append(f'{k}: dash or smart quote in text')
    sc = {r['metric']: r for r in L('scorecard')}
    rev, orders = sc['product_revenue']['tw'], sc['orders']['tw']
    if not 5e6 < rev < 12e6: probs.append(f'scorecard revenue {rev} out of range')
    if not 45000 < orders < 90000: probs.append(f'scorecard orders {orders} out of range')
    if not 25 < sc['product_margin_pct']['tw'] < 40: probs.append('margin % out of range')
    tot = [r for r in L('orders_mix') if r['value'] == 'Total' and r['cut'] == 'channel'][0]['orders_tw']
    if abs(tot - orders) > 2: probs.append(f'orders_mix total {tot} != scorecard {orders}')
    if os.path.exists(os.path.join(d, 'commercial_explorer.json')): explorer_ties(L, sc, probs)
    lev = L('levers')[0]['den']
    if abs(lev - orders) > 2: probs.append(f'levers orders {lev} != scorecard {orders}')
    a1, a2, a3 = sc['a92_base']['tw'], L('cust_overview')[0]['a92_base'], L('ad_penetration')[0]['a92']
    if len({a1, a2, a3}) > 1: probs.append(f'A92 differs: scorecard {a1}, customer {a2}, AD {a3}')
    w = [r for r in L('fy_weeks') if r['week_end'] == we]
    if not w or abs(w[0]['actual'] - rev) > 1: probs.append('fy_weeks revenue does not tie to the scorecard')
    if L('cust_overview')[0]['purchased'] != sc['purchasing_customers']['tw']: probs.append('purchasing customers differ')
    if os.path.exists(os.path.join(d, 'cat_books.json')):
        ct = [r for r in L('cat_books') if r['book'] == 'Total'][0]['revenue']
        if abs(ct - rev) > 0.005 * rev: probs.append(f'category total revenue {ct} does not tie to the scorecard {rev}')
    if os.path.exists(os.path.join(d, 'inv_health.json')):
        ih = L('inv_health')[0]
        if not 10e6 < ih['stock_at_cost'] < 100e6: probs.append(f'stock at cost {ih["stock_at_cost"]} out of range')
        it = [r for r in L('inv_books') if r['book'] == 'Total'][0]['stock_at_cost']
        if abs(it - ih['stock_at_cost']) > 1: probs.append('inventory book total does not tie to inventory health')
    if os.path.exists(os.path.join(d, 'mf_channel.json')):
        mc = L('mf_channel'); mt = [r for r in mc if r['channel'] == 'Total'][0]
        if not all(r.get('bridge_rows_ok') for r in mc) or not mt.get('bridge_sums_to_total'): probs.append('media orders bridge does not add up')
        if abs(mt['orders'] - L('mf_headline')[0]['orders']) > 1: probs.append('media channel total orders differ from the headline')
        if not all(r.get('reconciles') for r in L('mf_region')): probs.append('media region sessions do not reconcile to the channel total')
    if os.path.exists(os.path.join(d, 'pr_discounts.json')):
        pt = [r for r in L('pr_discounts') if r['book'] == 'Total'][0]
        if abs(pt['product_revenue'] - rev) > 0.005 * rev: probs.append('price waterfall product revenue does not tie to the scorecard')
        for r in L('pr_index'):
            if not 0.7 < r['ad_index'] < 1.4: probs.append(f'price index {r["pricing_group"]} {r["ad_index"]} out of range')
    if os.path.exists(os.path.join(d, 'cx_nps.json')):
        cn, cr = L('cx_nps')[0], L('cx_responses')
        if not 300 < cn['responses'] < 5000 or not -100 <= cn['nps'] <= 100: probs.append(f'NPS {cn["nps"]} on {cn["responses"]} responses out of range')
        if len(cr) != cn['responses'] or sum(r['has_comment'] for r in cr) != cn['comments']: probs.append('cx_responses does not match the cx_nps counts')
        if sum(r['n'] for r in L('cx_nps_weekly')) != cn['responses']: probs.append('weekly NPS responses do not add to the window')
        if sum(r['n'] for r in L('cx_segments')) != cn['responses']: probs.append('NPS segments do not add to the window')
        codes = {c['rid']: c for c in L('cx_voc_codes')}
        com = [r for r in cr if r['has_comment']]
        if any(r['rid'] not in codes for r in com): probs.append('some comments have no theme code - run the comment classification step')
        if any(r['rid'] in codes and codes[r['rid']]['band'] != r['band'] for r in com): probs.append('theme codes disagree with response bands')
        if sum(t['comments'] for t in L('cx_themes')) != len(com): probs.append('theme counts do not add to the comments')
        if L('cx_driver')[0]['coded_comments'] != len(com): probs.append('driver base does not match the comments')
        bad = [c['rid'] for c in codes.values() if not re.match(r'^[a-z][a-z ]{1,58}[a-z]$', c['sub_issue'])]
        if bad: probs.append(f'{len(bad)} sub-issues are not plain generic words - recode them')
    if os.path.exists(os.path.join(d, 'cx_contacts.json')):
        ck = L('cx_contacts')[0]
        ref = ck.get('closed_orders_ref_tw')
        if not ref or abs(ck['orders_tw'] - ref) > 0.01 * ref: probs.append(f'cx_contacts closed orders {ck["orders_tw"]} differ from the independent closed-order count {ref} by more than 1%')
        if abs(ck['orders_tw'] - orders) > 0.10 * orders: probs.append(f'cx_contacts closed orders {ck["orders_tw"]} are more than 10% away from the scorecard created orders {orders}')
        if not 1000 < ck['contacts_tw'] < 20000: probs.append(f'contacts {ck["contacts_tw"]} out of range')
    if os.path.exists(os.path.join(d, 'mf_acq_channels.json')):
        at = [r for r in L('mf_acq_channels') if r['acquisition_channel'] == 'Total'][0]
        mhd = L('mf_headline')[0]
        if abs(at['sessions'] - mhd['sessions']) > 0.001 * mhd['sessions'] or abs(at['orders'] - mhd['orders']) > 0.001 * mhd['orders']: probs.append('acquisition channel totals do not reconcile to the funnel headline')
    if os.path.exists(os.path.join(d, 'cx_csat_handler.json')):
        ca = [r for r in L('cx_csat_handler') if r['handler'] == 'All'][0]
        parts = sum(r['conversations_13w'] for r in L('cx_csat_handler') if r['handler'] != 'All')
        if parts != ca['conversations_13w']: probs.append('CSAT handler rows do not add to the total')
        if not 0 < ca['ratings_13w'] < 20000 or not 0 <= (ca['csat_pct_13w'] or 0) <= 100: probs.append('CSAT out of range')
    if os.path.exists(os.path.join(d, 'mf_sem_category.json')) and os.path.exists(os.path.join(d, 'mf_acq_channels.json')):
        smt = [r for r in L('mf_sem_category') if r['campaign_category'] == 'Total'][0]
        ps = sum(r['spend'] or 0 for r in L('mf_acq_channels') if r['acquisition_channel'] in ('Generic Paid Search', 'Branded Paid Search'))
        if abs((smt['spend'] or 0) + (smt.get('excluded_spend') or 0) - ps) > 1: probs.append('SEM by category spend does not reconcile to paid search channel spend')
    if os.path.exists(os.path.join(d, 'mf_device.json')):
        dv = sum(r['sessions'] for r in L('mf_device')); hs = L('mf_headline')[0]['sessions']
        if abs(dv - hs) > 0.001 * hs: probs.append(f'device sessions {dv} do not reconcile to the funnel headline {hs}')
    print('\n'.join(probs) if probs else f'GATE OK {cal["fy_wk"]} w/e {we}')
    sys.exit(1 if probs else 0)
if __name__ == '__main__':
    c = sys.argv[1]
    if c == 'wrap': print(wrap(open(sys.argv[2]).read()))
    elif c == 'unwrap': unwrap(sys.argv[2], sys.argv[3])
    elif c == 'gate': gate(sys.argv[2])
