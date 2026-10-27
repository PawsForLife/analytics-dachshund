"""Tests for dev_copy.py. Run with: python3 -m unittest scripts/dev-copy/test_dev_copy.py"""
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dev_copy  # noqa: E402

PROD = "https://claude.ai/artifact/PRODPRODPRODPROD"
DEV = "https://claude.ai/artifact/DEVDEVDEVDEV"


def hexid(n):
    return f"{n:032x}"


def write(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        json.dump(obj, f)


def make_export(root, n=23, wrapped=False):
    for i in range(n):
        doc = {"title": f"Dataset {i}", "description": "d",
               "source": {"kind": "file", "name": f"ds{i}.json", "format": "json", "url": f"/_blob/{hexid(i + 1)}"},
               "schedule": "Refreshed every Monday", "staleAfterHours": 200,
               "lastAttempt": {"ok": True}, "request": {"args": {"query": "select 1"}}}
        write(f"{root}/datasets/ds{i}.json", {"id": f"ds{i}", "data": doc, "version": 3} if wrapped else doc)
    write(f"{root}/files/index.html.json", {"text": "<div id='dash-root'></div>"})
    write(f"{root}/files/app.js.json", {"text": "var x=1;"})
    write(f"{root}/dash/meta.json", {"title": "Pet Circle Weekly Trading Dashboard"})
    write(f"{root}/ops/refresh.json", {"runbook": "prod runbook"})


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    code = 0
    with redirect_stdout(out), redirect_stderr(err):
        try:
            dev_copy.main(list(argv))
        except SystemExit as e:
            code = e.code or 0
    return code, out.getvalue(), err.getvalue()


class DevCopyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.export = f"{self.root}/export"
        self.out = f"{self.root}/out"
        make_export(self.export)
        self.map_path = f"{self.root}/map.json"
        write(self.map_path, {hexid(i + 1): f"/_blob/{hexid(1000 + i)}" for i in range(23)})

    def tearDown(self):
        self.tmp.cleanup()

    def finalise(self, **kw):
        args = ["finalise", "--export", self.export, "--out", self.out, "--prod-url", PROD,
                "--dev-url", kw.get("dev", DEV), "--map", self.map_path, "--branch", "feature/x"]
        return run(*args)

    def test_prepare_chunks_assets(self):
        code, out, _ = run("prepare", "--export", self.export, "--out", self.out, "--prod-url", PROD)
        self.assertEqual(code, 0)
        plan = json.load(open(f"{self.out}/assets.json"))
        self.assertEqual(plan["assets"], 23)
        self.assertEqual([len(c) for c in plan["chunks"]], [10, 10, 3])
        self.assertEqual(plan["names"][hexid(1)], "ds0.json")

    def test_wrapped_exports_are_read(self):
        make_export(self.export, wrapped=True)
        code, out, _ = run("prepare", "--export", self.export, "--out", self.out, "--prod-url", PROD)
        self.assertEqual(code, 0)
        self.assertIn("23 datasets", out)

    def test_finalise_rewrites_datasets_and_marks_dev(self):
        code, out, err = self.finalise()
        self.assertEqual(code, 0, err)
        ds = json.load(open(f"{self.out}/docs/datasets/ds0.json"))
        self.assertEqual(ds["source"]["url"], f"/_blob/{hexid(1000)}")
        self.assertNotIn("staleAfterHours", ds)
        self.assertNotIn("lastAttempt", ds)
        self.assertIn("Dev copy", ds["schedule"])
        self.assertEqual(ds["request"]["args"]["query"], "select 1")   # query untouched
        meta = json.load(open(f"{self.out}/docs/dash/meta.json"))
        self.assertEqual(meta["title"], "DEV: Pet Circle Weekly Trading Dashboard (feature/x)")

    def test_batches_respect_limit_and_target_dev(self):
        self.finalise()
        target = json.load(open(f"{self.out}/target.json"))
        self.assertEqual(target["dev_url"], DEV)
        total = 0
        for name in target["batches"]:
            b = json.load(open(f"{self.out}/batches/{name}"))
            self.assertLessEqual(len(b["writes"]), 50)
            self.assertEqual(b["url"], DEV)
            total += len(b["writes"])
        self.assertEqual(total, 23 + 2 + 1 + 1)   # datasets + files + meta + devcopy

    def test_ops_refresh_not_copied_unless_asked(self):
        self.finalise()
        self.assertFalse(os.path.exists(f"{self.out}/docs/ops/refresh.json"))
        self.assertTrue(os.path.exists(f"{self.out}/docs/ops/devcopy.json"))

    def test_refuses_production_as_target(self):
        code, _, err = self.finalise(dev=PROD)
        self.assertEqual(code, 2)
        self.assertIn("same artifact", err)

    def test_missing_asset_in_map_is_an_error(self):
        m = json.load(open(self.map_path))
        del m[hexid(5)]
        write(self.map_path, m)
        code, _, err = self.finalise()
        self.assertEqual(code, 2)
        self.assertIn("no copy in the map", err)

    def test_oversize_document_is_an_error(self):
        write(f"{self.export}/files/app.js.json", {"text": "x" * (300 * 1024)})
        code, _, err = self.finalise()
        self.assertEqual(code, 2)
        self.assertIn("over the", err)

    def test_verify_passes_then_catches_tampering(self):
        self.finalise()
        code, out, _ = run("verify", "--out", self.out, "--map", self.map_path)
        self.assertEqual(code, 0)
        self.assertIn("OK: 27 documents", out)
        p = f"{self.out}/docs/datasets/ds3.json"
        ds = json.load(open(p))
        ds["source"]["url"] = f"/_blob/{hexid(4)}"      # a production asset
        write(p, ds)
        code, out, _ = run("verify", "--out", self.out, "--map", self.map_path)
        self.assertEqual(code, 1)
        self.assertIn("datasets/ds3", out)

    def test_non_file_sources_are_reported_not_fatal(self):
        write(f"{self.export}/datasets/live.json", {"title": "Live", "source": {"kind": "query"}})
        code, out, _ = run("prepare", "--export", self.export, "--out", self.out, "--prod-url", PROD)
        self.assertEqual(code, 0)
        self.assertIn("live", out)


if __name__ == "__main__":
    unittest.main()
