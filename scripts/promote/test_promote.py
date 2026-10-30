"""Tests for promote.py. Run with: python3 -m unittest test_promote -v"""
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import promote  # noqa: E402

URL = "https://claude.ai/artifact/LIVELIVELIVE"
HDR = ("-- Dataset: {id}\n-- Title: {title}\n-- Tab: Test\n-- Connector: Google Cloud BigQuery  Tool: execute_sql_readonly\n"
       "-- Project: petcircle-data-ca\n-- Labels: {labels}\n-- Description: {desc}\n\n")


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(text)


def wj(path, obj):
    w(path, json.dumps(obj))


def live_doc(i, q, title=None, desc="d", labels=None):
    args = {"projectId": "petcircle-data-ca", "query": q}
    if labels:
        args["labels"] = labels
    return {"title": title or f"T{i}", "description": desc, "request": {"args": args, "connector": "Google Cloud BigQuery", "tool": "execute_sql_readonly"},
            "source": {"kind": "file", "url": f"/_blob/{i:032x}", "name": f"ds{i}.json"}, "updated": {"at": "x"},
            "lastAttempt": {"ok": True}, "schedule": "weekly", "staleAfterHours": 200}


def repo_sql(i, q, title=None, desc="d", labels="null"):
    return HDR.format(id=f"ds{i}", title=title or f"T{i}", labels=labels, desc=desc) + q + "\n"


def run(*argv):
    out, err, code = io.StringIO(), io.StringIO(), 0
    with redirect_stdout(out), redirect_stderr(err):
        try:
            promote.main(list(argv))
        except SystemExit as e:
            code = e.code or 0
    return code, out.getvalue(), err.getvalue()


class PromoteTests(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        r = self.t.name
        self.repo, self.base, self.exp, self.out = f"{r}/repo", f"{r}/base", f"{r}/exp", f"{r}/out"
        for d in (self.repo, self.base):
            for i in range(3):
                w(f"{d}/sql/ds{i}.sql", repo_sql(i, f"SELECT {i}"))
            w(f"{d}/sql/README.md", "# index")
            w(f"{d}/templates/index.html", "<div></div>")
            w(f"{d}/templates/app.js", "var a=1;")
        for i in range(3):
            wj(f"{self.exp}/datasets/ds{i}.json", live_doc(i, f"SELECT {i}"))
        wj(f"{self.exp}/files/index.html.json", {"text": "<div></div>"})
        wj(f"{self.exp}/files/app.js.json", {"text": "var a=1;"})
        wj(f"{self.exp}/ops/refresh.json", {"runbook": "rb", "ops_py": "MOVED"})
        self.versions = f"{self.t.name}/versions.json"

    def tearDown(self):
        self.t.cleanup()

    def plan(self, *extra, base=True):
        args = ["plan", "--repo", self.repo, "--export", self.exp, "--out", self.out] + list(extra)
        if base:
            args += ["--baseline", self.base]
        return run(*args)

    def plan_json(self):
        return json.load(open(f"{self.out}/plan.json"))

    def test_identical_repo_and_live_is_a_no_op(self):
        code, out, _ = self.plan()
        self.assertEqual(code, 0)
        self.assertEqual(self.plan_json()["changes"], [])

    def test_query_change_is_planned_and_marked_needs_refresh(self):
        w(f"{self.repo}/sql/ds1.sql", repo_sql(1, "SELECT 1, 2"))
        code, out, _ = self.plan()
        self.assertEqual(code, 0)
        ch = self.plan_json()["changes"]
        self.assertEqual([(c["doc_id"], c["fields"], c["needs_refresh"]) for c in ch], [("ds1", ["query"], True)])
        self.assertIn("SELECT 1, 2", open(f"{self.out}/report.txt").read())

    def test_trailing_whitespace_in_live_query_is_not_a_change(self):
        wj(f"{self.exp}/datasets/ds0.json", live_doc(0, "SELECT 0\n\n  "))
        self.plan()
        self.assertEqual(self.plan_json()["changes"], [])

    def test_patch_never_contains_data_fields(self):
        w(f"{self.repo}/sql/ds1.sql", repo_sql(1, "SELECT 9", title="New title", desc="New desc", labels='{"usage": "dashboard"}'))
        self.plan()
        p = json.load(open(f"{self.out}/patches/datasets__ds1.json"))
        self.assertEqual(set(p), {"title", "description", "request"})
        self.assertEqual(p["request"]["args"]["query"], "SELECT 9")
        self.assertEqual(p["request"]["args"]["labels"], {"usage": "dashboard"})
        for forbidden in ("source", "updated", "lastAttempt", "schedule", "staleAfterHours"):
            self.assertNotIn(forbidden, p)

    def test_live_edit_outside_the_repo_is_blocked_as_drift(self):
        wj(f"{self.exp}/datasets/ds2.json", live_doc(2, "SELECT 2 /* hotfix on live */"))
        w(f"{self.repo}/sql/ds2.sql", repo_sql(2, "SELECT 2, 3"))
        code, out, _ = self.plan()
        self.assertEqual(code, 3)
        self.assertIn("DRIFT datasets/ds2.query", out)
        self.assertTrue(self.plan_json()["blocked"])

    def test_without_a_baseline_drift_is_only_a_warning(self):
        w(f"{self.repo}/sql/ds2.sql", repo_sql(2, "SELECT 2, 3"))
        code, out, _ = self.plan(base=False)
        self.assertEqual(code, 0)
        self.assertIn("could not be checked", out)

    def test_new_dataset_in_repo_is_blocked(self):
        w(f"{self.repo}/sql/ds9.sql", repo_sql(9, "SELECT 9"))
        code, out, _ = self.plan()
        self.assertEqual(code, 3)
        self.assertIn("datasets/ds9 is in the repo but not on the live dashboard", out)

    def test_live_only_dataset_is_a_warning_and_untouched(self):
        wj(f"{self.exp}/datasets/extra.json", live_doc(7, "SELECT 7"))
        code, out, _ = self.plan()
        self.assertEqual(code, 0)
        self.assertIn("datasets/extra is on the live dashboard", out)
        self.assertEqual(self.plan_json()["changes"], [])

    def test_page_change_is_planned(self):
        w(f"{self.repo}/templates/app.js", "var a=2;")
        self.plan()
        self.assertEqual([(c["collection"], c["doc_id"]) for c in self.plan_json()["changes"]], [("files", "app.js")])
        self.assertEqual(json.load(open(f"{self.out}/patches/files__app.js.json")), {"text": "var a=2;"})

    def test_oversize_page_is_blocked(self):
        w(f"{self.repo}/templates/app.js", "x" * (300 * 1024))
        code, out, _ = self.plan()
        self.assertEqual(code, 3)
        self.assertIn("over the", out)

    def test_refresh_code_is_not_promoted_unless_asked_and_acknowledged(self):
        w(f"{self.repo}/docs/runbook.md", "new runbook")
        self.plan()
        self.assertEqual(self.plan_json()["changes"], [])
        self.plan("--include-refresh-code")
        ch = self.plan_json()["changes"]
        self.assertEqual(ch[0]["collection"], "ops")
        self.assertTrue(ch[0]["unattended_code"])
        self.assertNotIn("ops_py", json.load(open(f"{self.out}/patches/ops__refresh.json")))
        wj(self.versions, {"ops/refresh": 3})
        code, _, err = run("build", "--out", self.out, "--dashboard-url", URL, "--versions", self.versions,
                           "--release-ref", "t", "--now", "2026-11-03T03:00:00+00:00")   # Tuesday 14:00 Sydney
        self.assertEqual(code, 2)
        self.assertIn("--ack-unattended", err)

    def build(self, now="2026-11-04T03:00:00+00:00", versions=None, extra=()):   # Wednesday 14:00 Sydney
        wj(self.versions, versions if versions is not None else {"datasets/ds1": 5, "files/app.js": 7})
        return run("build", "--out", self.out, "--dashboard-url", URL, "--versions", self.versions,
                   "--release-ref", "weekly-trading/2026-11-04-abc1234", "--commit", "abc1234", "--now", now, *extra)

    def test_build_orders_datasets_before_page_and_pins_versions(self):
        w(f"{self.repo}/sql/ds1.sql", repo_sql(1, "SELECT 1, 2"))
        w(f"{self.repo}/templates/app.js", "var a=2;")
        self.plan()
        code, out, err = self.build()
        self.assertEqual(code, 0, err)
        b = json.load(open(f"{self.out}/batches/batch_01.json"))
        self.assertEqual(b["url"], URL)
        self.assertEqual([(x["collection"], x["doc_id"], x["op"], x.get("if_version")) for x in b["writes"]],
                         [("datasets", "ds1", "update", 5), ("files", "app.js", "update", 7), ("ops", "release", "set", None)])
        rel = json.load(open(f"{self.out}/patches/ops__release.json"))
        self.assertEqual(rel["tag"], "weekly-trading/2026-11-04-abc1234")

    def test_build_refuses_blocked_plan_and_missing_versions(self):
        w(f"{self.repo}/sql/ds9.sql", repo_sql(9, "SELECT 9"))
        self.plan()
        code, _, err = self.build()
        self.assertEqual(code, 2)
        self.assertIn("blocked", err)
        w(f"{self.repo}/sql/ds9.sql", repo_sql(9, "SELECT 9"))
        os.remove(f"{self.repo}/sql/ds9.sql")
        w(f"{self.repo}/sql/ds1.sql", repo_sql(1, "SELECT 1, 2"))
        self.plan()
        code, _, err = self.build(versions={})
        self.assertEqual(code, 2)
        self.assertIn("no version for datasets/ds1", err)

    def test_build_refuses_refresh_windows(self):
        w(f"{self.repo}/sql/ds1.sql", repo_sql(1, "SELECT 1, 2"))
        self.plan()
        code, _, err = self.build(now="2026-11-01T22:30:00+00:00")        # Monday 09:30 Sydney
        self.assertEqual(code, 2)
        self.assertIn("Monday refresh window", err)
        code, _, err = self.build(now="2026-11-02T23:30:00+00:00")        # Tuesday 10:30 Sydney
        self.assertEqual(code, 2)
        self.assertIn("Tuesday Operations top-up window", err)
        code, _, err = self.build(now="2026-11-01T22:30:00+00:00", extra=["--force-window"])
        self.assertEqual(code, 0, err)

    def test_build_uses_update_when_release_doc_already_exists(self):
        w(f"{self.repo}/sql/ds1.sql", repo_sql(1, "SELECT 1, 2"))
        self.plan()
        self.build(versions={"datasets/ds1": 5, "ops/release": 2})
        b = json.load(open(f"{self.out}/batches/batch_01.json"))
        self.assertEqual((b["writes"][-1]["op"], b["writes"][-1]["if_version"]), ("update", 2))

    def test_verify_detects_mismatch_and_passes_when_matching(self):
        code, out, _ = run("verify", "--repo", self.repo, "--export", self.exp)
        self.assertEqual(code, 0)
        self.assertIn("OK", out)
        w(f"{self.repo}/sql/ds0.sql", repo_sql(0, "SELECT 0, 1"))
        code, out, _ = run("verify", "--repo", self.repo, "--export", self.exp)
        self.assertEqual(code, 1)
        self.assertIn("datasets/ds0", out)

    def test_header_problems_are_reported_clearly(self):
        w(f"{self.repo}/sql/ds0.sql", "SELECT 0\n")
        code, _, err = self.plan()
        self.assertEqual(code, 2)
        self.assertIn("ds0.sql", err)

    def test_connector_change_is_blocked(self):
        w(f"{self.repo}/sql/ds0.sql", repo_sql(0, "SELECT 0").replace("Google Cloud BigQuery", "Other"))
        code, out, _ = self.plan()
        self.assertEqual(code, 3)
        self.assertIn("connector/tool differ", out)


if __name__ == "__main__":
    unittest.main()
