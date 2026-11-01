#!/usr/bin/env python3
"""Tests for the One Roof eval engine (app/Resources/evals/roof_eval.py, LAB-EVALS).

  python3 tests/test_eval_engine.py            unit tests: offline, no engine needed (seconds)
  ROOF_EVAL_INTEGRATION=1 python3 tests/...    also install the engine into a temp folder and run a tiny task on the
                                               mock model: setup, run, background, status, results, index (needs uv;
                                               the first install downloads packages)
"""
import ast
import re
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ENGINE = ROOT / "app/Resources/evals/roof_eval.py"
TINY = ROOT / "tests/evals/tiny_task.py"


def load(evals_dir: str):
    os.environ["ONEROOF_EVALS_DIR"] = evals_dir
    spec = importlib.util.spec_from_file_location("roof_eval", ENGINE)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class Unit(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-eval-unit-")
        self.e = load(self.tmp)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_task_ref(self):
        self.assertEqual(self.e.task_ref("gsm8k"), "inspect_evals/gsm8k")
        self.assertEqual(self.e.task_ref("inspect_evals/gpqa_diamond"), "inspect_evals/gpqa_diamond")
        self.assertEqual(self.e.task_ref("/x/tiny_task.py"), "/x/tiny_task.py")
        self.assertEqual(self.e.task_name("/x/tiny_task.py"), "tiny_task")

    def test_wilson_interval_is_honest_at_zero_and_small_n(self):
        lo, hi, how = self.e.interval(0.0, 5, 0.0, True)
        self.assertEqual(how, "wilson")
        self.assertEqual(lo, 0.0)
        self.assertAlmostEqual(hi, 0.4345, places=3)  # 0/5 right still allows up to ~43 %
        lo, hi, _ = self.e.interval(0.8, 1000, None, True)
        self.assertLess(hi - lo, 0.06)

    def test_normal_interval_for_unbounded_metrics(self):
        lo, hi, how = self.e.interval(3.0, 50, 0.5, False)
        self.assertEqual(how, "normal")
        self.assertAlmostEqual(lo, 2.02)
        self.assertAlmostEqual(hi, 3.98)

    def test_price_lookup_maps_inspect_names_to_the_price_list(self):
        doc = {"models": {"anthropic/claude-sonnet-5.5": {"input": 2.0, "output": 10.0},
                          "openai/gpt-5-nano": {"input": 0.05, "output": 0.4},
                          "qwen/qwen3-coder": {"input": 0.2, "output": 0.8}}}
        self.assertEqual(self.e.price_for("anthropic/claude-sonnet-5-5", doc)["input"], 2.0)
        self.assertEqual(self.e.price_for("openai/gpt-5-nano", doc)["output"], 0.4)
        self.assertEqual(self.e.price_for("openrouter/qwen/qwen3-coder", doc)["input"], 0.2)
        self.assertTrue(self.e.price_for("mockllm/model", doc)["free"])
        self.assertTrue(self.e.price_for("ollama/llama3", doc)["free"])
        self.assertIsNone(self.e.price_for("nosuch/model", doc))

    def test_estimate_and_cap(self):
        self.e.write_json(self.e.PRICES, {"checked": self.e.now(), "models": {"openai/gpt-5-nano": {"input": 0.05, "output": 0.4}}})
        est = self.e.estimate("gsm8k", "openai/gpt-5-nano", 50, 2)
        self.assertEqual(est["calls"], 100)
        self.assertAlmostEqual(est["usd"], 100 * (1000 * 0.05 + 500 * 0.4) / 1e6)
        self.assertIn("default guess", est["token_basis"])

    def test_estimate_counts_grader_and_sandbox(self):
        """LAB-2012: a benchmark that grades with a second model, run before on this Mac, and a cloud sandbox."""
        import sqlite3
        e = self.e
        e.write_json(e.PRICES, {"checked": e.now(), "models": {"openai/gpt-5-nano": {"input": 0.05, "output": 0.4},
                                                              "z-ai/glm-5.3-flash": {"input": 1.0, "output": 2.0}}})
        with sqlite3.connect(e.DB) as db:
            db.executescript(e.SCHEMA)
            db.execute("INSERT INTO runs (id, task, model, status, started, samples_done, input_tokens, output_tokens, "
                       "sample_seconds) VALUES ('r1','hle','mockllm/model','done','2026-10-31',10,5000,1000,300)")
            db.execute("INSERT INTO model_usage VALUES ('r1','mockllm/model',5000,1000,NULL)")
            db.execute("INSERT INTO model_usage VALUES ('r1','openrouter/z-ai/glm-5.3-flash',10000,2000,0.014)")
        est = e.estimate("hle", "openai/gpt-5-nano", 20, 1, "daytona")
        self.assertEqual(est["grader"]["models"], ["openrouter/z-ai/glm-5.3-flash"])
        # grader: 1,000 in + 200 out per answer × 20 answers at $1 / $2 per million
        self.assertAlmostEqual(est["grader"]["usd"], 20 * (1000 * 1.0 + 200 * 2.0) / 1e6, places=6)
        # sandbox: 30 s per answer × 20 at (1 vCPU + 2 GiB) Daytona rates
        rate = e.SANDBOX_RATES["daytona"]["vcpu_hour"] + 2 * e.SANDBOX_RATES["daytona"]["gib_hour"]
        self.assertAlmostEqual(est["sandbox"]["usd"], round(20 * 30 / 3600 * rate, 4), places=4)
        self.assertAlmostEqual(est["usd"], round(est["model_usd"] + est["grader"]["usd"] + est["sandbox"]["usd"], 4), places=3)
        self.assertGreater(est["cap_check_usd"], est["usd"])          # grader padded ×1.5 for the cap check
        free = e.estimate("hle", "mockllm/model", 20, 1)
        self.assertGreater(free["usd"], 0)                              # a free model still pays its grader
        self.assertNotIn("sandbox", free)                               # this Mac: no sandbox bill

    def test_cost_config_holds_only_names_inspect_used(self):
        """Inspect refuses a cost config naming a model it does not know, so only the run's model and graders seen in
        this task's logs go in (a broad list of every price broke every paid run, caught 10-31)."""
        import sqlite3
        e = self.e
        doc = {"checked": e.now(), "models": {"anthropic/claude-haiku-5.5": {"input": 1, "output": 5},
                                             "z-ai/glm-5.3-flash": {"input": 1, "output": 2}, "aion-labs/aion-2-0": {"input": 1, "output": 1}}}
        self.assertEqual(list(e.cost_config("anthropic/claude-haiku-5-5", "gsm8k", doc)), ["anthropic/claude-haiku-5-5"])
        with sqlite3.connect(e.DB) as db:
            db.executescript(e.SCHEMA)
            db.execute("INSERT INTO runs (id, task, model, status, started, samples_done) VALUES ('r','hle','mockllm/model','done','x',3)")
            db.execute("INSERT INTO model_usage VALUES ('r','openrouter/z-ai/glm-5.3-flash',300,60,NULL)")
        self.assertEqual(sorted(e.cost_config("mockllm/model", "hle", doc)), ["openrouter/z-ai/glm-5.3-flash"])
        self.assertEqual(e.cost_config("mockllm/model", "gsm8k", doc), {})

    def test_named_stderr_pairs_with_its_metric(self):
        sc = [{"scorer": "if", "metric": "final_acc", "value": 0.5}, {"scorer": "if", "metric": "final_stderr", "value": 0.1},
              {"scorer": "m", "metric": "accuracy", "value": 0.4}, {"scorer": "m", "metric": "stderr", "value": 0.05}]
        self.assertEqual(self.e.stderr_for(sc[0], sc), 0.1)
        self.assertEqual(self.e.stderr_for(sc[2], sc), 0.05)
        self.assertTrue(self.e.is_stderr("final_stderr"))
        self.assertTrue(self.e.is_proportion("inst_loose_acc"))
        self.assertFalse(self.e.is_proportion("mean_tokens"))

    def test_runs_never_use_the_callers_folder(self):
        # LAB-1993: a run started from a worktree that was removed mid-run crashed at the end (getcwd), marked failed
        self.assertEqual(self.e.run_cwd({"task_ref": "swe_bench_verified_mini", "dir": "/runs/x"}), "/runs/x")
        self.assertEqual(self.e.run_cwd({"task_ref": str(TINY), "dir": "/runs/x"}), str(TINY.parent))

    def test_the_log_decides_done(self):
        fs = self.e.final_status
        self.assertEqual(fs(1, "success", False), "done")       # scored + logged, then a closing error: still done
        self.assertEqual(fs(0, "error", False), "failed")       # exit 0 with every call failed
        self.assertEqual(fs(1, None, False), "failed")          # never wrote a log
        self.assertEqual(fs(0, "success", True), "cancelled")

    def test_failure_hints(self):
        self.assertIn("Hugging Face", self.e.hint_for("Dataset 'cais/hle' is a gated dataset on the Hub."))
        self.assertIn("several attempts", self.e.hint_for("Reducer 'pass_at_2' requires 2 epochs"))
        self.assertIn("grader", self.e.hint_for("Error code: 401 - Incorrect API key"))
        self.assertIsNone(self.e.hint_for("something else"))

    def test_redact_removes_key_material(self):
        for t in ("Incorrect API key provided: sk-h7Fl4****rOp4. You", "bad AIzaSyA1234567890abcdef here",
                  "fw_3abcdefghijklmnop", "api_key=abc123secret"):
            r = self.e.redact(t)
            for frag in ("sk-h7", "AIzaSy", "fw_3abc", "abc123secret"):
                self.assertNotIn(frag, r)
        self.assertEqual(self.e.redact("plain error"), "plain error")

    def test_providers_need_a_key_file_never_a_value(self):
        r = subprocess.run([sys.executable, str(ENGINE), "providers", "set", "anthropic", "--key-file", "sk-not-a-file"],
                           capture_output=True, text=True, env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        self.assertNotEqual(r.returncode, 0)
        kf = Path(self.tmp) / "k.txt"
        kf.write_text("dummy")
        r = subprocess.run([sys.executable, str(ENGINE), "providers", "set", "anthropic", "--key-file", str(kf)],
                           capture_output=True, text=True, env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        self.assertEqual(r.returncode, 0, r.stderr)
        conf = json.loads((Path(self.tmp) / "providers.json").read_text())
        self.assertEqual(conf["anthropic"]["key_file"], str(kf))
        self.assertNotIn("dummy", (Path(self.tmp) / "providers.json").read_text())
        self.assertEqual(oct((Path(self.tmp) / "providers.json").stat().st_mode & 0o777), "0o600")

    def test_key_file_with_other_text_is_refused(self):
        kf = Path(self.tmp) / "two-lines.txt"
        kf.write_text("my gemini key\nAIzaFAKEFAKEFAKEFAKEFAKE\n")
        self.e.write_json(self.e.PROVIDERS, {"google": {"key_file": str(kf)}})
        with self.assertRaises(SystemExit) as cm:
            self.e.run_env("google/gemini-2.5-flash")
        self.assertEqual(cm.exception.code, 6)
        kf.write_text("AIzaFAKEFAKEFAKEFAKEFAKE\n")
        env = self.e.run_env("google/gemini-2.5-flash")
        self.assertEqual(env["GOOGLE_API_KEY"], "AIzaFAKEFAKEFAKEFAKEFAKE")

    def test_run_refuses_without_engine(self):
        r = subprocess.run([sys.executable, str(ENGINE), "run", "gsm8k", "--model", "mockllm/model"],
                           capture_output=True, text=True, env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        self.assertEqual(r.returncode, 4)
        self.assertIn("roof eval setup", r.stderr)

    def test_starter_shelf_is_well_formed(self):
        s = json.loads((ROOT / "app/Resources/evals/starter.json").read_text())
        self.assertEqual(len(s["shelf"]), 24)
        for b in s["shelf"]:
            self.assertIn(b["category"], s["categories"])
            self.assertTrue(b["teaches"])
        self.assertEqual(len({b["task"] for b in s["shelf"]}), 24)


class XRay(unittest.TestCase):
    """xray.py on a throwaway repo with a known history: Claude adds 10 lines, a person rewrites 4 of them 2 days later,
    Claude's second commit is reverted, and a 'fix' follows Claude's first commit on the same file."""

    def test_churn_revert_fixup(self):
        repo = tempfile.mkdtemp(prefix="roof-xray-")
        self.addCleanup(shutil.rmtree, repo, True)
        base = int(time.time()) - 20 * 86400

        def commit(msg, when_days, trailer=None, author="Pat Person"):
            env = dict(os.environ, GIT_AUTHOR_NAME=author, GIT_AUTHOR_EMAIL="p@x", GIT_COMMITTER_NAME=author,
                       GIT_COMMITTER_EMAIL="p@x", GIT_AUTHOR_DATE=f"{base + when_days * 86400} +0000",
                       GIT_COMMITTER_DATE=f"{base + when_days * 86400} +0000")
            full = msg + (f"\n\nCo-Authored-By: {trailer}" if trailer else "")
            subprocess.run(["git", "-C", repo, "add", "-A"], check=True, env=env)
            subprocess.run(["git", "-C", repo, "commit", "-qm", full], check=True, env=env)
            return subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()

        subprocess.run(["git", "init", "-q", repo], check=True)
        f = Path(repo) / "a.py"
        f.write_text("".join(f"x{i} = {i}\n" for i in range(10)))
        commit("add a", 0, "Claude Opus 5.5 <noreply@anthropic.com>")
        lines = f.read_text().splitlines(keepends=True)
        lines[2:6] = [f"y{i} = {i}\n" for i in range(4)]
        f.write_text("".join(lines))
        commit("fix a: rename", 2)
        (Path(repo) / "b.py").write_text("b = 1\n")
        bad = commit("add b", 3, "Claude Opus 5.5 <noreply@anthropic.com>")
        subprocess.run(["git", "-C", repo, "revert", "--no-edit", bad], check=True,
                       stdout=subprocess.DEVNULL, env=dict(os.environ, GIT_AUTHOR_NAME="Pat", GIT_AUTHOR_EMAIL="p@x", GIT_COMMITTER_NAME="Pat",
                                GIT_COMMITTER_EMAIL="p@x", GIT_AUTHOR_DATE=f"{base + 4 * 86400} +0000",
                                GIT_COMMITTER_DATE=f"{base + 4 * 86400} +0000"))
        r = subprocess.run([sys.executable, str(ROOT / "app/Resources/evals/xray.py"), "--repo", repo, "--days", "30",
                            "--horizon", "7", "--json"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        c = json.loads(r.stdout)["agents"]["Claude"]
        self.assertEqual(c["commits"], 2)
        self.assertEqual(c["lines_added"], 11)
        self.assertAlmostEqual(c["churn"], 5 / 11, places=3)     # 4 lines of a.py rewritten + b.py's line removed by the revert
        self.assertEqual(c["self_churn_share"], 0.0)              # a person did the rewrite and the revert
        self.assertEqual(c["revert_rate"], 0.5)
        self.assertEqual(c["fixup_rate"], 1.0)                    # 'fix a' after 'add a'; the revert after 'add b' 


class IssueCost(unittest.TestCase):
    def test_transcript_usage_sums_tokens_per_model(self):
        spec = importlib.util.spec_from_file_location("xray", ROOT / "app/Resources/evals/xray.py")
        x = importlib.util.module_from_spec(spec); spec.loader.exec_module(x)
        tmp = tempfile.mkdtemp(prefix="roof-cost-"); self.addCleanup(shutil.rmtree, tmp, True)
        t = os.path.join(tmp, "t.jsonl")
        with open(t, "w") as f:
            for u in ({"input_tokens": 10, "output_tokens": 5, "cache_read_input_tokens": 100}, {"input_tokens": 1, "output_tokens": 2}):
                f.write(json.dumps({"message": {"model": "claude-haiku-5-5", "usage": u}}) + "\n")
            f.write(json.dumps({"message": {"model": "<synthetic>", "usage": {"input_tokens": 999}}}) + "\n")
            f.write("not json with usage\n")
        u = x.transcript_usage(t)
        self.assertEqual(dict(u["claude-haiku-5-5"]), {"input": 11, "output": 7, "cache_read": 100, "cache_write": 0})
        self.assertNotIn("<synthetic>", u)
        self.assertEqual(x.transcript_usage(os.path.join(tmp, "missing.jsonl")), {})


class Supervision(unittest.TestCase):
    def test_asks_waits_and_answer_mix_per_agent(self):
        import sqlite3
        spec = importlib.util.spec_from_file_location("xray", ROOT / "app/Resources/evals/xray.py")
        x = importlib.util.module_from_spec(spec); spec.loader.exec_module(x)
        tmp = tempfile.mkdtemp(prefix="roof-sup-"); self.addCleanup(shutil.rmtree, tmp, True)
        store = os.path.join(tmp, "sessions.sqlite")
        db = sqlite3.connect(store)
        db.execute("CREATE TABLE sessions (id TEXT PRIMARY KEY, json TEXT, updated REAL)")
        db.execute("CREATE TABLE decisions (id TEXT PRIMARY KEY, session_id TEXT, kind TEXT, asked_at REAL, answered_at REAL, answer TEXT, agent TEXT)")
        now = time.time()
        for i, (sid, kind, wait, ans) in enumerate([("s1", "other", 5, "reply"), ("s1", "runCommand", 10, "always"),
                                                     ("s2", "other", 60, "reply"), ("s2", "other", None, None)]):
            db.execute("INSERT INTO decisions VALUES (?,?,?,?,?,?,?)",
                       (f"d{i}", sid, kind, now - 3600, (now - 3600 + wait) if wait is not None else None, ans, "codex"))
        db.execute("INSERT INTO decisions VALUES ('old','s3','other',?,?,'reply','codex')", (now - 90 * 86400, now - 90 * 86400 + 1))
        db.commit(); db.close()
        m = x.supervision(store, 30)["agents"]["codex"]
        self.assertEqual(m["asks"], 4)                       # the 90-day-old ask is outside the window
        self.assertEqual(m["sessions_with_asks"], 2)
        self.assertEqual(m["asks_per_session"], 2.0)
        self.assertEqual(m["median_wait_s"], 10)
        self.assertEqual(m["answers"], {"reply": 2, "always": 1, "unanswered": 1})
        self.assertEqual(m["run_command_share"], 0.25)


class EvalSet(unittest.TestCase):
    """evalset.py (LAB-1995) on a throwaway repo with a known history: which fix commits become questions, what the
    model sees, versions that are never edited, the catalog entry and the scorer's path matching."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-evalset-")
        self.repo = tempfile.mkdtemp(prefix="roof-evalset-repo-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(shutil.rmtree, self.repo, True)
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        spec = importlib.util.spec_from_file_location("evalset", ROOT / "app/Resources/evals/evalset.py")
        self.m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.m)
        subprocess.run(["git", "init", "-q", self.repo], check=True)

    def commit(self, msg, files):
        for name, text in files.items():
            p = Path(self.repo) / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)
        env = dict(os.environ, GIT_AUTHOR_NAME="Pat", GIT_AUTHOR_EMAIL="p@x", GIT_COMMITTER_NAME="Pat", GIT_COMMITTER_EMAIL="p@x")
        subprocess.run(["git", "-C", self.repo, "add", "-A"], check=True, env=env)
        subprocess.run(["git", "-C", self.repo, "commit", "-qm", msg], check=True, env=env)

    def history(self):
        self.commit("XYZ-1 · setup", {"src/alpha.py": "a\n", "src/beta.py": "b\n", "src/gamma.py": "g\n",
                                      "tests/test_alpha.py": "t\n"})
        self.commit("XYZ-2 · [demo-bugs] Login button does nothing", {"src/alpha.py": "a2\n", "tests/test_alpha.py": "t2\n"})
        self.commit("XYZ-2 · release page", {"site/page.js": "p\n"})
        self.commit("XYZ-3 · fix beta crash on start", {"src/beta.py": "b2\n"})
        self.commit("XYZ-4 · add a new screen", {"src/gamma.py": "g2\n"})
        self.commit("XYZ-5 · Fix: dark mode colours wrong", {"src/gamma.py": "g3\n"})
        self.commit("XYZ-5 · fix follow-up", {"src/alpha.py": "a3\n"})

    def test_picks_first_fix_per_issue_and_hides_the_answer(self):
        self.history()
        cases, stats = self.m.build_cases(self.repo, 20, 30, None)
        self.assertEqual([c["meta"]["issue"] for c in cases], ["XYZ-5", "XYZ-2"])   # newest issue first
        self.assertEqual(cases[0]["target"], ["src/gamma.py"])     # XYZ-5's FIRST fix, not the follow-up
        self.assertEqual(cases[1]["target"], ["src/alpha.py"])     # tests and site pages are not the fix
        self.assertEqual(stats["left_out_leak"], 1)                # 'fix beta crash' names beta.py
        self.assertEqual(stats["left_out_not_a_fix"], 1)           # 'add a new screen' (the first commit has no tree before it)
        self.assertIn("Login button does nothing", cases[1]["input"])
        self.assertNotIn("XYZ-2 ·", cases[1]["input"].split("\n", 1)[1])   # the tag and key are stripped from the report
        listed = cases[1]["input"].split("Source files:\n", 1)[1].splitlines()
        self.assertEqual(listed, ["src/alpha.py", "src/beta.py", "src/gamma.py"])   # the tree before the fix, no tests

    def test_versions_are_never_edited(self):
        self.history()
        cases, stats = self.m.build_cases(self.repo, 20, 30, None)
        d1, new1 = self.m.write_set("demo", self.repo, cases, stats, 30)
        before = (d1 / "cases.jsonl").read_text()
        d1b, new1b = self.m.write_set("demo", self.repo, cases, stats, 30)
        self.assertTrue(new1)
        self.assertEqual((d1b, new1b), (d1, False))                # same tasks: the last version is reused
        self.commit("XYZ-6 · [demo-bugs] Save loses the title", {"src/beta.py": "b3\n"})
        cases2, stats2 = self.m.build_cases(self.repo, 20, 30, None)
        d2, new2 = self.m.write_set("demo", self.repo, cases2, stats2, 30)
        self.assertEqual((d2.name, new2), ("v2", True))
        self.assertEqual((d1 / "cases.jsonl").read_text(), before)
        entry = self.m.catalog_entries()[0]
        self.assertEqual((entry["folder"], entry["category"], entry["version"]), ("own-demo", "Your evals", "2"))
        self.assertTrue(entry["tasks"][0]["name"].endswith("own_demo_v2.py"))
        self.assertEqual(entry["tasks"][0]["samples"], 3)

    def test_a_damaged_set_is_skipped_not_fatal(self):
        self.history()
        cases, stats = self.m.build_cases(self.repo, 20, 30, None)
        self.m.write_set("good", self.repo, cases, stats, 30)
        bad = Path(self.tmp) / "sets/bad/v1"
        bad.mkdir(parents=True)
        (bad / "set.json").write_text("{not json")
        self.assertEqual([e["folder"] for e in self.m.catalog_entries()], ["own-good"])
        entry = self.m.catalog_entries()[0]
        for k in ("folder", "title", "description", "category", "tasks", "sandbox", "internet", "starter"):
            self.assertIn(k, entry)                                   # every field the app's EvalBenchmark decodes

    def test_frequent_files_floor(self):
        rows = [{"target": ["a"]}, {"target": ["a"]}, {"target": ["b"]}, {"target": ["c"]}, {"target": ["d"]}]
        self.assertEqual(self.m.frequent_files_baseline(rows), 2)   # each 'a' is found from the other 'a'

    def test_scorer_reads_paths_like_a_person_writes_them(self):
        src = self.m.TASK_FILE.format(title="t", repo="r", system="s", func="own_t_v1")
        tree = ast.parse(src)
        ns = {"re": __import__("re")}
        exec(compile(ast.Module([n for n in tree.body if isinstance(n, ast.Assign) and n.targets[0].id == "PATH"]
                                + [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ("named", "hit")],
                                type_ignores=[]), "task", "exec"), ns)
        names = ns["named"]("1. `app/Sources/A.swift`\n- ./app/B.swift (likely)\nC.swift\nnot a path")
        self.assertEqual(names, ["app/Sources/A.swift", "app/B.swift", "C.swift"])
        self.assertTrue(ns["hit"]("C.swift", ["app/x/C.swift"]))
        self.assertFalse(ns["hit"]("C.swift", ["app/x/BC.swift"]))


class Judge(unittest.TestCase):
    """judge.py (LAB-1996): agreement on held-back labels only, TPR/TNR, position consistency, self-preference."""

    def setUp(self):
        spec = importlib.util.spec_from_file_location("judge", ROOT / "app/Resources/evals/judge.py")
        self.j = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.j)

    def doc(self, rows):
        return {"task": "judge_t_v1", "model": "openai/gpt-5-nano",
                "samples": [{"id": i, "answer": v, "metadata": {"item": it, "split": sp, "label": lb}} for i, (it, sp, lb, v) in enumerate(rows)]}

    def test_single_agreement_counts_only_held_back_labels(self):
        rows = [("e1", "example", "pass", "FAIL"),           # an example the judge got wrong: not counted
                ("h1", "held-out", "pass", "PASS"), ("h2", "held-out", "pass", "FAIL"),
                ("h3", "held-out", "fail", "FAIL"), ("h4", "held-out", "fail", "FAIL"),
                ("u1", "unlabelled", None, "PASS")]
        a = self.j.agreement_for("r", self.doc(rows), {"name": "t", "mode": "single", "models": ["anthropic/claude-haiku-5-5"]}, "openai/gpt-5-nano")
        self.assertEqual((a["n"], a["agreement"], a["tpr"], a["tnr"]), (4, 0.75, 0.5, 1.0))
        self.assertEqual(a["judged_pass_rate"], round(2 / 6, 4))   # every answer, labelled or not
        self.assertNotIn("self_preference", a)
        self.assertIn("not yet trustworthy", self.j.render(a))   # 4 held back < 10

    def test_pairwise_counts_a_win_only_when_it_holds_both_ways(self):
        rows = [("q1", "held-out", "a", "A"), ("q1", "held-out", "a", "A"),     # A both orders (already swapped back)
                ("q2", "held-out", "b", "A"), ("q2", "held-out", "b", "B"),     # flips with the order: position bias
                ("q3", "unlabelled", None, "TIE"), ("q3", "unlabelled", None, "TIE")]
        a = self.j.agreement_for("r", self.doc(rows), {"name": "t", "mode": "pairwise", "models": ["openai/gpt-5-nano", "x/y"]}, "openai/gpt-5-nano")
        self.assertEqual((a["a_wins"], a["b_wins"], a["ties"], a["inconsistent"]), (1, 0, 1, 1))
        self.assertEqual(a["position_consistency"], round(2 / 3, 4))
        self.assertEqual((a["n"], a["agreement"]), (2, 0.5))   # q2 inconsistent counts as a miss
        self.assertIn("self_preference", a)                    # the judge also wrote run A's answers

    def test_model_and_code_labels_are_measured_apart_and_named(self):
        def row(it, labs, v):
            return {"id": it, "answer": v, "metadata": {"item": it, "split": "held-out", "labels": labs}}
        doc = {"task": "judge_t_v1", "model": "google/gemini-3.8-flash", "samples": [
            row("1", {"model": "pass", "code": "pass"}, "PASS"), row("2", {"model": "fail", "code": "fail"}, "FAIL"),
            row("3", {"model": "fail", "code": "fail"}, "PASS"), row("4", {"model": "pass", "code": "pass"}, "PASS")]}
        a = self.j.agreement_for("r", doc, {"name": "t", "mode": "single", "models": ["x/haiku"]}, "google/gemini-3.8-flash",
                                 ["anthropic/claude-sonnet-5-5"])
        self.assertEqual(a["reference"], "model:anthropic/claude-sonnet-5-5")   # no owner labels: the model's, named
        self.assertEqual((a["n"], a["agreement"], a["tpr"], a["tnr"]), (4, 0.75, 1.0, 0.5))
        self.assertEqual((a["code"]["fails_what_code_fails"], a["code"]["code_fail"]), (0.5, 2))
        text = self.j.render(a)
        self.assertIn("claude-sonnet-5-5's labels", text)
        self.assertIn("model labels, not yours", text)
        b = self.j.agreement_for("r", doc, {"name": "t", "mode": "single", "models": []}, "anthropic/claude-sonnet-5-5",
                                 ["anthropic/claude-sonnet-5-5"])
        self.assertIn("same_as_labeller", b)

    def test_code_label_reads_the_note_like_the_set_check(self):
        cv = self.j.code_verdict
        self.assertEqual(cv("Open `app/UI/V2/V2LearnCard.swift` first.", "app/UI/DocumentPages.swift\napp/UI/V2/V2LearnCard.swift")[0], "pass")
        self.assertEqual(cv("Look at LearnBlogFeed.swift.", "app/UI/DocumentPages.swift")[0], "fail")

    def test_judge_task_file_parses_and_reads_verdicts(self):
        src = self.j.TASK_FILE.format(name="t", version=1, mode="pairwise", func="judge_t_v1")
        tree = ast.parse(src)
        ns = {"re": __import__("re"), "MODE": "pairwise"}
        exec(compile(ast.Module([n for n in tree.body if isinstance(n, ast.Assign) and n.targets[0].id == "WORDS"]
                                + [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "verdict"],
                                type_ignores=[]), "task", "exec",
                     flags=__import__("__future__").annotations.compiler_flag), ns)   # CI's python3 can be 3.9 (no X | None)
        self.assertEqual(ns["verdict"]("A is clearer.\nVERDICT: B"), "B")
        self.assertEqual(ns["verdict"]("verdict: tie"), "TIE")
        self.assertIsNone(ns["verdict"]("no idea"))


class LmEval(unittest.TestCase):
    """lmeval_adapter.py (LAB-1997): lm-eval's results file becomes a normal run in the index, beside Inspect's."""

    RESULTS = {"results": {"arc_challenge_chat_letter": {"name": "arc_challenge_chat_letter", "sample_len": 100,
               "exact_match,letter": 0.64, "exact_match_stderr,letter": 0.048}},
               "n-samples": {"arc_challenge_chat_letter": {"original": 1172, "effective": 100}},
               "lm_eval_version": "0.4.13", "total_evaluation_time_seconds": "80.5"}

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-lmeval-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        spec = importlib.util.spec_from_file_location("lmeval_adapter", ROOT / "app/Resources/evals/lmeval_adapter.py")
        self.a = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.a)

    def test_results_file_becomes_a_summary(self):
        s = self.a.summary_of(self.RESULTS, "arc_challenge_chat_letter")
        self.assertEqual((s["samples_done"], s["dataset_size"], s["status"]), (100, 1172, "success"))
        self.assertEqual(s["scores"], [{"scorer": "exact_match (letter)", "metrics": {"accuracy": 0.64, "stderr": 0.048}}])

    def test_index_keeps_lm_eval_runs_beside_inspect_runs(self):
        e = load(self.tmp)
        d = Path(self.tmp) / "runs/20261031-200817-lm-eval_arc_challenge_chat_letter-tqat"
        d.mkdir(parents=True)
        (d / "run.json").write_text(json.dumps({"id": d.name, "task": "lm-eval:arc_challenge_chat_letter", "framework": "lm-eval",
                                                "model": "openai-api/local/qwen3-1.7b", "status": "done", "limit": 100,
                                                "summary": self.a.summary_of(self.RESULTS, "arc_challenge_chat_letter")}))
        e.index()
        r = e.results_for(d.name)[0]
        self.assertEqual((r["framework"], r["samples_done"]), ("lm-eval", 100))
        m = r["metrics"][0]
        self.assertEqual((m["metric"], m["value"], m["ci_method"], m["n"]), ("accuracy", 0.64, "wilson", 100))

    def test_letter_task_reads_the_whole_sentence(self):
        y = (ROOT / "app/Resources/evals/lmeval_tasks/arc_challenge_chat_letter.yaml").read_text()
        pat = re.search(r'regex_pattern: "(.+)"', y).group(1).encode().decode("unicode_escape")
        self.assertEqual(re.findall(pat, "The best answer is C")[-1], "C")
        self.assertEqual(re.findall(pat, "The best answer is (B).")[-1], "B")
        self.assertNotIn("include:", y)   # lm-eval resolves include only inside this folder


@unittest.skipUnless(os.environ.get("ROOF_EVAL_INTEGRATION") == "1", "set ROOF_EVAL_INTEGRATION=1")
class Integration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="roof-eval-int-")
        cls.env = dict(os.environ, ONEROOF_EVALS_DIR=cls.tmp)
        r = cls.sh("setup")
        assert r.returncode == 0, r.stderr

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    @classmethod
    def sh(cls, *a):
        return subprocess.run([sys.executable, str(ENGINE), *a], capture_output=True, text=True, env=cls.env)

    def test_foreground_run_scores_and_indexes(self):
        r = self.sh("run", str(TINY), "--model", "mockllm/model", "--limit", "4", "--json")
        self.assertEqual(r.returncode, 0, r.stderr + r.stdout)
        res = json.loads(r.stdout)
        self.assertEqual(res["status"], "done")
        m = res["results"][0]["metrics"][0]
        self.assertEqual((m["metric"], m["n"], m["ci_method"]), ("accuracy", 4, "wilson"))
        self.assertTrue(0 <= m["ci95"][0] <= m["value"] <= m["ci95"][1] <= 1)
        db = Path(self.tmp) / "evals.db"
        db.unlink()
        self.assertEqual(self.sh("index").returncode, 0)  # the logs rebuild the index
        self.assertTrue(json.loads(self.sh("results", res["id"], "--json").stdout)[0]["metrics"])

    def test_background_run_finishes_and_cancel_on_done_is_refused(self):
        r = self.sh("run", str(TINY), "--model", "mockllm/model", "--limit", "4", "--background", "--json")
        rid = json.loads(r.stdout)["id"]
        for _ in range(120):
            st = {x["id"]: x for x in json.loads(self.sh("status", "--json").stdout)}
            if st[rid]["status"] in ("done", "failed"):
                break
            time.sleep(1)
        self.assertEqual(st[rid]["status"], "done")
        self.assertEqual(st[rid]["progress"], "4/4")
        self.assertIn("already done", self.sh("cancel", rid).stdout)

    def test_judge_end_to_end_on_the_mock_model(self):
        r = json.loads(self.sh("run", str(TINY), "--model", "mockllm/model", "--limit", "4", "--json").stdout)
        new = self.sh("judge", "new", "t", "--runs", r["id"], "--rubric", "Correct and short.", "--json")
        self.assertEqual(new.returncode, 0, new.stderr)
        items = [json.loads(x)["id"] for x in (Path(self.tmp) / "judges/t/items.jsonl").read_text().splitlines()]
        for i, it in enumerate(items):
            self.sh("judge", "label", "t", "--item", it, "--verdict", "fail" if i else "pass", "--why", "x")
        b = json.loads(self.sh("judge", "build", "t", "--json").stdout)
        self.assertEqual((b["examples"], b["held_out"], b["questions"]), (0, 4, 4))
        jr = json.loads(self.sh("run", b["task_file"], "--model", "mockllm/model", "--limit", "4", "--json").stdout)
        self.assertEqual(jr["status"], "done")
        a = jr["results"][0]["judge_agreement"]                  # shown with the judged score
        self.assertEqual((a["n"], a["tpr"], a["tnr"]), (4, 0.0, 1.0))   # the mock never says PASS

    def test_background_run_survives_its_starting_folder_being_removed(self):
        # LAB-1993: started from a release worktree that was deleted while the run went on
        start = tempfile.mkdtemp(prefix="roof-eval-cwd-")
        r = subprocess.run([sys.executable, str(ENGINE), "run", str(TINY), "--model", "mockllm/model", "--limit", "4",
                            "--background", "--json"], capture_output=True, text=True, env=self.env, cwd=start)
        shutil.rmtree(start)
        rid = json.loads(r.stdout)["id"]
        for _ in range(120):
            st = {x["id"]: x for x in json.loads(self.sh("status", "--json").stdout)}
            if st[rid]["status"] in ("done", "failed"):
                break
            time.sleep(1)
        self.assertEqual(st[rid]["status"], "done", st[rid])


if __name__ == "__main__":
    unittest.main(verbosity=2)
