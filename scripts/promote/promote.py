#!/usr/bin/env python3
"""Promote a dashboard's reviewed code from the repo to the live dashboard.

Updates ONLY code-owned fields of the live dashboard, never data:

  datasets/<id>   title, description, request (the stored query, project, labels)
  files/<name>    text (the page: index.html, app.js, explorer.js)
  ops/refresh     refresh helper code, only with --include-refresh-code

It never touches a dataset's source, updated, lastAttempt, schedule or
staleAfterHours, so releases do not change data. See SKILL.md for the full
procedure; Claude performs the reads and writes, this script decides what to
write and refuses anything unsafe.

  plan    compare the repo with an export of the live dashboard; write a report and patches
  build   turn the plan into version-pinned write batches (refuses unsafe states)
  verify  after promotion, confirm the live dashboard now matches the repo

Standard library only. No network access.
"""
import argparse
import difflib
import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone

MAX_DOC_BYTES = 256 * 1024
BATCH_SIZE = 50
NO_PROMOTE_FILES = {"sql/README.md"}           # repo-only files in sql/
PAGE_FILES = ["index.html", "app.js", "explorer.js"]
# repo file (relative to the dashboard folder) -> field of ops/refresh
REFRESH_CODE = {
    "src/refresh_lib.py": "refresh_lib_py",
    "src/voc.py": "voc_py",
    "config/voc_rubric.md": "voc_rubric",
    "sql/_voc_text.sql.txt": "voc_text_sql",
    "docs/runbook.md": "runbook",
}
ALLOWED = {
    "datasets": {"title", "description", "request"},
    "files": {"text"},
    "ops": {"refresh_lib_py", "voc_py", "voc_rubric", "voc_text_sql", "runbook", "dashboard", "tag", "commit", "promotedAt", "note"},
}
ALLOWED_ARGS = {"projectId", "query", "labels"}
HEADER_RE = re.compile(r"^-- (Dataset|Title|Tab|Connector|Project|Labels|Description): ?(.*)$")
CONN_RE = re.compile(r"^(.*?)\s{2}Tool: (.*)$")


class PromoteError(Exception):
    pass


# ---------- reading ----------
def unwrap(doc):
    if isinstance(doc, dict) and isinstance(doc.get("data"), dict) and ("version" in doc or "id" in doc):
        return doc["data"]
    return doc


def load_collection(export_dir, collection):
    d = os.path.join(export_dir, collection)
    out = {}
    if os.path.isdir(d):
        for n in sorted(os.listdir(d)):
            if n.endswith(".json"):
                with open(os.path.join(d, n), encoding="utf-8") as f:
                    out[n[:-5]] = unwrap(json.load(f))
    return out


def read_text(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()


def parse_sql(text, name="<sql>"):
    """Split a repo SQL file into its header fields and the query."""
    head, sep, body = text.partition("\n\n")
    if not sep:
        raise PromoteError(f"{name}: no blank line after the comment header")
    meta = {}
    for line in head.splitlines():
        m = HEADER_RE.match(line)
        if not m:
            raise PromoteError(f"{name}: unexpected header line {line!r}")
        meta[m.group(1)] = m.group(2)
    for need in ("Dataset", "Title", "Connector", "Project", "Labels", "Description"):
        if need not in meta:
            raise PromoteError(f"{name}: header is missing '{need}'")
    c = CONN_RE.match(meta["Connector"])
    if not c:
        raise PromoteError(f"{name}: cannot read Connector/Tool line")
    labels = json.loads(meta["Labels"])
    return {"id": meta["Dataset"], "title": meta["Title"], "description": meta["Description"],
            "connector": c.group(1), "tool": c.group(2), "projectId": meta["Project"],
            "labels": labels, "query": body.rstrip()}


def load_repo(folder):
    """Return the code in a dashboard folder as plain dicts."""
    sqld = os.path.join(folder, "sql")
    datasets = {}
    if os.path.isdir(sqld):
        for n in sorted(os.listdir(sqld)):
            if n.endswith(".sql"):
                p = parse_sql(read_text(os.path.join(sqld, n)), n)
                if p["id"] != n[:-4]:
                    raise PromoteError(f"{n}: header says dataset {p['id']!r}")
                datasets[p["id"]] = p
    pages, refresh = {}, {}
    for n in PAGE_FILES:
        p = os.path.join(folder, "templates", n)
        if os.path.exists(p):
            pages[n] = read_text(p)
    for rel, field in REFRESH_CODE.items():
        p = os.path.join(folder, rel)
        if os.path.exists(p):
            refresh[field] = read_text(p)
    return {"datasets": datasets, "pages": pages, "refresh": refresh}


def live_view(doc):
    r = doc.get("request") or {}
    a = r.get("args") or {}
    return {"title": doc.get("title"), "description": doc.get("description"),
            "connector": r.get("connector"), "tool": r.get("tool"),
            "projectId": a.get("projectId"), "labels": a.get("labels"),
            "query": (a.get("query") or "").rstrip()}


FIELDS = ["title", "description", "projectId", "labels", "query"]


# ---------- planning ----------
def diff_text(a, b, label):
    return "".join(difflib.unified_diff(a.splitlines(True), b.splitlines(True), f"live {label}", f"repo {label}", n=2))


def make_plan(repo, live_ds, live_files, live_ops, baseline, include_refresh):
    changes, blocks, warns, report = [], [], [], []
    patches = {}

    for ds_id, r in sorted(repo["datasets"].items()):
        doc = live_ds.get(ds_id)
        if doc is None:
            blocks.append(f"datasets/{ds_id} is in the repo but not on the live dashboard. New datasets need a live dataset and its first data file; promotion cannot create them.")
            continue
        if not doc.get("request"):
            blocks.append(f"datasets/{ds_id} has no stored query on the live dashboard but has SQL in the repo.")
            continue
        L = live_view(doc)
        if (L["connector"], L["tool"]) != (r["connector"], r["tool"]):
            blocks.append(f"datasets/{ds_id}: connector/tool differ (live {L['connector']}/{L['tool']}, repo {r['connector']}/{r['tool']}). Promotion does not change these.")
            continue
        diffs = [f for f in FIELDS if L[f] != r[f]]
        if not diffs:
            continue
        for f in diffs:
            if baseline is not None:
                b = baseline["datasets"].get(ds_id)
                if b is not None and L[f] != b[f]:
                    blocks.append(f"DRIFT datasets/{ds_id}.{f}: the live value differs from the last release, so promoting would overwrite a change made outside the repo. Copy it into the repo first.")
        req = json.loads(json.dumps(doc["request"]))
        args = req.setdefault("args", {})
        args["query"] = r["query"]
        args["projectId"] = r["projectId"]
        if r["labels"] is None:
            args.pop("labels", None)
        else:
            args["labels"] = r["labels"]
        patch = {"request": req}
        if "title" in diffs:
            patch["title"] = r["title"]
        if "description" in diffs:
            patch["description"] = r["description"]
        patches[("datasets", ds_id)] = patch
        changes.append({"collection": "datasets", "doc_id": ds_id, "fields": diffs, "needs_refresh": "query" in diffs or "projectId" in diffs})
        if "query" in diffs:
            report.append(f"--- datasets/{ds_id}: query\n" + diff_text(L["query"] + "\n", r["query"] + "\n", ds_id + ".sql"))
        other = [f for f in diffs if f != "query"]
        if other:
            report.append(f"--- datasets/{ds_id}: " + ", ".join(other))

    for ds_id, doc in sorted(live_ds.items()):
        if doc.get("request") and ds_id not in repo["datasets"]:
            warns.append(f"datasets/{ds_id} is on the live dashboard with a query but not in the repo (created or kept live only). It will not be changed.")

    for name, text in sorted(repo["pages"].items()):
        doc = live_files.get(name)
        cur = doc.get("text") if doc else None
        if cur == text:
            continue
        if cur is None:
            blocks.append(f"files/{name} is in the repo but not on the live dashboard.")
            continue
        if baseline is not None and name in baseline["pages"] and cur != baseline["pages"][name]:
            blocks.append(f"DRIFT files/{name}: the live page differs from the last release, so promoting would overwrite a change made outside the repo. Copy it into the repo first.")
        if len(text.encode("utf-8")) > MAX_DOC_BYTES:
            blocks.append(f"files/{name} is over the {MAX_DOC_BYTES} byte limit.")
            continue
        patches[("files", name)] = {"text": text}
        changes.append({"collection": "files", "doc_id": name, "fields": ["text"], "needs_refresh": False})
        n_add = sum(1 for l in difflib.ndiff(cur.splitlines(), text.splitlines()) if l[:1] in "+-")
        report.append(f"--- files/{name}: page changed ({n_add} changed lines)")
    for name in live_files:
        if name in PAGE_FILES and name not in repo["pages"]:
            warns.append(f"files/{name} is on the live dashboard but not in the repo. It will not be changed.")

    if include_refresh:
        cur_ops = live_ops.get("refresh") or {}
        rp = {}
        for field, text in repo["refresh"].items():
            if cur_ops.get(field) != text:
                if baseline is not None and field in baseline["refresh"] and cur_ops.get(field) != baseline["refresh"][field]:
                    blocks.append(f"DRIFT ops/refresh.{field}: live differs from the last release.")
                rp[field] = text
        if rp:
            patches[("ops", "refresh")] = rp
            changes.append({"collection": "ops", "doc_id": "refresh", "fields": sorted(rp), "needs_refresh": False, "unattended_code": True})
            report.append("--- ops/refresh: UNATTENDED CODE changes (run by scheduled tasks): " + ", ".join(sorted(rp)))
    elif any(live_ops.get("refresh", {}).get(f) != t for f, t in repo["refresh"].items() if live_ops.get("refresh")):
        warns.append("Refresh helper code in the repo differs from ops/refresh on the live dashboard. Not promoted (use --include-refresh-code after review).")

    if baseline is None:
        warns.append("No baseline given, so drift (live edits made outside the repo) could not be checked. Pass --baseline with the previous release's folder.")

    for (col, _), p in patches.items():
        bad = set(p) - ALLOWED[col]
        if bad:
            raise PromoteError(f"internal check failed: patch for {col} would write {sorted(bad)}")
        if col == "datasets" and set(p["request"]["args"]) - ALLOWED_ARGS:
            raise PromoteError("internal check failed: patch would write unexpected request args")
    return changes, blocks, warns, report, patches


def cmd_plan(a):
    repo = load_repo(a.repo)
    if not repo["datasets"]:
        raise PromoteError(f"No SQL files found under {a.repo}/sql")
    baseline = load_repo(a.baseline) if a.baseline else None
    changes, blocks, warns, report, patches = make_plan(
        repo, load_collection(a.export, "datasets"), load_collection(a.export, "files"),
        load_collection(a.export, "ops"), baseline, a.include_refresh_code)
    os.makedirs(os.path.join(a.out, "patches"), exist_ok=True)
    for (col, doc_id), p in patches.items():
        with open(os.path.join(a.out, "patches", f"{col}__{doc_id}.json"), "w", encoding="utf-8") as f:
            json.dump(p, f)
    plan = {"changes": changes, "blocks": blocks, "warnings": warns, "blocked": bool(blocks)}
    with open(os.path.join(a.out, "plan.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=1)
    lines = [f"Changes to promote: {len(changes)}"]
    for c in changes:
        lines.append(f"  {c['collection']}/{c['doc_id']}: {', '.join(c['fields'])}")
    nr = [c["doc_id"] for c in changes if c["needs_refresh"]]
    if nr:
        lines.append(f"Datasets whose query changed ({len(nr)}): their data keeps the OLD query's shape until the next refresh runs: {', '.join(nr)}")
    for w in warns:
        lines.append("WARNING: " + w)
    for b in blocks:
        lines.append("BLOCKED: " + b)
    lines.append("")
    lines += report
    text = "\n".join(lines) + "\n"
    with open(os.path.join(a.out, "report.txt"), "w", encoding="utf-8") as f:
        f.write(text)
    print("\n".join(lines[:max(len(lines) - len(report) - 1, 1)]))
    print(f"Full report: {os.path.join(a.out, 'report.txt')}")
    if blocks:
        sys.exit(3)


# ---------- building ----------
def sydney_now(now=None):
    if now:
        t = datetime.fromisoformat(now)
        if t.tzinfo is None:
            t = t.replace(tzinfo=timezone.utc)
    else:
        t = datetime.now(timezone.utc)
    try:
        from zoneinfo import ZoneInfo
        return t.astimezone(ZoneInfo("Australia/Sydney"))
    except Exception:
        return t.astimezone(timezone(timedelta(hours=11)))   # tzdata missing: assume daylight saving


def in_refresh_window(t):
    m = t.hour * 60 + t.minute
    if t.weekday() == 0 and 7 * 60 + 30 <= m < 10 * 60 + 45:     # Monday refresh + freshness check
        return "Monday refresh window (07:30 to 10:45 Sydney)"
    if t.weekday() == 1 and 9 * 60 <= m < 10 * 60 + 45:          # Tuesday Operations top-up
        return "Tuesday Operations top-up window (09:00 to 10:45 Sydney)"
    return None


def cmd_build(a):
    with open(os.path.join(a.out, "plan.json"), encoding="utf-8") as f:
        plan = json.load(f)
    if plan["blocked"]:
        raise PromoteError("The plan is blocked. Resolve every BLOCKED item and run plan again.")
    if not plan["changes"]:
        raise PromoteError("Nothing to promote.")
    w = in_refresh_window(sydney_now(a.now))
    if w and not a.force_window:
        raise PromoteError(f"Inside the {w}. A promotion now can make the scheduled refresh fail. Wait, or pass --force-window if the owner agrees.")
    if any(c.get("unattended_code") for c in plan["changes"]) and not a.ack_unattended:
        raise PromoteError("This promotion changes code that scheduled tasks run unattended. Review it, then pass --ack-unattended.")
    with open(a.versions, encoding="utf-8") as f:
        versions = json.load(f)

    order = {"datasets": 0, "ops": 1, "files": 2}      # data definitions first, the page last
    writes = []
    for c in sorted(plan["changes"], key=lambda c: (order[c["collection"]], c["doc_id"])):
        key = f"{c['collection']}/{c['doc_id']}"
        if key not in versions:
            raise PromoteError(f"versions file has no version for {key}. Read it from the live dashboard (get or list) and add it.")
        writes.append({"op": "update", "collection": c["collection"], "doc_id": c["doc_id"],
                       "file_path": os.path.abspath(os.path.join(a.out, "patches", f"{c['collection']}__{c['doc_id']}.json")),
                       "if_version": int(versions[key])})
    rel = {"dashboard": a.dashboard_url, "tag": a.release_ref, "commit": a.commit or "",
           "promotedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "note": "Written by promote.py. Records what code the live dashboard was last promoted from."}
    rp = os.path.abspath(os.path.join(a.out, "patches", "ops__release.json"))
    with open(rp, "w", encoding="utf-8") as f:
        json.dump(rel, f)
    entry = {"collection": "ops", "doc_id": "release", "file_path": rp}
    if "ops/release" in versions:
        entry.update({"op": "update", "if_version": int(versions["ops/release"])})
    else:
        entry["op"] = "set"
    writes.append(entry)

    os.makedirs(os.path.join(a.out, "batches"), exist_ok=True)
    names = []
    for i in range(0, len(writes), BATCH_SIZE):
        n = f"batch_{i // BATCH_SIZE + 1:02d}.json"
        with open(os.path.join(a.out, "batches", n), "w", encoding="utf-8") as f:
            json.dump({"url": a.dashboard_url, "writes": writes[i:i + BATCH_SIZE]}, f, indent=1)
        names.append(n)
    print(f"{len(writes)} writes in {len(names)} batch file(s): {', '.join(names)}")
    print(f"Write them ONLY to {a.dashboard_url}, in order. Stop at the first failure.")


# ---------- verifying ----------
def cmd_verify(a):
    repo = load_repo(a.repo)
    changes, blocks, warns, _, _ = make_plan(
        repo, load_collection(a.export, "datasets"), load_collection(a.export, "files"),
        load_collection(a.export, "ops"), None, a.include_refresh_code)
    stale = [f"{c['collection']}/{c['doc_id']} ({', '.join(c['fields'])})" for c in changes]
    stale += [b for b in blocks]
    if stale:
        print("The live dashboard does NOT match the repo:")
        for s in stale:
            print("  ", s)
        sys.exit(1)
    print(f"OK: live dashboard matches the repo ({len(repo['datasets'])} queries, {len(repo['pages'])} page files).")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("plan")
    s.add_argument("--repo", required=True, help="the dashboard folder, e.g. dashboards/weekly-trading, at the release being promoted")
    s.add_argument("--export", required=True, help="export of the LIVE dashboard (datasets/, files/, ops/)")
    s.add_argument("--out", required=True)
    s.add_argument("--baseline", help="the same folder at the PREVIOUS release, to detect live edits made outside the repo")
    s.add_argument("--include-refresh-code", action="store_true")
    s.set_defaults(fn=cmd_plan)
    s = sub.add_parser("build")
    s.add_argument("--out", required=True)
    s.add_argument("--dashboard-url", required=True)
    s.add_argument("--versions", required=True, help="JSON {\"datasets/<id>\": version, ...} read from the live dashboard just before writing")
    s.add_argument("--release-ref", required=True, help="the release tag being promoted")
    s.add_argument("--commit", help="the commit the tag points at")
    s.add_argument("--force-window", action="store_true")
    s.add_argument("--ack-unattended", action="store_true")
    s.add_argument("--now", help="ISO time, for tests")
    s.set_defaults(fn=cmd_build)
    s = sub.add_parser("verify")
    s.add_argument("--repo", required=True)
    s.add_argument("--export", required=True, help="a FRESH export of the live dashboard, taken after promotion")
    s.add_argument("--include-refresh-code", action="store_true")
    s.set_defaults(fn=cmd_verify)
    a = p.parse_args(argv)
    try:
        a.fn(a)
    except PromoteError as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
