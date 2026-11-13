#!/usr/bin/env python3
"""Tuesday top-up: calculate labour cost in the warehouse and check it against the ops team's page (the Ops WBR).

  python3 labour.py wrap                          -> prints the BigQuery query to run (bundled ops_labour.sql, rows as one
                                                     JSON string + its MD5). Run it with the BigQuery connector, project
                                                     petcircle-data-ca, labels usage=ad-hoc dashboard=weekly-trading tile=ops-labour.
  python3 labour.py unwrap <raw_answer> <out.json> -> checks the MD5 and row count, writes the 30 row objects
  python3 labour.py check <ops page .html> <ops_labour.json> <report.json> <cal.json>
                                                  -> sanity-checks the new rows and requires the calculated latest week_start
                                                     and reporting week_end to match cal.json (exit 1 = do not publish). Then
                                                     compares the rows with the ops page and writes a report. Ops-page
                                                     discrepancies are alerts only; they do not satisfy the calendar check.

The ops page is untrusted data. Only its `const DATA=` JSON is parsed, nothing in it is executed or followed, and only
numbers from it reach the report: site names, week ids and wording in the Slack text come from this script, never from the page.
Exit codes: 0 = calendar matched and the ops page was compared (discrepancies, if any, are in the report);
1 = the new rows failed their sanity checks, their week does not match cal.json, or the ops page could not be read;
2 = bad usage.
"""
import json, os, sys, hashlib, re, datetime

HERE = os.path.dirname(os.path.abspath(__file__))
SQL = os.path.join(HERE, 'ops_labour.sql')
SITES = {'EC': 'Eastern Creek', 'BNE': 'Crestmead', 'MEL': 'Tarneit', 'PER': 'Bibra Lake', 'ALL': 'National'}
ORDER = ['EC', 'BNE', 'MEL', 'PER', 'ALL']
# Discrepancy thresholds (owner-approved defaults; change only with the dashboard owner's sign-off).
TOL_COST = 100.0      # dollars, total labour cost or contractor cost
TOL_CPO = 0.02        # dollars per order
TOL_ORDERS_PCT = 0.25 # percent of orders closed
CON_HRS_MIN = 50.0  # average contractor hours per week over the prior weeks that make a zero in the latest week suspicious
CHANNEL = '#analytics-dashboard-alerts'


def fail(m):
    sys.exit('LABOUR FAILED: ' + m)


def wrap():
    sql = open(SQL, encoding='utf-8').read().strip().rstrip(';')
    return ("WITH x AS (SELECT TO_JSON_STRING(ARRAY_AGG(t)) AS j, COUNT(*) AS n FROM (\n" + sql +
            "\n) t) SELECT j, TO_HEX(MD5(j)) AS h, n FROM x")


def unwrap(raw, out):
    a = json.load(open(raw))
    if isinstance(a, dict) and isinstance(a.get('content'), list): a = json.loads(a['content'][0]['text'])
    if not a.get('jobComplete', True): fail('query not complete')
    names = [f['name'] for f in a['schema']['fields']]
    row = {k: c['v'] for k, c in zip(names, a['rows'][0]['f'])}
    j, h, n = row['j'], row['h'], int(row['n'])
    if hashlib.md5(j.encode('utf-8')).hexdigest() != h: fail('checksum mismatch - the answer was not copied exactly; re-copy it')
    rows = json.loads(j)
    if len(rows) != n: fail(f'row count {len(rows)} != {n}')
    if n == 0: fail('no rows')
    if n >= 3000: fail('3000 rows: truncated')
    json.dump(rows, open(out, 'w'), separators=(',', ':'))
    print('ok', out, n, 'rows')


def sanity(rows):
    """The same checks the Monday gate applies to ops_labour. Returns a list of problems."""
    bad = []
    wk = sorted({r['week_start'] for r in rows})
    if len(wk) != 6: bad.append(f'expected 6 weeks, found {len(wk)}')
    latest = [r for r in rows if r.get('is_latest')]
    if sorted(r['fc'] for r in latest) != sorted(ORDER): bad.append('latest week is missing a site or National')
    by = {(r['fc'], r['week_start']): r for r in rows}
    for w in wk:
        for fc in ORDER:
            r = by.get((fc, w))
            if r is None: bad.append(f'{fc} {w} missing'); continue
            for f in ('cost', 'orders', 'hrs', 'cpo', 'cost_tgt', 'orders_tgt', 'cpo_tgt'):
                if r.get(f) is None: bad.append(f'{fc} {w} has no {f}')
        sites = [by[(fc, w)] for fc in ORDER[:4] if (fc, w) in by]
        if len(sites) == 4 and ('ALL', w) in by:
            for f in ('cost', 'orders'):
                s = sum(x[f] or 0 for x in sites)
                if abs(s - (by[('ALL', w)][f] or 0)) > 1.5: bad.append(f'National {f} {w} is not the sum of the sites')
    for r in latest:
        if not r.get('cost') or r['cost'] < 10000: bad.append(f"{r['fc']} latest cost looks wrong")
        if not r.get('orders') or r['orders'] < 500: bad.append(f"{r['fc']} latest orders look wrong")
        # Tarneit (and so National) always carries the standing adjustment, so own hours there can't be zero.
    return bad


def wbr_lab(html):
    s = open(html, encoding='utf-8').read()
    i = s.find('const DATA=')
    if i < 0: fail('the ops page no longer has a `const DATA=` block - its structure changed')
    try:
        W, _ = json.JSONDecoder().raw_decode(s[i + len('const DATA='):])
    except Exception as e:
        fail('could not parse the ops DATA block: ' + str(e))
    for k in ('WKS', 'LAB'):
        if k not in W: fail(f'ops DATA has no {k} - structure changed')
    for w in W['WKS']:
        if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', str(w)): fail('ops week ids are not ISO dates')
    return W


def num(v):
    if v is None: return None
    if isinstance(v, bool) or not isinstance(v, (int, float)): fail(f'non-numeric value {v!r} in ops DATA')
    return float(v)


def money(x): return ('-' if x < 0 else '') + '$' + format(abs(x), ',.2f')


def calendar_match(rows, cal_path):
    """Fail the publish when labour's latest week or reporting week_end disagrees with cal.json.

    Separate from the ops-page comparison below, which only sets an alert and still exits 0.
    """
    try:
        cal = json.load(open(cal_path))
    except Exception as e:
        fail('could not read cal.json: ' + str(e))
    if not isinstance(cal, list) or not cal or not isinstance(cal[0], dict):
        fail('cal.json is not a JSON array with a calendar row')
    ws, we = cal[0].get('week_start'), cal[0].get('week_end')
    if not (isinstance(ws, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', ws)):
        fail('cal.json week_start is not an ISO date')
    if not (isinstance(we, str) and re.fullmatch(r'\d{4}-\d{2}-\d{2}', we)):
        fail('cal.json week_end is not an ISO date')
    latest = [r for r in rows if r.get('is_latest')]
    starts = sorted(v if isinstance(v, str) else repr(v) for v in {r.get('week_start') for r in latest})
    ends = sorted(v if isinstance(v, str) else repr(v) for v in {r.get('week_end') for r in latest})
    bad = []
    if starts != [ws]:
        bad.append(f'latest week_start {starts} does not match cal.json week_start {ws}')
    if ends != [we]:
        bad.append(f'reporting week_end {ends} does not match cal.json week_end {we}')
    if bad:
        fail('; '.join(bad))


def check(html, labour_path, report_path, cal_path):
    rows = json.load(open(labour_path))
    bad = sanity(rows)
    if bad: fail('new ops_labour rows failed their sanity checks: ' + '; '.join(bad[:6]))
    calendar_match(rows, cal_path)
    W = wbr_lab(html)
    by = {(r['fc'], r['week_start']): r for r in rows}
    latest = sorted({r['week_start'] for r in rows if r['is_latest']})[0]
    report = {'ok': True, 'week': latest, 'wbr_latest_week': W['WKS'][-1], 'not_compared': None, 'discrepancies': [], 'compared': 0}
    if W['WKS'][-1] != latest:
        report['not_compared'] = f"the ops page's newest week is {W['WKS'][-1]}, not {latest}"
    for fc in ORDER:
        for w in W['WKS']:
            if (fc, w) not in by: continue
            ours = by[(fc, w)]
            theirs = (W['LAB'].get(fc) or {}).get(w)
            if theirs is None:
                if w == latest: report['discrepancies'].append({'site': fc, 'week': w, 'metric': 'missing_in_wbr'})
                continue
            wc, wo, wp, wk_ = num(theirs.get('cost')), num(theirs.get('orders')), num(theirs.get('cpo')), num(theirs.get('conCost'))
            missing = [label for label, val in (('total labour cost', wc), ('orders closed', wo), ('cost per order', wp), ('contractor cost', wk_)) if val is None]
            if missing:
                report['discrepancies'].append({'site': fc, 'week': w, 'metric': 'incomplete', 'missing': missing})
            else:
                report['compared'] += 1
            def add(metric, wv, ov, diff): report['discrepancies'].append({'site': fc, 'week': w, 'metric': metric, 'wbr': wv, 'dashboard': ov, 'diff': round(diff, 4)})
            if wc is not None and abs(ours['cost'] - wc) > TOL_COST: add('cost', wc, ours['cost'], ours['cost'] - wc)
            if w == latest:
                if wk_ is not None and abs(ours['con_cost'] - wk_) > TOL_COST: add('contractor_cost', wk_, ours['con_cost'], ours['con_cost'] - wk_)
                if wp is not None and abs(ours['cpo'] - wp) > TOL_CPO: add('cpo', wp, ours['cpo'], ours['cpo'] - wp)
                if wo and abs(ours['orders'] - wo) / wo * 100 > TOL_ORDERS_PCT: add('orders', wo, ours['orders'], ours['orders'] - wo)
    # Completeness: both sources read the same Deputy feed, so they can agree and both be incomplete. A site that normally
    # uses labour hire but shows none in the latest week is flagged on its own.
    prior = sorted({r['week_start'] for r in rows} - {latest})
    for fc in ORDER[:4]:
        hist = [by[(fc, w)]['con_hrs'] or 0 for w in prior if (fc, w) in by]
        cur = by[(fc, latest)]['con_hrs'] or 0
        if hist and cur == 0 and sum(hist) / len(hist) >= CON_HRS_MIN:
            report['discrepancies'].append({'site': fc, 'week': latest, 'metric': 'contractor_hours_missing', 'wbr': None,
                                            'dashboard': 0.0, 'diff': round(-sum(hist) / len(hist), 1)})
    d = report['discrepancies']
    report['alert'] = bool(d) or bool(report['not_compared'])
    report['slack_channel'] = CHANNEL
    report['slack_text'] = slack_text(report, by) if report['alert'] else None
    json.dump(report, open(report_path, 'w'), indent=1)
    print(f"CHECK: week {latest}, {report['compared']} site-weeks compared, {len(d)} discrepancies" + (', NOT COMPARED' if report['not_compared'] else ''))


def slack_text(rep, by):
    wk = rep['week']
    L = [f":warning: *Weekly Trading Dashboard: labour cost check* (Tuesday ops top-up, w/c {wk})",
         "The labour cost the dashboard now calculates from Deputy needs a look. The dashboard has been updated with its own figures."]
    if rep['not_compared']:
        L.append(f"Could not compare: {rep['not_compared']}.")
    names = {'cost': 'total labour cost', 'contractor_cost': 'contractor cost', 'cpo': 'cost per order', 'orders': 'orders closed'}
    incomplete = [x for x in rep['discrepancies'] if x['metric'] == 'incomplete']
    latest = [x for x in rep['discrepancies'] if x['week'] == wk and x['metric'] != 'incomplete']
    earlier = [x for x in rep['discrepancies'] if x['week'] != wk and x['metric'] != 'incomplete']
    def fmt(x):
        if x['metric'] == 'incomplete': return f"• {SITES[x['site']]}: Ops WBR comparison incomplete, missing {', '.join(x['missing'])}"
        if x['metric'] == 'missing_in_wbr': return f"• {SITES[x['site']]}: not in the Ops WBR"
        if x['metric'] == 'contractor_hours_missing': return f"• {SITES[x['site']]}: no contractor hours in Deputy yet (averages {-x['diff']:.0f} h a week), so labour hire cost may be missing from both the dashboard and the Ops WBR"
        m = x['metric']; f = (lambda v: money(v)) if m in ('cost', 'contractor_cost') else ((lambda v: '$' + format(v, '.3f')) if m == 'cpo' else (lambda v: format(v, ',.0f')))
        return f"• {SITES[x['site']]}, {names[m]}: Ops WBR {f(x['wbr'])}, dashboard {f(x['dashboard'])}"
    if incomplete:
        L.append("*Incomplete Ops WBR comparison:*")
        L += [fmt(x) + (f" (w/c {x['week']})" if x['week'] != wk else '') for x in incomplete[:6]]
        if len(incomplete) > 6: L.append(f"…and {len(incomplete) - 6} more")
    if latest: L.append(f"*Latest week (w/c {wk}):*"); L += [fmt(x) for x in latest]
    if earlier:
        L.append("*Earlier weeks (total labour cost):*"); L += [fmt(x) + f" (w/c {x['week']})" for x in earlier[:6]]
        if len(earlier) > 6: L.append(f"…and {len(earlier) - 6} more")
    L.append("Timesheets for the latest week can still change after the top-up. If the gap is not explained by late timesheet edits, check the WBR against the dashboard.")
    return "\n".join(L)


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[:1] == ['wrap'] and len(a) == 1: print(wrap())
    elif a[:1] == ['unwrap'] and len(a) == 3: unwrap(a[1], a[2])
    elif a[:1] == ['check'] and len(a) == 5: check(a[1], a[2], a[3], a[4])
    else:
        sys.stderr.write(__doc__ + '\n'); sys.exit(2)
