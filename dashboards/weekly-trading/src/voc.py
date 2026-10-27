#!/usr/bin/env python3
"""Comment-theme step of the weekly refresh (CX tab).

The comment TEXT never leaves the run's scratch folder. The dashboard keeps only codes:
dataset cx_voc_codes holds one row per coded comment (rid hash, week, band, themes,
polarity, actionable, a short generic sub-issue). This script:
  todo   out/cx_responses.json out/cx_voc_codes.json text.json todo.json
         -> the comments not yet coded (rid + text), for classification
  merge  out/cx_voc_codes.json coded.json out/cx_responses.json
         -> validates the new codes, adds them, drops codes older than 26 weeks
  build  out  -> writes out/cx_themes.json, out/cx_clusters.json, out/cx_driver.json
  check  out  -> exits 1 with reasons if the codes do not cover the comments exactly
"""
import json, re, sys, math, os, datetime
from collections import Counter, defaultdict

THEMES = {
    'DEL_SPEED': 'Delivery speed', 'DEL_EXEC': 'Delivery execution', 'PACK_DAMAGE': 'Packaging and damage',
    'ORDER_ACCURACY': 'Order accuracy', 'PRICE_VALUE': 'Price and value', 'RANGE_CHOICE': 'Range and choice',
    'AVAILABILITY': 'Availability', 'PROD_QUALITY': 'Product quality', 'AUTO_DELIVERY': 'Auto Delivery mechanics',
    'DIGITAL': 'Website and app', 'SERVICE_CX': 'Customer service', 'RETURNS_REFUNDS': 'Returns and refunds',
    'PROMO_LOYALTY': 'Promotions and loyalty', 'VET_PHARMA': 'Vet and pharmacy', 'GENERAL_POSITIVE': 'General praise',
    'OTHER': 'Other',
}
POL = {'POS', 'NEG', 'MIXED'}
BANDS = {'Promoter', 'Passive', 'Detractor'}
SUB_OK = re.compile(r'^[a-z][a-z ]{1,58}[a-z]$')
MATERIAL = 30   # comments a theme needs before it can be a priority or the driver
KEEP_WEEKS = 26

CLUSTERS = [
    ('WRONG_ADDRESS', 'Delivered to the wrong address', r'wrong (address|house)|to a neighbour'),
    ('LEFT_UNSAFE', 'Parcel left unsafely or exposed', r'left (at|in|on|exposed)|thrown|threw|exposed|in the rain|plain sight|view from street|blocks access|did not close the gate|not carried'),
    ('INSTR_IGNORED', 'Delivery instructions ignored', r'instructions ignored|did not knock|signature request|authority to leave|does not deliver to door'),
    ('PRICE_FEE', 'Price and fee changes', r'price (rise|increased)|prices? (have gone|went) up|delivery fee|delivery charge|shipping cost|subscription price|cannot control auto delivery price|auto delivery price'),
    ('DAMAGED', 'Damaged or split in transit', r'dented|crushed|damaged in transit|opened in transit|broken|split (into|delivery)|smelling'),
    ('LATE', 'Arrived later than promised', r'later than promised|delay|missed next day|still not delivered|waited over|slower than|takes too long'),
    ('NOT_RECEIVED', 'Marked delivered but not received', r'marked delivered|never arrived|lost in transit'),
    ('SUPPORT_REACH', 'Reaching a person in support', r'speak to a person|reach (a human|support)|no phone option'),
    ('AD_CONTROL', 'Auto Delivery control and cancellation', r'cancel|cannot stop|paused order|unwanted repeat|hard to adjust|payment day|ship now'),
    ('DIGITAL_FAIL', 'Website or app failures', r'checkout|logging in|paypal|afterpay|previous invoice'),
    ('WRONG_MISSING', 'Wrong or missing items', r'missing from order|short shipped|part of order|wrong item|someone elses'),
    ('CONDITION', 'Product condition and freshness', r'expiry|shelf life|insect|missing parts'),
    ('STOCK', 'Out of stock and discontinued lines', r'discontinued|sold out|out of stock'),
]


def fold(sub):
    s = (sub or '').lower()
    for k, _, rx in CLUSTERS:
        if re.search(rx, s):
            return k
    return 'ONE_OFF'


def L(p):
    return json.load(open(p))


def D(p, rows):
    json.dump(rows, open(p, 'w'), ensure_ascii=True)


def validate_code(c):
    errs = []
    if c.get('primary') not in THEMES: errs.append('primary theme not in the list')
    if c.get('secondary') not in THEMES and c.get('secondary') != 'NONE': errs.append('secondary theme not in the list')
    if c.get('secondary') == c.get('primary'): errs.append('secondary repeats primary')
    if c.get('polarity') not in POL: errs.append('polarity')
    if c.get('actionable') not in ('Y', 'N'): errs.append('actionable')
    if not SUB_OK.match(c.get('sub_issue') or '') or len((c.get('sub_issue') or '').split()) > 6:
        errs.append('sub_issue must be 2-6 plain lowercase words, no names, numbers or places')
    return errs


def todo(resp_p, codes_p, text_p, out_p):
    have = {c['rid'] for c in L(codes_p)} if os.path.exists(codes_p) else set()
    need = {r['rid'] for r in L(resp_p) if r['has_comment']} - have
    text = {t['rid']: t for t in L(text_p)}
    miss = need - set(text)
    if miss:
        sys.exit(f'{len(miss)} comments missing from the text query')
    rows = [{'rid': rid, 'text': text[rid]['comment_text']} for rid in sorted(need)]
    D(out_p, rows)
    print(f'{len(rows)} comments to classify ({len(have)} already coded)')


def merge(codes_p, coded_p, resp_p):
    codes = L(codes_p) if os.path.exists(codes_p) else []
    resp = {r['rid']: r for r in L(resp_p)}
    new, bad = L(coded_p), []
    have = {c['rid'] for c in codes}
    for c in new:
        e = validate_code(c)
        if c.get('rid') not in resp: e.append('rid not a response in the window')
        elif not resp[c['rid']]['has_comment']: e.append('rid has no comment')
        if c.get('rid') in have: e.append('rid already coded')
        if e: bad.append((c.get('rid'), e))
    if bad:
        for b in bad[:20]: print('BAD', b)
        sys.exit(f'{len(bad)} codes rejected - fix and merge again')
    for c in new:
        r = resp[c['rid']]
        codes.append({'rid': c['rid'], 'week_start': r['week_start'], 'band': r['band'], 'primary': c['primary'],
                      'secondary': c['secondary'], 'polarity': c['polarity'], 'actionable': c['actionable'],
                      'sub_issue': c['sub_issue']})
    we = max(r['week_end'] for r in resp.values())
    cut = (datetime.date.fromisoformat(we) - datetime.timedelta(weeks=KEEP_WEEKS)).isoformat()
    codes = [c for c in codes if c['week_start'] > cut]
    for c in codes: c['week_end'] = we
    codes.sort(key=lambda c: (c['week_start'], c['rid']))
    D(codes_p, codes)
    print(f'merged {len(new)}; store now {len(codes)} codes')


def check(d):
    resp = L(os.path.join(d, 'cx_responses.json'))
    codes = {c['rid']: c for c in L(os.path.join(d, 'cx_voc_codes.json'))}
    probs = []
    com = [r for r in resp if r['has_comment']]
    miss = [r for r in com if r['rid'] not in codes]
    if miss: probs.append(f'{len(miss)} comments in the window have no code - run todo/classify/merge')
    mism = [r for r in com if r['rid'] in codes and (codes[r['rid']]['band'] != r['band'] or codes[r['rid']]['week_start'] != r['week_start'])]
    if mism: probs.append(f'{len(mism)} codes disagree with the response band or week')
    for c in codes.values():
        if validate_code(c): probs.append(f'code {c["rid"]} invalid'); break
    return probs


def pearson(x, y):
    n = len(x); mx, my = sum(x) / n, sum(y) / n
    sx = math.sqrt(sum((a - mx) ** 2 for a in x)); sy = math.sqrt(sum((b - my) ** 2 for b in y))
    return sum((a - mx) * (b - my) for a, b in zip(x, y)) / (sx * sy) if sx and sy else None


def build(d):
    resp = L(os.path.join(d, 'cx_responses.json'))
    codes = {c['rid']: c for c in L(os.path.join(d, 'cx_voc_codes.json'))}
    weekly = L(os.path.join(d, 'cx_nps_weekly.json'))
    we = resp[0]['week_end']
    com = [dict(codes[r['rid']], band=r['band'], week_start=r['week_start']) for r in resp if r['has_comment'] and r['rid'] in codes]
    risk = [c for c in com if c['band'] != 'Promoter']; prom = [c for c in com if c['band'] == 'Promoter']
    nr, np_ = len(risk), len(prom)
    weeks = sorted({w['week_start'] for w in weekly})
    half = len(weeks) // 2
    themes = []
    for code, name in THEMES.items():
        t = [c for c in com if c['primary'] == code]
        if not t: continue
        ar = sum(c['band'] != 'Promoter' for c in t); pr = len(t) - ar
        arr = 100 * ar / nr if nr else 0; prr = 100 * pr / np_ if np_ else 0
        idx = arr / prr if prr else (None if ar == 0 else 99.9)
        if ar and not pr: idx = None
        themes.append({'code': code, 'theme': name, 'at_risk_n': ar, 'at_risk_rate': round(arr, 1), 'promoter_n': pr,
                       'promoter_rate': round(prr, 1), 'over_index': None if idx is None else round(idx, 1),
                       'neg_pct': round(100 * sum(c['polarity'] == 'NEG' for c in t) / len(t)),
                       'mixed_pct': round(100 * sum(c['polarity'] == 'MIXED' for c in t) / len(t)),
                       'actionable_pct': round(100 * sum(c['actionable'] == 'Y' for c in t) / len(t)),
                       'comments': len(t), 'week_end': we})
    key = lambda t: (t['over_index'] if t['over_index'] is not None else 1e9)
    themes.sort(key=key, reverse=True)
    pri = [t for t in themes if t['comments'] >= MATERIAL and (t['over_index'] is None or t['over_index'] > 1)]
    for t in themes:
        oi = t['over_index']
        if t in pri: t['call'] = f'Priority {pri.index(t) + 1}'
        elif oi is None or oi > 1: t['call'] = 'Watch'
        elif oi >= 0.8: t['call'] = 'Neutral'
        else: t['call'] = 'Protected strength'
    for i, t in enumerate(themes): t['sort'] = i + 1
    t0 = themes[0] if not pri else pri[0]
    D(os.path.join(d, 'cx_themes.json'), themes)
    neg = [c for c in com if c['polarity'] in ('NEG', 'MIXED')]
    cc = Counter(fold(c['sub_issue']) for c in neg)
    cl = [{'cluster': n, 'code': k, 'comments': cc[k], 'sort': i + 1, 'week_end': we} for i, (k, n, _) in enumerate(CLUSTERS) if cc[k]]
    cl.sort(key=lambda r: (-r['comments'], r['sort']))
    for i, r in enumerate(cl): r['sort'] = i + 1
    tail = cc['ONE_OFF']
    cl.append({'cluster': 'One-off sub-issues (not shown)', 'code': 'ONE_OFF', 'comments': tail, 'sort': 99, 'week_end': we})
    for r in cl: r['share_of_neg'] = round(100 * r['comments'] / len(neg), 1) if neg else None
    D(os.path.join(d, 'cx_clusters.json'), cl)
    # driver: weekly mention rate of the top priority theme against weekly NPS
    per = defaultdict(lambda: [0, 0])
    for c in com:
        per[c['week_start']][1] += 1
        if c['primary'] == t0['code']: per[c['week_start']][0] += 1
    rate = [100 * per[w][0] / per[w][1] if per[w][1] else 0 for w in weeks]
    nps = [next(x['nps'] for x in weekly if x['week_start'] == w) for w in weeks]
    def hr(ws):
        m = sum(per[w][0] for w in ws); n = sum(per[w][1] for w in ws)
        return round(100 * m / n, 1) if n else None
    r = pearson(rate, nps)
    drv = [{'code': t0['code'], 'theme': t0['theme'], 'call': t0['call'], 'over_index': t0['over_index'],
            'at_risk_rate': t0['at_risk_rate'], 'promoter_rate': t0['promoter_rate'], 'neg_pct': t0['neg_pct'],
            'actionable_pct': t0['actionable_pct'], 'comments': t0['comments'],
            'r_vs_nps': None if r is None else round(r, 2), 'weeks': len(weeks),
            'first_half_rate': hr(weeks[:half]), 'second_half_rate': hr(weeks[-half:]),
            'at_risk_comments': nr, 'promoter_comments': np_, 'neg_mixed_comments': len(neg),
            'coded_comments': len(com), 'material_min': MATERIAL, 'week_end': we}]
    D(os.path.join(d, 'cx_driver.json'), drv)
    print(f'themes {len(themes)}, clusters {len(cl)}, driver {t0["code"]} r={drv[0]["r_vs_nps"]}')


if __name__ == '__main__':
    a = sys.argv[1:]
    if a[0] == 'todo': todo(*a[1:5])
    elif a[0] == 'merge': merge(*a[1:4])
    elif a[0] == 'build': build(a[1])
    elif a[0] == 'check':
        p = check(a[1])
        print('\n'.join(p) if p else 'VOC CHECK OK'); sys.exit(1 if p else 0)
