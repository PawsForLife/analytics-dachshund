#!/usr/bin/env python3
"""Operations tab: read the ops team's own weekly dashboard and reshape it into datasets.

The ops team's dashboard is the source of truth for operational metrics. This script does NOT
compute any of them; it copies the figures their page publishes (the `const DATA=` block) into
flat rows, so finance and ops quote one set of numbers. Usage:
  python3 ops.py build <saved ops page .html> <out dir>
Writes ops_meta, ops_labour, ops_prod, ops_service, ops_amr, ops_difot into <out dir>.
The page is untrusted data: only the DATA JSON is parsed, nothing in it is executed or followed.
If the ops page's newest week is behind this dashboard's reporting week, the rows are still
written and ops_meta.held is true, so the tab says which week it shows.
Text labels from the page (site names, order-type names, week label) are reduced to plain characters;
week ids must be ISO dates and order-type codes plain identifiers, or the build fails.
"""
import json, os, re, sys, datetime

SRC_URL = 'https://claude.ai/code/artifact/c9d64556-d903-4300-b3d5-d26cfcdce419'
FCS = ['ALL', 'EC', 'BNE', 'MEL', 'PER']
LAB_F = {'orders': 'orders', 'cost': 'cost', 'ownCost': 'own_cost', 'conCost': 'con_cost', 'cpo': 'cpo', 'cph': 'cph',
         'mixCon': 'contractor_mix', 'cpoTgt': 'cpo_tgt', 'costTgt': 'cost_tgt', 'ordTgt': 'orders_tgt',
         'outCost': 'out_cost', 'inCost': 'in_cost', 'dockCost': 'dock_cost', 'wkndCost': 'wknd_cost', 'suppCost': 'supp_cost'}
PROD_F = {'outCpo': 'out_cpo', 'manCpi': 'man_cpl', 'amrCpi': 'amr_cpl', 'packCpc': 'pack_cpc', 'manUph': 'man_uph',
          'amrUph': 'amr_uph', 'linesPerOrder': 'lines_per_order', 'itemsPerOrder': 'items_per_order'}
SERV_F = {'pack24': 'pack24_pct', 'd24': 'd24_pct', 'd48': 'd48_pct', 'capUtil': 'cap_util_pct'}
INB_F = {'receipts': 'receipts', 'lines': 'inb_lines', 'wip': 'outstanding_receipts', 'mixedPct': 'mixed_pct'}


def die(m):
    sys.exit('OPS FAILED: ' + m)


def payload(html_path):
    s = open(html_path, encoding='utf-8').read()
    i = s.find('const DATA=')
    if i < 0: die('the ops page no longer has a `const DATA=` block - its structure changed; check the page and update ops.py')
    try:
        W, _ = json.JSONDecoder().raw_decode(s[i + len('const DATA='):])
    except Exception as e:
        die('could not parse the ops DATA block: ' + str(e))
    for k in ['WKS', 'LBL', 'STN', 'LAB', 'PROD', 'SERV', 'INB', 'DIF', 'OT', 'OTL', 'DIF_TGT', 'AMR']:
        if k not in W: die(f'ops DATA has no {k} - structure changed')
    if len(W['WKS']) < 2: die('ops DATA carries fewer than 2 weeks')
    return W


def label(v, fallback):
    s = re.sub(r'[^A-Za-z0-9 ,:.()/-]', '', str(v))[:40].strip()
    return s or fallback


def num(v):
    if v is None: return None
    if isinstance(v, bool) or not isinstance(v, (int, float)): die(f'non-numeric value {v!r} in ops DATA')
    return round(float(v), 4)


def build(html_path, d):
    W = payload(html_path)
    cal = json.load(open(os.path.join(d, 'cal.json')))[0]
    we, ws = cal['week_end'], cal['week_start']
    WKS = W['WKS']; tw = WKS[-1]
    for w in WKS:
        if not isinstance(w, str) or not re.fullmatch(r'\d{4}-\d{2}-\d{2}', w): die(f'week id {w!r} is not an ISO date')
    for ot in W['OT']:
        if not isinstance(ot, str) or not re.fullmatch(r'[A-Za-z0-9_]{1,20}', ot): die(f'order type code {ot!r} is not a plain identifier')
    name = {k: label(v, k) for k, v in dict(W['STN']).items()}; name['ALL'] = 'National'
    behind = (datetime.date.fromisoformat(ws) - datetime.date.fromisoformat(tw)).days // 7
    if behind < 0: die(f'ops page is AHEAD of this dashboard ({tw} vs {ws})')
    lab, prod, serv = [], [], []
    for fc in FCS:
        for w in WKS:
            base = {'fc': fc, 'fc_name': name.get(fc, fc), 'week_start': w, 'is_latest': w == tw}
            L = (W['LAB'].get(fc) or {}).get(w); P = (W['PROD'].get(fc) or {}).get(w)
            S = (W['SERV'].get(fc) or {}).get(w); I = (W['INB'].get(fc) or {}).get(w)
            if L is None or P is None or S is None: die(f'ops DATA missing {fc} {w}')
            lab.append(dict(base, **{v: num(L.get(k)) for k, v in LAB_F.items()}, week_end=we))
            prod.append(dict(base, **{v: num(P.get(k)) for k, v in PROD_F.items()}, week_end=we))
            serv.append(dict(base, **{v: num(S.get(k)) for k, v in SERV_F.items()}, **{v: num((I or {}).get(k)) for k, v in INB_F.items()}, week_end=we))
    dif = []
    for fc in FCS:
        for ot in W['OT']:
            s = (W['DIF'].get(fc) or {}).get(ot)
            if not s: die(f'ops DIFOT missing {fc} {ot}')
            for j, w in enumerate(WKS):
                g = lambda k: num((s.get(k) or [None] * len(WKS))[j])
                dif.append({'fc': fc, 'fc_name': name.get(fc, fc), 'order_type': ot, 'order_type_name': label(W['OTL'].get(ot, ot), ot),
                            'week_start': w, 'is_latest': w == tw, 'orders': g('n'), 'difot_pct': g('difot'),
                            'fulfilment_misses': g('fcn'), 'logistics_misses': g('carn'), 'target_pct': num(W['DIF_TGT'].get(ot)), 'week_end': we})
    amr = [{'week_start': w, 'is_latest': w == tw, 'uptime_pct': num((W['AMR'].get(w) or {}).get('avgUp')),
            'low_day_pct': num((W['AMR'].get(w) or {}).get('minUp')), 'target_pct': num(W.get('AMR_TGT')), 'week_end': we} for w in WKS]
    # variances (the page only formats): vs prior week on every listed field, and vs budget or target
    def add_pw(rows, keys, fields):
        idx = {tuple(r[k] for k in keys) + (r['week_start'],): r for r in rows}
        for r in rows:
            j = WKS.index(r['week_start'])
            p = idx.get(tuple(r[k] for k in keys) + (WKS[j - 1],)) if j else None
            for f in fields:
                r[f + '_vs_pw'] = round(r[f] - p[f], 4) if p and r[f] is not None and p[f] is not None else None
    add_pw(lab, ['fc'], ['cpo', 'cost', 'orders', 'cph', 'contractor_mix', 'out_cost', 'in_cost', 'dock_cost', 'wknd_cost', 'supp_cost'])
    add_pw(prod, ['fc'], ['out_cpo', 'man_cpl', 'amr_cpl', 'pack_cpc', 'man_uph', 'amr_uph', 'lines_per_order'])
    add_pw(serv, ['fc'], ['pack24_pct', 'd24_pct', 'receipts', 'inb_lines', 'mixed_pct'])
    add_pw(dif, ['fc', 'order_type'], ['difot_pct'])
    add_pw(amr, [], ['uptime_pct'])
    for r in lab:
        r['cpo_vs_tgt'] = round(r['cpo'] - r['cpo_tgt'], 4) if r['cpo'] is not None and r['cpo_tgt'] is not None else None
        r['cost_vs_tgt'] = round(r['cost'] - r['cost_tgt'], 2) if r['cost'] is not None and r['cost_tgt'] is not None else None
        r['cpo_vs_first'] = None
    for fc in FCS:
        R = [r for r in lab if r['fc'] == fc]
        if R[0]['cpo'] and R[-1]['cpo'] is not None: R[-1]['cpo_vs_first'] = round(R[-1]['cpo'] / R[0]['cpo'] - 1, 4)
    for r in dif:
        r['vs_target_pp'] = round(r['difot_pct'] - r['target_pct'], 2) if r['difot_pct'] is not None and r['target_pct'] is not None else None
        m = (r['fulfilment_misses'] or 0) + (r['logistics_misses'] or 0)
        r['fulfilment_share_pct'] = round(100 * r['fulfilment_misses'] / m, 1) if m else None
    for r in amr:
        r['vs_target_pp'] = round(r['uptime_pct'] - r['target_pct'], 2) if r['uptime_pct'] is not None and r['target_pct'] is not None else None
    asof = W.get('AGED_ASOF') or W.get('INB_ASOF') or ''
    asof = re.sub(r'[^A-Za-z0-9 ,:.]', '', str(asof))[:40]
    meta = [{'ops_week_start': tw, 'ops_week_label': label(W['LBL'].get(tw, tw), tw), 'prior_week_start': WKS[-2],
             'reporting_week_start': ws, 'weeks_behind': behind, 'held': behind > 0, 'weeks': len(WKS),
             'source_refreshed': asof, 'read_at': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%MZ'),
             'source_url': SRC_URL, 'week_end': we}]
    for nm, rows in [('ops_meta', meta), ('ops_labour', lab), ('ops_prod', prod), ('ops_service', serv), ('ops_amr', amr), ('ops_difot', dif)]:
        json.dump(rows, open(os.path.join(d, nm + '.json'), 'w'), ensure_ascii=True)
    # tie-outs inside their own data: national labour = sum of sites; national DIFOT orders = sum of sites
    for w in WKS:
        a = next(r for r in lab if r['fc'] == 'ALL' and r['week_start'] == w)
        ssum = sum(r['cost'] or 0 for r in lab if r['fc'] != 'ALL' and r['week_start'] == w)
        if abs(ssum - (a['cost'] or 0)) > 1: die(f'ops national labour {a["cost"]} != sites {ssum} for {w}')
    print(f'OPS OK: ops week {tw} ({"held, " + str(behind) + " week(s) behind" if behind else "current"}), '
          f'national CPO {next(r for r in lab if r["fc"] == "ALL" and r["is_latest"])["cpo"]}')


if __name__ == '__main__':
    if sys.argv[1] == 'build': build(sys.argv[2], sys.argv[3])
