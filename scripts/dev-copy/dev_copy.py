#!/usr/bin/env python3
"""Helper for making a private dev copy of a Claude dashboard.

The Claude-side steps (create the artifact, copy assets, write documents) are
done with the Artifact and ArtifactData tools, as described in SKILL.md. This
script does the deterministic parts so they are reviewed, tested and repeatable:

  prepare   read an export of the production dashboard and list the assets to copy
  finalise  rewrite the documents for the dev copy and emit write batches
  verify    check the emitted documents before anything is written

Only the Python standard library is used. Nothing here contacts the network.
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone

BLOB_RE = re.compile(r"^/_blob/([0-9a-f]{32})$")
ARTIFACT_RE = re.compile(r"claude\.ai/(?:code/)?artifact/([A-Za-z0-9_-]+)")
MAX_DOC_BYTES = 256 * 1024      # the dashboard store refuses larger documents
BATCH_SIZE = 50                 # ArtifactData batch limit
ASSET_CHUNK = 10                # asset copy limit per call
DEV_SCHEDULE = "Dev copy: not refreshed automatically. Data is a snapshot of production taken when this copy was made."


class DevCopyError(Exception):
    pass


def artifact_id(url):
    m = ARTIFACT_RE.search(url or "")
    if not m:
        raise DevCopyError(f"Not a claude.ai artifact link: {url!r}")
    return m.group(1)


def unwrap(doc):
    """ArtifactData exports are either the document itself or {id, data, version}."""
    if isinstance(doc, dict) and "data" in doc and isinstance(doc["data"], dict) and (
        "version" in doc or "id" in doc
    ):
        return doc["data"]
    return doc


def load_collection(export_dir, collection):
    d = os.path.join(export_dir, collection)
    docs = {}
    if not os.path.isdir(d):
        return docs
    for name in sorted(os.listdir(d)):
        if name.endswith(".json"):
            with open(os.path.join(d, name), encoding="utf-8") as f:
                docs[name[:-5]] = unwrap(json.load(f))
    return docs


def file_text(doc):
    return doc.get("text") if isinstance(doc, dict) else None


def dataset_assets(datasets):
    """Return ({asset_id: [dataset ids]}, [problems])."""
    assets, problems = {}, []
    for ds_id, doc in datasets.items():
        src = doc.get("source") or {}
        if src.get("kind") != "file":
            problems.append(f"{ds_id}: source kind is {src.get('kind')!r}, not 'file' (live query datasets need no copy)")
            continue
        m = BLOB_RE.match(src.get("url", ""))
        if not m:
            problems.append(f"{ds_id}: source url {src.get('url')!r} is not an internal /_blob/ asset")
            continue
        assets.setdefault(m.group(1), []).append(ds_id)
    return assets, problems


def cmd_prepare(a):
    datasets = load_collection(a.export, "datasets")
    if not datasets:
        raise DevCopyError(f"No datasets found under {a.export}/datasets")
    assets, problems = dataset_assets(datasets)
    ids = sorted(assets)
    chunks = [ids[i:i + ASSET_CHUNK] for i in range(0, len(ids), ASSET_CHUNK)]
    os.makedirs(a.out, exist_ok=True)
    plan = {
        "prod_url": a.prod_url,
        "datasets": len(datasets),
        "assets": len(ids),
        "chunks": chunks,
        "names": {i: (datasets[assets[i][0]].get("source") or {}).get("name") for i in ids},
        "datasets_by_asset": assets,
        "notes": problems,
    }
    with open(os.path.join(a.out, "assets.json"), "w", encoding="utf-8") as f:
        json.dump(plan, f, indent=1)
    print(f"{len(datasets)} datasets, {len(ids)} assets to copy in {len(chunks)} call(s) of up to {ASSET_CHUNK}.")
    for p in problems:
        print("note:", p)
    print(f"Wrote {os.path.join(a.out, 'assets.json')}")


def build_docs(a, asset_map):
    """Return {(collection, doc_id): body} for the dev copy."""
    datasets = load_collection(a.export, "datasets")
    files = load_collection(a.export, "files")
    meta = load_collection(a.export, "dash").get("meta", {})
    if not files.get("index.html") or not file_text(files["index.html"]):
        raise DevCopyError("Export has no files/index.html page")
    assets, _ = dataset_assets(datasets)
    missing = sorted(i for i in assets if i not in asset_map)
    if missing:
        raise DevCopyError(f"{len(missing)} asset(s) have no copy in the map, e.g. {missing[:3]}")
    for old, new in asset_map.items():
        if not BLOB_RE.match(new):
            raise DevCopyError(f"Mapped url for {old} is not a /_blob/ url: {new!r}")

    base_title = meta.get("title") or "Dashboard"
    docs = {("dash", "meta"): {"title": f"DEV: {base_title} ({a.branch})"}}
    for name, doc in files.items():
        docs[("files", name)] = doc
    for ds_id, doc in datasets.items():
        d = json.loads(json.dumps(doc))                    # deep copy
        old = BLOB_RE.match(d["source"]["url"]).group(1)
        d["source"]["url"] = asset_map[old]
        d["schedule"] = DEV_SCHEDULE
        d.pop("staleAfterHours", None)                     # a snapshot would otherwise show as stale
        d.pop("lastAttempt", None)
        docs[("datasets", ds_id)] = d
    docs[("ops", "devcopy")] = {
        "madeFrom": a.prod_url,
        "branch": a.branch,
        "madeAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "note": "Private dev copy. Not read by any scheduled task. Delete when the branch is merged.",
    }
    if a.include_ops:
        for name, doc in load_collection(a.export, "ops").items():
            if name != "devcopy":
                docs[("ops", name)] = doc
    return docs


def cmd_finalise(a):
    if artifact_id(a.dev_url) == artifact_id(a.prod_url):
        raise DevCopyError("The dev URL is the same artifact as production. Refusing to continue.")
    with open(a.map, encoding="utf-8") as f:
        asset_map = json.load(f)
    docs = build_docs(a, asset_map)

    for (col, doc_id), body in docs.items():
        size = len(json.dumps(body).encode("utf-8"))
        if size > MAX_DOC_BYTES:
            raise DevCopyError(f"{col}/{doc_id} is {size} bytes, over the {MAX_DOC_BYTES} byte limit")

    docs_dir = os.path.abspath(os.path.join(a.out, "docs"))
    batch_dir = os.path.abspath(os.path.join(a.out, "batches"))
    os.makedirs(batch_dir, exist_ok=True)
    order = {"dash": 0, "files": 1, "ops": 2, "datasets": 3}
    writes = []
    for (col, doc_id) in sorted(docs, key=lambda k: (order[k[0]], k[1])):
        p = os.path.join(docs_dir, col, f"{doc_id}.json")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as f:
            json.dump(docs[(col, doc_id)], f)
        writes.append({"op": "set", "collection": col, "doc_id": doc_id, "file_path": p})

    names = []
    for i in range(0, len(writes), BATCH_SIZE):
        name = f"batch_{i // BATCH_SIZE + 1:02d}.json"
        with open(os.path.join(batch_dir, name), "w", encoding="utf-8") as f:
            json.dump({"url": a.dev_url, "writes": writes[i:i + BATCH_SIZE]}, f, indent=1)
        names.append(name)
    with open(os.path.join(a.out, "target.json"), "w", encoding="utf-8") as f:
        json.dump({"dev_url": a.dev_url, "prod_url": a.prod_url, "batches": names}, f, indent=1)
    print(f"{len(writes)} documents in {len(names)} batch file(s): {', '.join(names)}")
    print(f"Write them ONLY to {a.dev_url}. Production ({a.prod_url}) must not be written to.")


def cmd_verify(a):
    with open(os.path.join(a.out, "target.json"), encoding="utf-8") as f:
        target = json.load(f)
    with open(a.map, encoding="utf-8") as f:
        asset_map = json.load(f)
    new_urls = set(asset_map.values())
    problems = []
    if artifact_id(target["dev_url"]) == artifact_id(target["prod_url"]):
        problems.append("dev and production URLs are the same artifact")
    seen = {}
    for name in target["batches"]:
        with open(os.path.join(a.out, "batches", name), encoding="utf-8") as f:
            batch = json.load(f)
        if batch["url"] != target["dev_url"]:
            problems.append(f"{name} targets {batch['url']}, not the dev copy")
        if len(batch["writes"]) > BATCH_SIZE:
            problems.append(f"{name} has more than {BATCH_SIZE} writes")
        for w in batch["writes"]:
            seen[(w["collection"], w["doc_id"])] = w["file_path"]
    n_ds = 0
    for (col, doc_id), p in seen.items():
        with open(p, encoding="utf-8") as f:
            body = json.load(f)
        if col == "datasets":
            n_ds += 1
            url = (body.get("source") or {}).get("url")
            if url not in new_urls:
                problems.append(f"datasets/{doc_id} points at {url}, which is not a copied asset")
            if body.get("schedule") != DEV_SCHEDULE or "staleAfterHours" in body:
                problems.append(f"datasets/{doc_id} still carries production refresh settings")
    copied_ids = {BLOB_RE.match(u).group(1) for u in new_urls if BLOB_RE.match(u)}
    if set(asset_map) & copied_ids:
        problems.append("a copied asset has the same id as a production asset; the map looks wrong")
    for need in [("dash", "meta"), ("files", "index.html"), ("ops", "devcopy")]:
        if need not in seen:
            problems.append(f"missing {need[0]}/{need[1]}")
    if problems:
        for p in problems:
            print("PROBLEM:", p)
        sys.exit(1)
    print(f"OK: {len(seen)} documents ({n_ds} datasets) all target the dev copy and reference copied assets only.")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    def common(s):
        s.add_argument("--export", required=True, help="directory holding the exported production documents (datasets/, files/, dash/, ops/)")
        s.add_argument("--out", required=True, help="working directory for generated files")
        s.add_argument("--prod-url", required=True, help="claude.ai link of the production dashboard")

    s = sub.add_parser("prepare"); common(s); s.set_defaults(fn=cmd_prepare)
    s = sub.add_parser("finalise"); common(s)
    s.add_argument("--dev-url", required=True)
    s.add_argument("--map", required=True, help="JSON {production asset id: copied /_blob/ url}")
    s.add_argument("--branch", required=True, help="git branch this copy is for")
    s.add_argument("--include-ops", action="store_true", help="also copy ops/* documents (runbook and helper scripts); off by default because refresh code lives in the repo")
    s.set_defaults(fn=cmd_finalise)
    s = sub.add_parser("verify")
    s.add_argument("--out", required=True)
    s.add_argument("--map", required=True)
    s.set_defaults(fn=cmd_verify)

    a = p.parse_args(argv)
    try:
        a.fn(a)
    except DevCopyError as e:
        print("ERROR:", e, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
