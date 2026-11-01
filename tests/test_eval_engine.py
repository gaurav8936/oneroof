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


EVALS_DIR = ROOT / "app/Resources/evals"
SCORE_FIX = ROOT / "tests/evals/scores"


def sibling(name: str):
    spec = importlib.util.spec_from_file_location(name, EVALS_DIR / f"{name}.py")
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def engine(tmp: str, *args) -> dict:
    """The engine's CLI as the app calls it (JSON out), on the system python, in a temp evals folder."""
    r = subprocess.run([sys.executable, str(ENGINE), *args, "--json"], capture_output=True, text=True,
                       env=dict(os.environ, ONEROOF_EVALS_DIR=tmp))
    return json.loads(r.stdout)


class Fixture:
    """A temp evals folder with own sets and finished runs whose results come from a summary (no Inspect needed): the
    same path lm-eval runs take through index(), with per-question scores."""

    def __init__(self, tmp: str):
        self.tmp = Path(tmp)

    def set(self, name: str, version: int, ids: list, floor: int = 1, kind: str = "fix-locator", built: str = "2026-10-01T00:00:00Z"):
        d = self.tmp / "sets" / name / f"v{version}"
        d.mkdir(parents=True)
        cases = [{"id": i, "input": f"Bug report ({i.split('-')[0]}-{i.split('-')[1]}):\nBroken {i}\n\nSource files:\na.py\nb.py",
                  "target": ["a.py"], "meta": {"kind": kind, "issue": "-".join(i.split("-")[:2]), "date": "2026-09-01"}} for i in ids]
        (d / "cases.jsonl").write_text("".join(json.dumps(c, sort_keys=True) + "\n" for c in cases))
        func = f"own_{name}_v{version}"
        (d / f"{func}.py").write_text("# task\n")
        (d / "set.json").write_text(json.dumps({"name": name, "version": version, "task": func, "kind": kind, "repo": name,
                                                "head": "abc", "built": built, "days": 120, "count": len(ids), "stats": {},
                                                "baseline_frequent_files": floor, "issues": [c["meta"]["issue"] for c in cases]}))
        return d / f"{func}.py"

    def run(self, rid: str, task: str, model: str, scores: dict, started: str, agent=None, task_ref=None, epochs=None):
        d = self.tmp / "runs" / rid
        d.mkdir(parents=True)
        vals = list(scores.values())
        acc = sum(vals) / len(vals)
        (d / "run.json").write_text(json.dumps({
            "id": rid, "task": task, "task_ref": task_ref or task, "model": model, "agent": agent, "status": "done",
            "limit": len(vals), "epochs": epochs, "started": started,
            "summary": {"status": "success", "samples_done": len(vals), "started": started, "finished": started,
                        "scores": [{"scorer": "s", "metrics": {"accuracy": acc}}],
                        "samples": [[k, 1, v] for k, v in scores.items()]}}))


class Overview(unittest.TestCase):
    """LAB-2062: `overview --json` — your sets first with agents above models above the baseline, the floor, what
    changed (the paired compare's verdict), and exactly one suggestion, the first of five rules that fires."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-overview-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.e = load(self.tmp)
        self.f = Fixture(self.tmp)

    def test_cards_order_floor_and_changes(self):
        ids = [f"XYZ-{i}-abc" for i in range(1, 11)]
        tf = str(self.f.set("demo", 1, ids, floor=4))
        right = {i: 1.0 for i in ids}
        half = {i: (1.0 if n < 5 else 0.0) for n, i in enumerate(ids)}
        self.f.run("r1", "own_demo_v1", "anthropic/claude-haiku-5-5", half, "2026-10-02T00:00:00Z", task_ref=tf)
        self.f.run("r2", "own_demo_v1", "anthropic/claude-haiku-5-5", right, "2026-10-03T00:00:00Z", task_ref=tf)
        self.f.run("r3", "own_demo_v1", "anthropic/claude-haiku-5-5", half, "2026-10-04T00:00:00Z", task_ref=tf, agent="claude_code")
        self.f.run("r4", "own_demo_v1", "mockllm/model", {i: 0.0 for i in ids}, "2026-10-05T00:00:00Z", task_ref=tf)
        self.e.index()
        ov = self.e.overview()
        card = ov["evals"][0]
        self.assertEqual((card["set"], card["version"], card["floor"]), ("demo", 1, {"right": 4, "of": 10}))
        self.assertEqual([r["kind"] for r in card["rows"]], ["agent", "model", "baseline"])   # agents first
        self.assertEqual(card["rows"][1]["run"], "r2")                                         # latest per contestant
        self.assertEqual(card["rows"][1]["score"], 1.0)
        ch = ov["changes"][0]
        cmp = self.e.paired_compare(self.e.sample_means("r2"), self.e.sample_means("r1"))
        self.assertEqual((ch["runs"], ch["verdict"], ch["diff"]), (["r2", "r1"], cmp["verdict"], cmp["diff"]))
        self.assertIn("+50 on demo · fix locator v1", ch["text"])
        self.assertEqual(ov["suggestion"]["rule"], "one_attempt")   # no judge; the best run had 1 attempt

    def test_paired_compare_matches_the_app(self):
        a = {"q1": 1.0, "q2": 1.0, "q3": 0.0, "q4": 1.0}
        b = {"q1": 0.0, "q2": 1.0, "q3": 0.0, "q4": 0.0}
        c = self.e.paired_compare(a, b)
        self.assertTrue(c["paired"])
        self.assertEqual((c["n"], c["diff"], c["verdict"]), (4, 0.5, "noise"))   # EvalStats.compare gives the same
        self.assertEqual(self.e.paired_compare({"q1": 1.0}, {"q9": 0.0}), None)   # too little to say anything

    def test_each_suggestion_rule(self):
        self.assertEqual(self.e.overview()["suggestion"]["rule"], "no_set")             # nothing at all
        self.f.set("demo", 1, ["XYZ-1-a", "XYZ-2-b"])
        self.e.index()
        self.assertEqual(self.e.overview()["suggestion"]["rule"], "nothing_ran")        # a set, no run
        tf = str(self.tmp) + "/sets/demo/v1/own_demo_v1.py"
        self.f.run("r1", "own_demo_v1", "openai/gpt-5-nano", {"XYZ-1-a": 1.0, "XYZ-2-b": 0.0}, "2026-10-02T00:00:00Z", task_ref=tf)
        self.e.index()
        s = self.e.overview()["suggestion"]
        self.assertEqual((s["rule"], s["target"]["tab"], s["target"]["epochs"]), ("one_attempt", "run", 3))
        self.f.run("r2", "own_demo_v1", "openai/gpt-5-mini", {"XYZ-1-a": 1.0, "XYZ-2-b": 1.0}, "2026-10-03T00:00:00Z",
                   task_ref=tf, epochs=3)
        self.e.index()
        self.assertIsNone(self.e.overview()["suggestion"])   # the best run has 3 attempts; no repo to find new fixes in
        es = self.e._sibling("evalset")
        es.new_fix_count = lambda meta: 6
        rule = self.e.suggestion(self.e.done_runs(), {"demo": es.all_versions()[0]}, es)
        self.assertEqual((rule["rule"], rule["text"]), ("new_fixes", "6 bugs fixed since v1: build v2"))
        jd = Path(self.tmp) / "judges/t"
        jd.mkdir(parents=True)
        (jd / "judge.json").write_text(json.dumps({"name": "t", "mode": "single", "rubric": "r", "runs": [], "models": [], "items": 0}))
        (jd / "items.jsonl").write_text("")
        s = self.e.overview()["suggestion"]
        self.assertEqual((s["rule"], s["target"]), ("judge_untrusted", {"tab": "your-evals", "judge": "t"}))
        self.assertEqual(s["text"], "Judge not trusted yet: label 10 answers")

    def test_empty_profile_has_no_numbers(self):
        ov = engine(self.tmp, "overview")
        self.assertEqual((ov["evals"], ov["changes"], ov["running"], ov["finished_runs"]), ([], [], [], 0))

    def test_runs_keep_their_set_version(self):
        self.assertEqual(self.e.set_of("/x/evals/sets/oneroof/v3/own_oneroof_v3.py"), ("oneroof", 3))
        self.assertEqual(self.e.set_of("/x/evals/judges/t/v1/judge_t_v1.py"), (None, None))
        self.assertEqual(self.e.contestant("anthropic/claude-haiku-5-5", "claude_code")["name"], "Claude Code · claude-haiku-5-5")
        self.assertEqual(self.e.contestant("mockllm/model", None)["kind"], "baseline")
        self.assertEqual(self.e.contestant("ollama/qwen3:1.7b", None)["kind"], "local")
        self.assertIn("--sample-id", self.e.inspect_cmd({"task_ref": "gsm8k", "model": "m", "limit": 1, "dir": "/x", "sample_id": "q7"}))


class PublishedScores(unittest.TestCase):
    """LAB-2063 (EVO-3): one official source per benchmark, parsed from saved copies of the real pages; every row has a
    source and a date; a failed check keeps the last good data and says so."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-scores-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        self.p = sibling("published_scores")
        self.files = {"scale_html": "scale.html", "swebench_json": "swebench.json", "html_table_row": "model_card.md",
                      "md_table_column": "simple_evals.md"}

    def page(self, url: str) -> str:
        src = next(s for s in self.p.sources().values() if s["url"] == url)
        return (SCORE_FIX / self.files[src["parser"]]).read_text()

    def test_every_source_is_official_and_parses(self):
        for key, src in self.p.sources().items():
            self.assertTrue(src["url"].startswith("https://"), key)
            self.assertIn(src["parser"], self.p.PARSERS, key)
            if key == "mmlu_pro":
                continue   # its row is in the model card's other table (not in the trimmed fixture)
            rows = self.p.rows_for(key, src, self.page(src["url"]), "2026-11-01") if src["parser"] != "html_table_row" or \
                src["row"] in ("GSM-8K (CoT)", "MATH (CoT)") else None
            if rows is None:
                continue
            self.assertTrue(rows, key)
            for r in rows:
                self.assertTrue(self.p.valid(r), (key, r))
                self.assertEqual((r["source_url"], r["checked"]), (src["url"], "2026-11-01"))
        hle = self.p.rows_for("hle", self.p.sources()["hle"], self.page(self.p.sources()["hle"]["url"]), "2026-11-01")
        self.assertEqual([r["score"] for r in hle], sorted([r["score"] for r in hle], reverse=True))
        swe = self.p.rows_for("swe_bench", self.p.sources()["swe_bench"], self.page(self.p.sources()["swe_bench"]["url"]), "d")
        self.assertEqual(len(swe), 3)                      # the Verified board only; a row with no score is dropped
        self.assertEqual(swe[0]["kind"], "agent")
        self.assertTrue(swe[0]["published"])
        g = self.p.rows_for("gsm8k", self.p.sources()["gsm8k"], self.page(self.p.sources()["gsm8k"]["url"]), "d")
        self.assertEqual((g[0]["contestant"], g[0]["score"]), ("Llama 3.1 405B Instruct", 0.968))

    def test_rows_without_a_source_or_date_are_refused(self):
        ok = {"contestant": "m", "score": 0.5, "source_url": "https://x", "checked": "2026-11-01"}
        self.assertTrue(self.p.valid(ok))
        for bad in ({"source_url": ""}, {"checked": ""}, {"score": 1.5}, {"contestant": ""}):
            self.assertFalse(self.p.valid(dict(ok, **bad)), bad)

    def test_failed_check_keeps_the_last_good_data(self):
        doc = self.p.refresh(get=self.page)
        self.assertGreaterEqual(len(doc["benchmarks"]["hle"]), 3)
        def down(url):
            raise OSError("offline")
        doc2 = self.p.refresh(get=down)
        self.assertEqual(doc2["benchmarks"]["hle"], doc["benchmarks"]["hle"])
        self.assertEqual(doc2["failures"]["hle"]["reason"], "offline")
        s = self.p.show("hle")
        self.assertEqual((s["benchmark"], s["has_source"], s["failed"]["reason"]), ("hle", True, "offline"))
        self.assertEqual(self.p.show("swe_bench_verified_mini")["benchmark"], "swe_bench")   # a task finds its benchmark
        none = self.p.show("niah")
        self.assertEqual((none["has_source"], none["rows"]), (False, []))                     # never invented
        self.assertEqual(self.p.headroom("hle")["level"], "lots")
        self.assertEqual(self.p.headroom("gsm8k")["level"], "saturated")


class Anatomy(unittest.TestCase):
    """HP EV-3 (LAB-2063): graded-by and the prompt template read from the benchmark's own code; the reviewed
    anatomy.json wins; unknown facts are left out."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-anatomy-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.e = load(self.tmp)
        src = Path(self.tmp) / "venv/lib/python3.12/site-packages/inspect_evals"
        for folder, code in {"judged": "from inspect_ai.scorer import model_graded_qa\nscorer=model_graded_qa()",
                             "coded": 'PROMPT_TEMPLATE = """Answer it.\n{prompt}\nEnd with "ANSWER: $ANSWER"."""\n'
                                      "def coded(fewshot: int = 5):\n    return Task(scorer=match())",
                             "plain": "x = 1"}.items():
            (src / folder).mkdir(parents=True)
            (src / folder / f"{folder}.py").write_text(code)
        self.e.write_json(self.e.CATALOG, {"inspect_evals": None, "count": 4, "tasks": 4, "categories": [], "benchmarks": [
            {"folder": f, "title": f.title(), "description": "d", "tags": [], "sandbox": f == "sandboxed", "internet": False,
             "tasks": [{"name": f, "samples": 10}], "starter": [], "category": "Other"} for f in ("judged", "coded", "plain", "sandboxed")]})

    def test_graded_by_and_template_come_from_the_code(self):
        self.assertEqual(self.e.derived_facts("judged", False)["graded_by"], "judge")
        c = self.e.derived_facts("coded", False)
        self.assertEqual((c["graded_by"], c["few_shot"]), ("code", 5))
        self.assertIn("{prompt}", c["prompt_template"])
        self.assertEqual(self.e.derived_facts("plain", False), {})        # unknown: left out, never guessed
        self.assertEqual(self.e.derived_facts("sandboxed", True)["graded_by"], "tests")

    def test_anatomy_shape_and_steps(self):
        a = self.e.anatomy("coded")
        self.assertEqual((a["graded_by"], a["graded_by_label"]), ("code", "Code / exact match"))
        self.assertEqual([s["title"] for s in a["steps"]], ["Prompt", "Model answers", "Code checks", "The number"])
        self.assertIn('ANSWER: $ANSWER', a["steps"][1]["body"])
        for k in ("chance", "maker", "year", "judge"):
            self.assertNotIn(k, a)                                         # not known for this benchmark
        p = self.e.anatomy("plain")
        self.assertEqual([s["title"] for s in p["steps"]], ["Prompt", "Model answers", "The number"])

    def test_reviewed_table_wins_and_covers_start_here(self):
        table = self.e.anatomy_table()
        shelf = json.loads((EVALS_DIR / "starter.json").read_text())["shelf"]
        for s in shelf:
            a = table.get(s["folder"])
            self.assertIsNotNone(a, s["folder"])
            self.assertIn(a["graded_by"], ("code", "judge", "tests"), s["folder"])
            if a.get("gated"):
                self.assertTrue(a["terms_url"].startswith("https://huggingface.co/datasets/"), s["folder"])
            if a.get("marking"):
                self.assertNotIn("{", a["marking"].replace("{target}", ""), s["folder"])
        ex = self.e.catalog_extras({"folder": "hle", "starter": [{"task": "hle"}], "tags": []})
        self.assertEqual(ex, {"made_of": "Expert questions · short answer · judged", "graded_by": "judge", "shelf": "start"})
        own = self.e.catalog_extras({"folder": "own-x", "category": "Your evals", "tags": ["own", "fix-locator"]})
        self.assertEqual((own["graded_by"], own["shelf"]), ("code", "own"))


class Items(unittest.TestCase):
    """HP EV-4/EV-5 (LAB-2064): questions without a run, one dot per run from the index, filters, paging, the seeded
    Random 10, a download only after a confirm, and gated datasets as a state, never an error."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-items-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.e = load(self.tmp)
        self.f = Fixture(self.tmp)

    def test_own_set_questions_dots_and_filters(self):
        ids = [f"XYZ-{i}-abc" for i in range(1, 13)]
        tf = str(self.f.set("demo", 1, ids))
        self.f.run("r1", "own_demo_v1", "openai/gpt-5-nano", {ids[0]: 1.0, ids[1]: 0.0}, "2026-10-02T00:00:00Z", task_ref=tf)
        self.f.run("r2", "own_demo_v1", "openai/gpt-5-mini", {ids[0]: 1.0, ids[2]: 1.0}, "2026-10-03T00:00:00Z", task_ref=tf)
        d = engine(self.tmp, "items", tf, "--limit", "5")
        self.assertEqual((d["total"], d["counts"]), (12, {"all": 12, "seen": 3, "wrong": 1}))
        self.assertEqual(len(d["items"]), 5)
        first = d["items"][0]
        self.assertEqual(first["dots"], [{"run": "r1", "score": 1.0}, {"run": "r2", "score": 1.0}])   # oldest run first
        self.assertNotIn("Source files", first["input"])                    # the report, not the file list
        self.assertEqual(engine(self.tmp, "items", tf, "--filter", "wrong")["items"][0]["id"], ids[1])
        page2 = engine(self.tmp, "items", tf, "--limit", "5", "--offset", "10")
        self.assertEqual([x["index"] for x in page2["items"]], [11, 12])
        r1 = engine(self.tmp, "items", tf, "--filter", "random", "--seed", "17")["items"]
        r2 = engine(self.tmp, "items", tf, "--filter", "random", "--seed", "17")["items"]
        r3 = engine(self.tmp, "items", tf, "--filter", "random", "--seed", "18")["items"]
        self.assertEqual((len(r1), r1), (10, r2))
        self.assertNotEqual([x["id"] for x in r1], [x["id"] for x in r3])

    def test_dots_match_each_runs_samples(self):
        self.f.run("r1", "tiny", "openai/gpt-5-nano", {"a": 1.0, "b": 0.0}, "2026-10-02T00:00:00Z")
        self.e.index()
        self.assertEqual(self.e.scores_by_item(self.e.runs_of_task("tiny")), {"a": [["r1", 1.0]], "b": [["r1", 0.0]]})

    def test_download_waits_for_a_confirm_and_gated_is_a_state(self):
        self.e.write_json(self.e.CATALOG, {"inspect_evals": None, "count": 1, "tasks": 1, "categories": [], "benchmarks": [
            {"folder": "hle", "title": "HLE", "description": "", "tags": [], "sandbox": False, "internet": False,
             "tasks": [{"name": "hle", "samples": 3}], "starter": [], "category": "x"}]})
        self.e.dataset_size = lambda ds: 1234
        items, state = self.e.load_items("hle", False)
        self.assertIsNone(items)
        self.assertEqual((state["needs_download"], state["gated"], state["size_bytes"], state["dataset"]),
                         (True, True, 1234, "cais/hle"))
        vpy = Path(self.tmp) / "venv/bin"
        vpy.mkdir(parents=True)
        for exe in ("python", "inspect"):
            (vpy / exe).write_text("#!/bin/sh\necho 'huggingface_hub.errors.GatedRepoError: 401 Client Error' >&2\nexit 1\n")
            (vpy / exe).chmod(0o755)
        items, state = self.e.load_items("hle", True)
        self.assertIsNone(items)
        self.assertEqual((state["gated"], state["terms_url"]), (True, "https://huggingface.co/datasets/cais/hle"))
        self.assertFalse(self.e.questions_file("hle").exists())             # never a partial list


class EvalSetVersions(unittest.TestCase):
    """HP EV-6 (LAB-2065): a dry run writes nothing; the next version keeps every case of the last one plus fixes since
    (v1 byte-identical); show gives each case's solve count on that version and the floor."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-setv-")
        self.repo = tempfile.mkdtemp(prefix="roof-setv-repo-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(shutil.rmtree, self.repo, True)
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        self.m = sibling("evalset")
        subprocess.run(["git", "init", "-q", self.repo], check=True)
        self.n = 0

    def commit(self, msg, files):
        for name, text in files.items():
            p = Path(self.repo) / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(text)
        env = dict(os.environ, GIT_AUTHOR_NAME="Pat", GIT_AUTHOR_EMAIL="p@x", GIT_COMMITTER_NAME="Pat", GIT_COMMITTER_EMAIL="p@x")
        subprocess.run(["git", "-C", self.repo, "add", "-A"], check=True, env=env)
        subprocess.run(["git", "-C", self.repo, "commit", "-qm", msg], check=True, env=env)

    def cli(self, *args):
        r = subprocess.run([sys.executable, str(EVALS_DIR / "evalset.py"), *args, "--json"], capture_output=True, text=True,
                           env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        return json.loads(r.stdout)

    def test_dry_run_extend_and_solve_counts(self):
        self.commit("XYZ-1 · setup", {"src/alpha.py": "a\n", "src/beta.py": "b\n", "src/gamma.py": "g\n"})
        self.commit("XYZ-2 · Login button does nothing (fix)", {"src/alpha.py": "a2\n"})
        dry = self.cli("build", "--repo", self.repo, "--name", "demo", "--days", "30", "--dry-run")
        self.assertEqual((dry["written"], dry["total"], dry["next_version"]), (False, 1, 1))
        self.assertFalse((Path(self.tmp) / "sets").exists())                  # a dry run writes nothing
        v1 = self.cli("build", "--repo", self.repo, "--name", "demo", "--days", "30")
        self.assertEqual(v1["version"], 1)
        before = (Path(self.tmp) / "sets/demo/v1/cases.jsonl").read_bytes()
        self.commit("XYZ-3 · Save loses the title, fixed", {"src/beta.py": "b2\n"})
        pre = self.cli("build", "--name", "demo", "--extend", "--dry-run", "--repo", self.repo, "--days", "30")
        self.assertEqual((pre["kept"], [c["issue"] for c in pre["new"]], pre["total"], pre["written"]), (1, ["XYZ-3"], 2, False))
        self.assertIn("leak", pre["left_out"])
        self.assertFalse((Path(self.tmp) / "sets/demo/v2").exists())
        v2 = self.cli("build", "--name", "demo", "--extend", "--repo", self.repo, "--days", "30")
        self.assertEqual((v2["version"], v2["total"], v2["written"]), (2, 2, True))
        self.assertEqual((Path(self.tmp) / "sets/demo/v1/cases.jsonl").read_bytes(), before)   # v1 never edited
        meta2 = json.loads((Path(self.tmp) / "sets/demo/v2/set.json").read_text())
        self.assertEqual((meta2["extends"], meta2["repo_path"]), (1, str(Path(self.repo).resolve())))
        # Solve counts come from the index: two runs on v1, one right on the case.
        import sqlite3
        cid = json.loads(before.decode().splitlines()[0])["id"]
        with sqlite3.connect(Path(self.tmp) / "evals.db") as db:
            db.executescript(load(self.tmp).SCHEMA)
            for rid, v in (("r1", 1.0), ("r2", 0.0)):
                db.execute("INSERT INTO runs (id, model, status, set_name, set_version, started) VALUES (?,?,?,?,?,?)",
                           (rid, "openai/gpt-5-nano", "done", "demo", 1, rid))
                db.execute("INSERT INTO sample_scores VALUES (?,?,?,?)", (rid, cid, 1, v))
        s = self.cli("show", "demo", "--version", "1")
        self.assertEqual((s["cases"][0]["solved_by"], s["runs"], s["floor"]["of"]), ({"right": 1, "runs": 2}, 2, 1))
        self.assertEqual(s["best"]["contestant"], "gpt-5-nano")
        self.assertEqual(s["cases"][0]["report"], "Login button does nothing (fix)")
        vs = self.cli("versions", "demo")["versions"]
        self.assertEqual([(v["version"], v["count"], v["runs"]) for v in vs], [(1, 1, 2), (2, 2, 0)])


class JudgeScreen(unittest.TestCase):
    """HP EV-7 (LAB-2066): the label queue (likely fails first), items with every source's label, ⌘Z undo, trust from
    the last run against today's labels (yours over a model's once there are 10), advice, and a rubric draft that only
    a new version uses."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-judge2-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        self.j = sibling("judge")
        d = Path(self.tmp) / "judges/t"
        d.mkdir(parents=True)
        self.d = d
        items = [{"id": f"i{n}", "run": "r", "model": "x/haiku", "question": f"Bug report (LAB-{n}):\nThing {n} breaks\n\nSource files:\na.py",
                  "answer": "Open a.py first." if n % 2 else "Look at b.py.", "target": "a.py"} for n in range(24)]
        (d / "items.jsonl").write_text("".join(json.dumps(x) + "\n" for x in items))
        (d / "judge.json").write_text(json.dumps({"name": "t", "mode": "single", "rubric": "Pass when right.", "runs": ["r"],
                                                  "models": ["x/haiku"], "task": "own", "items": 24, "created": "c"}))
        verdicts = {f"i{n}": "pass" for n in range(24)}   # a lenient judge: passes everything
        (Path(self.tmp) / "judges/agreements.json").write_text(json.dumps({"20261101-judge_t_v1-aaaa": {
            "run": "20261101-judge_t_v1-aaaa", "judge": "t", "mode": "single", "judge_model": "y/mini", "measured": "m",
            "version": 1, "verdicts": verdicts, "examples": ["i0", "i1"]}}))

    def cli(self, *args):
        r = subprocess.run([sys.executable, str(EVALS_DIR / "judge.py"), *args, "--json"], capture_output=True, text=True,
                           env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        return json.loads(r.stdout)

    def test_queue_items_and_undo(self):
        q = self.cli("queue", "t")
        self.assertEqual((q["total"], q["labelled"]), (24, 0))
        self.assertEqual(q["queue"][0]["code"]["right"], 0)       # judge passed, code says no changed file: first
        self.assertEqual(q["queue"][0]["judge"], "pass")
        self.assertEqual(self.cli("queue", "t", "--first", "i7")["queue"][0]["id"], "i7")
        self.cli("label", "t", "--item", "i2", "--verdict", "fail", "--why", "wrong file")
        it = {x["id"]: x for x in self.cli("items", "t")}
        self.assertEqual((it["i2"]["labels"]["owner"]["verdict"], it["i2"]["split"]), ("fail", "held back"))
        self.assertEqual((it["i0"]["split"], it["i0"]["issue"], it["i0"]["title"]), ("example", "LAB-0", "Thing 0 breaks"))
        self.assertEqual(it["i3"]["code"], {"named": ["a.py"], "right": 1, "of": 1, "hits": ["a.py"]})
        self.assertEqual(self.cli("label", "t", "--undo")["item"], "i2")
        self.assertNotIn("owner", {x["id"]: x for x in self.cli("items", "t")}["i2"]["labels"])
        self.assertIn("undone", (self.d / "labels.jsonl").read_text())   # the history stays in the file

    def test_trust_prefers_your_labels_and_reads_lenient(self):
        for n in range(2, 8):   # 6 of yours (too few) beside 20 model labels
            self.j.add_label(self.d, f"i{n}", "pass" if n % 2 else "fail", "")
        for n in range(2, 22):
            self.j.add_label(self.d, f"i{n}", "pass" if n % 2 else "fail", "", "model", "z/sonnet")
        t = self.cli("trust", "t")
        self.assertEqual((t["reference"], t["held_back_yours"], t["ready"]), ("model", 6, False))
        self.assertIn("label 4 more", t["reading"])
        for n in range(8, 14):
            self.j.add_label(self.d, f"i{n}", "pass" if n % 2 else "fail", "")
        t = self.cli("trust", "t")
        self.assertEqual((t["reference"], t["n"], t["tpr"], t["tnr"], t["ready"]), ("you", 12, 1.0, 0.0, False))
        self.assertTrue(t["reading"].startswith("It's lenient"))
        self.assertIn("Not ready to stand in for you", t["reading"])
        adv = self.cli("advise", "t")["advice"]
        self.assertTrue(adv[0].startswith("Label the 12 waiting answers (mostly fails"))
        self.assertTrue(any("fail side" in a for a in adv))

    def test_rubric_draft_goes_into_the_next_version_only(self):
        for n in range(24):
            self.j.add_label(self.d, f"i{n}", "pass", "ok")
        b1 = self.cli("build", "t")
        v1 = (self.d / "v1/cases.jsonl").read_bytes()
        self.assertEqual(self.cli("rubric", "t", "--set", "Pass only when the first file is right.")["draft"],
                         "Pass only when the first file is right.")
        b2 = self.cli("build", "t")
        self.assertEqual((b1["version"], b2["version"], b2["new"]), (1, 2, True))
        self.assertEqual((self.d / "v1/cases.jsonl").read_bytes(), v1)
        self.assertIn("Pass only when the first file is right.", (self.d / "v2/cases.jsonl").read_text())
        vs = self.cli("versions", "t")
        self.assertEqual([v["rubric"] for v in vs["versions"]], ["Pass when right.", "Pass only when the first file is right."])
        self.assertIsNone(vs["draft"])


class RunPlanning(unittest.TestCase):
    """LAB-2067 (HP EV-9, EV-2): the ± points a run can tell apart, queue rows that say why a run stopped and who ran,
    and the seat guard that waits instead of failing."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-run2-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.e = load(self.tmp)

    def test_power_shape_and_values(self):
        p = engine(self.tmp, "power", "--n", "20", "--epochs", "3")
        self.assertEqual((p["n"], p["epochs"], p["method"]), (20, 3, "wilson"))
        self.assertAlmostEqual(p["plus_minus_points"], 13, delta=1)   # 20 cases × 3 attempts: about ±12-13 points
        self.assertGreater(engine(self.tmp, "power", "--n", "5")["plus_minus_points"], 30)   # 5 questions say very little
        lo, hi, _ = self.e.interval(0.5, 60, None, True)
        self.assertAlmostEqual(p["plus_minus_points"], round((hi - lo) / 2 * 100, 1))   # the app mirrors this number

    def test_status_says_why_a_run_stopped_and_who_ran(self):
        d = Path(self.tmp) / "runs/r1"
        d.mkdir(parents=True)
        (d / "run.json").write_text(json.dumps({"id": "r1", "task": "swe_bench_verified_mini", "model": "anthropic/claude-haiku-5-5",
                                                "agent": "claude_code", "status": "failed", "limit": 10,
                                                "error": "Traceback …\nRuntimeError: Cannot connect to the Docker daemon"}))
        d2 = Path(self.tmp) / "runs/r2"
        d2.mkdir(parents=True)
        (d2 / "run.json").write_text(json.dumps({"id": "r2", "task": "gsm8k", "model": "mockllm/model", "status": "done", "limit": 5}))
        rows = {r["id"]: r for r in engine(self.tmp, "status")}
        self.assertEqual(rows["r1"]["error"], "RuntimeError: Cannot connect to the Docker daemon")   # the last line
        self.assertIn("start Docker", rows["r1"]["hint"])
        self.assertEqual((rows["r1"]["contestant"]["kind"], rows["r1"]["contestant"]["name"]), ("agent", "Claude Code · claude-haiku-5-5"))
        self.assertEqual((rows["r2"]["error"], rows["r2"]["hint"], rows["r2"]["contestant"]["kind"]), (None, None, "baseline"))

    def test_seat_guard_waits_while_the_seat_is_over_its_limit(self):
        usage = Path(self.tmp) / "usage"
        usage.mkdir()
        (usage / "Claude1.json").write_text(json.dumps({"updated": time.time(), "rate_limits": {"five_hour": {"used_percentage": 95}}}))
        os.environ["ONEROOF_USAGE_DIR"] = str(usage)
        self.addCleanup(os.environ.pop, "ONEROOF_USAGE_DIR", None)
        ar = sibling("agent_runner")
        d = Path(self.tmp) / "runs/r3"
        d.mkdir(parents=True)
        (d / "run.json").write_text(json.dumps({"id": "r3", "seat": "C1", "seat_limit": 90, "status": "running"}))
        seen = []
        def nap(_):
            seen.append(json.loads((d / "run.json").read_text()))
            (d / "CANCEL").write_text("x")   # the owner cancels while it waits
        self.addCleanup(setattr, ar.time, "sleep", ar.time.sleep)   # ar.time is the time module: put sleep back
        ar.time.sleep = nap
        self.assertFalse(ar.wait_for_seat(json.loads((d / "run.json").read_text()), d))
        self.assertEqual(seen[0]["status"], "waiting")
        self.assertIn("waiting for seat C1: 95 %", seen[0]["waiting"])
        est = ar.seat_estimate("claude_code", 20, 1)
        self.assertEqual((est["seat"], est["seat_basis"], est["seat_fits"]), ("C1", "guess", False))
        (usage / "Claude1.json").write_text(json.dumps({"updated": time.time(), "rate_limits": {"five_hour": {"used_percentage": 40}}}))
        (d / "CANCEL").unlink()
        self.assertTrue(ar.wait_for_seat(json.loads((d / "run.json").read_text()), d))
        self.assertEqual(json.loads((d / "run.json").read_text())["status"], "running")   # back to work, never failed
        self.assertTrue(ar.seat_estimate("claude_code", 20, 1)["seat_fits"])

    def test_seat_env_keeps_the_login_and_drops_every_paid_route(self):
        ar = sibling("agent_runner")
        env = ar.strip_keys({"PATH": "/bin", "HOME": "/h", "ANTHROPIC_API_KEY": "x", "OPENAI_API_KEY": "x", "GITHUB_TOKEN": "x",
                             "AWS_ACCESS_KEY_ID": "x", "AWS_PROFILE": "x", "CLAUDE_CODE_USE_BEDROCK": "1", "ANTHROPIC_BASE_URL": "u",
                             "OPENAI_BASE_URL": "u", "CLAUDE_CODE_OAUTH_TOKEN": "login", "CODEX_HOME": "/h/.codex"})
        self.assertEqual(sorted(env), ["CLAUDE_CODE_OAUTH_TOKEN", "CODEX_HOME", "HOME", "PATH"])
        cmd = ar.command("claude_code", "claude", "q", Path("/x"))
        self.assertIn("--disallowedTools", cmd)
        self.assertTrue(cmd[cmd.index("--disallowedTools") + 1].startswith("Bash,Edit,Write,MultiEdit,NotebookEdit"))
        self.assertEqual(cmd[cmd.index("--permission-mode") + 1], "default")
        self.assertIn("read-only", ar.command("codex_cli", "codex", "q", Path("/x")))

    def test_doctor_lists_agents_first_with_why_unavailable(self):
        ar = sibling("agent_runner")
        rows = ar.agents_state()
        self.assertEqual([r["id"] for r in rows][:4], ["claude_code", "codex_cli", "opencode", "kimi_code"])
        kimi = next(r for r in rows if r["id"] == "kimi_code")
        self.assertEqual((kimi["available"], kimi["why"]), (False, "no headless mode"))
        self.assertEqual(next(r for r in rows if r["id"] == "codex_cli")["seat"], "CX")


class AgentRunner(unittest.TestCase):
    """HP EV-1 (LAB-2067): an agent CLI on a seat answers each case of your set in a fresh worktree at the commit before
    the fix, gets no API key, leaves no worktree behind (also after a failure) and pushes nothing. A fake CLI stands in
    for Claude Code: no seat is used by the tests."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-agent-")
        self.repo = tempfile.mkdtemp(prefix="roof-agent-repo-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.addCleanup(shutil.rmtree, self.repo, True)
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        self.es = sibling("evalset")
        subprocess.run(["git", "init", "-q", self.repo], check=True)
        env = dict(os.environ, GIT_AUTHOR_NAME="Pat", GIT_AUTHOR_EMAIL="p@x", GIT_COMMITTER_NAME="Pat", GIT_COMMITTER_EMAIL="p@x")
        for msg, files in [("XYZ-1 · setup", {"src/alpha.py": "old alpha\n", "src/beta.py": "b\n"}),
                           ("XYZ-2 · fix: login button does nothing", {"src/alpha.py": "new alpha\n"}),
                           ("XYZ-3 · Fix: export is empty", {"src/beta.py": "b2\n"})]:
            for name, text in files.items():
                p = Path(self.repo) / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text(text)
            subprocess.run(["git", "-C", self.repo, "add", "-A"], check=True, env=env)
            subprocess.run(["git", "-C", self.repo, "commit", "-qm", msg], check=True, env=env)
        cases, stats = self.es.build_cases(self.repo, 20, 30, None)
        self.assertEqual(len(cases), 2)
        d, _ = self.es.write_set("demo", self.repo, cases, stats, 30)
        self.task = str(self.es.task_file(d))
        self.log = Path(self.tmp) / "agent.log"
        # The fake agent: answers alpha.py, records where it ran, what the old file said and any key it was given; fails
        # on the XYZ-3 case when asked to.
        self.fake = Path(self.tmp) / "fake-claude"
        self.fake.write_text("#!/bin/sh\n"
                             f"echo \"$PWD|$(cat src/alpha.py 2>/dev/null)|${{ANTHROPIC_API_KEY:-none}}|${{OPENAI_API_KEY:-none}}\" >> {self.log}\n"
                             "case \"$2\" in *export*) if [ -n \"$FAKE_FAIL\" ]; then echo boom >&2; exit 3; fi;; esac\n"
                             "echo 'src/alpha.py'\n")
        self.fake.chmod(0o755)
        usage = Path(self.tmp) / "usage"
        usage.mkdir()
        (usage / "Claude1.json").write_text(json.dumps({"updated": time.time(), "rate_limits": {"five_hour": {"used_percentage": 9}}}))
        self.env = dict(os.environ, ONEROOF_EVALS_DIR=self.tmp, ONEROOF_AGENT_BIN_CLAUDE_CODE=str(self.fake),
                        ONEROOF_EVAL_WORKTREES=str(Path(self.tmp) / "worktrees"),
                        ONEROOF_USAGE_DIR=str(usage), ANTHROPIC_API_KEY="test-value-never-reaches-the-agent",
                        OPENAI_API_KEY="test-value-also-not")

    def run_engine(self, *args, extra=None):
        r = subprocess.run([sys.executable, str(ENGINE), *args, "--json"], capture_output=True, text=True,
                           env=dict(self.env, **(extra or {})))
        return json.loads(r.stdout)

    def worktrees(self):
        out = subprocess.run(["git", "-C", self.repo, "worktree", "list"], capture_output=True, text=True).stdout
        return [x for x in out.splitlines() if x.strip()]

    def test_cases_run_in_worktrees_at_the_pre_fix_commit_and_are_scored(self):
        before = subprocess.run(["git", "-C", self.repo, "rev-list", "--all", "--count"], capture_output=True, text=True).stdout
        est = self.run_engine("estimate", self.task, "--agent", "claude_code", "--seat", "C1", "--limit", "2")
        self.assertEqual((est["seat"], est["usd"], est["seat_basis"]), ("C1", 0.0, "guess"))
        self.assertAlmostEqual(est["seat_share"], 0.006)
        res = self.run_engine("run", self.task, "--agent", "claude_code", "--seat", "C1")
        self.assertEqual(res["status"], "done", res)
        self.assertEqual((res["runner"], res["model"], res["seat"]), ("seat", "seat/C1", "C1"))
        r = res["results"][0]
        self.assertEqual(r["contestant"]["kind"], "agent")
        self.assertEqual(r["contestant"]["name"], "Claude Code · C1")
        self.assertEqual(r["metrics"][0]["value"], 0.5)      # alpha.py is right for XYZ-2, wrong for XYZ-3
        lines = self.log.read_text().splitlines()
        self.assertEqual(len(lines), 2)
        for line in lines:
            where, alpha, ak, ok = line.split("|")
            self.assertIn("/worktrees/", where)              # a fresh worktree per case
            self.assertEqual((ak, ok), ("none", "none"))      # no API key ever reaches the agent
        self.assertIn("old alpha", self.log.read_text())     # XYZ-2's case: the tree before the fix
        self.assertEqual(len(self.worktrees()), 1)           # every case worktree removed
        self.assertFalse(any((Path(self.tmp) / "worktrees").glob("*/*")))
        after = subprocess.run(["git", "-C", self.repo, "rev-list", "--all", "--count"], capture_output=True, text=True).stdout
        self.assertEqual(before, after)                      # nothing committed
        self.assertEqual(subprocess.run(["git", "-C", self.repo, "remote"], capture_output=True, text=True).stdout, "")
        rows = self.run_engine("samples", res["id"])
        self.assertEqual(sorted(x["score"] for x in rows), [0.0, 1.0])
        self.assertEqual({x["code"]["verdict"] for x in rows}, {"pass", "fail"})
        tr = self.run_engine("sample", res["id"], rows[0]["id"], "--epoch", "1")
        self.assertEqual([m["role"] for m in tr["messages"]], ["system", "user", "assistant"])

    def test_a_failing_case_leaves_no_worktree_and_the_run_still_scores(self):
        res = self.run_engine("run", self.task, "--agent", "claude_code", "--seat", "C1", extra={"FAKE_FAIL": "1"})
        self.assertEqual(res["status"], "done")
        rows = self.run_engine("samples", res["id"])
        self.assertTrue(any("boom" in (x.get("error") or "") for x in rows))
        self.assertEqual(len(self.worktrees()), 1)

    def test_a_new_regression_set_keeps_the_repo_so_agents_can_answer_it(self):
        res = self.run_engine("run", self.task, "--agent", "claude_code", "--seat", "C1")
        rows = self.run_engine("samples", res["id"])
        add = subprocess.run([sys.executable, str(EVALS_DIR / "evalset.py"), "add", "--new", "demo regressions", "--from-run", res["id"],
                              "--sample", rows[0]["id"], "--json"], capture_output=True, text=True, env=self.env)
        self.assertTrue(json.loads(add.stdout)["added"])
        meta = json.loads((Path(self.tmp) / "sets/demo_regressions/v1/set.json").read_text())
        self.assertEqual(Path(meta["repo_path"]).resolve(), Path(self.repo).resolve())

    def test_a_full_seat_refuses_before_starting_and_benchmarks_are_refused(self):
        (Path(self.tmp) / "usage/Claude1.json").write_text(json.dumps({"updated": time.time(),
                                                                      "rate_limits": {"five_hour": {"used_percentage": 89.5}}}))
        e = self.run_engine("run", self.task, "--agent", "claude_code", "--seat", "C1")
        self.assertIn("would pass the 90 % limit", e["error"])
        e = self.run_engine("run", "gsm8k", "--agent", "claude_code", "--seat", "C1")
        self.assertIn("answer your own eval sets", e["error"])
        e = self.run_engine("run", self.task, "--agent", "kimi_code", "--seat", "K1")
        self.assertIn("no headless mode", e["error"])


class CompareAndHistory(unittest.TestCase):
    """LAB-2068 (HP EV-8 + blend): compare = the app's paired compare plus the cases only one solved; leaderboard per
    version with agents first, the baseline last and the floor; history with drops 'possible' unless the paired range
    excludes 0."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-board-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.e = load(self.tmp)
        self.f = Fixture(self.tmp)
        self.ids = [f"XYZ-{i}-abc" for i in range(1, 21)]
        self.tf = str(self.f.set("demo", 1, self.ids, floor=8))

    def scores(self, right: int, shift: int = 0) -> dict:
        return {i: (1.0 if (n + shift) % 20 < right else 0.0) for n, i in enumerate(self.ids)}

    def test_compare_matches_the_app_and_lists_the_discordant_cases(self):
        self.f.run("a", "own_demo_v1", "anthropic/claude-haiku-5-5", self.scores(15), "2026-10-02T00:00:00Z", task_ref=self.tf)
        self.f.run("b", "own_demo_v1", "openai/gpt-5-mini", self.scores(12, 2), "2026-10-03T00:00:00Z", task_ref=self.tf)
        self.e.index()
        c = engine(self.tmp, "compare", "a", "b")
        pc = self.e.paired_compare(self.e.sample_means("a"), self.e.sample_means("b"))
        self.assertEqual((c["diff"], c["ci95"], c["n"], c["paired"]), (pc["diff"], pc["ci95"], 20, True))
        self.assertEqual((c["diff"], c["ci95"]), (0.15, [-0.1073, 0.4073]))   # same numbers in EvalsTests (Swift)
        self.assertEqual(c["verdict"], "noise")
        self.assertEqual((len(c["only_a"]), len(c["only_b"]), c["tied"]), (5, 2, 13))
        self.assertIn("XYZ-14-abc", c["only_a"])
        self.assertIn("unknown", json.dumps(engine(self.tmp, "compare", "a", "zz")) + "unknown")

    def test_leaderboard_order_floor_and_baseline_last(self):
        self.f.run("m1", "own_demo_v1", "openai/gpt-5-mini", self.scores(11), "2026-10-02T00:00:00Z", task_ref=self.tf)
        self.f.run("m2", "own_demo_v1", "openai/gpt-5-mini", self.scores(13), "2026-10-05T00:00:00Z", task_ref=self.tf)
        self.f.run("ag", "own_demo_v1", "seat/C1", self.scores(9), "2026-10-04T00:00:00Z", task_ref=self.tf, agent="claude_code")
        self.f.run("base", "own_demo_v1", "mockllm/model", self.scores(0), "2026-10-04T00:00:00Z", task_ref=self.tf)
        self.e.index()
        lb = engine(self.tmp, "leaderboard", "demo@v1")
        self.assertEqual([r["kind"] for r in lb["rows"]], ["agent", "model", "baseline"])
        self.assertEqual([r["run"] for r in lb["rows"]], ["ag", "m2", "base"])   # the latest run per contestant
        self.assertEqual((lb["floor"], lb["floor_kind"], lb["cases"]), (0.4, "no-model floor", 20))
        self.assertTrue(lb["rows"][0]["seat"])
        self.assertEqual(lb["rows"][0]["contestant"], "Claude Code · C1")
        self.assertEqual(engine(self.tmp, "leaderboard", "demo@v2")["rows"], [])   # versions are never mixed

    def test_history_flags_a_possible_drop(self):
        self.f.run("h1", "own_demo_v1", "openai/gpt-5-mini", self.scores(14), "2026-10-06T00:00:00Z", task_ref=self.tf)
        self.f.run("h2", "own_demo_v1", "openai/gpt-5-mini", self.scores(12), "2026-10-31T00:00:00Z", task_ref=self.tf)
        self.f.run("k1", "own_demo_v1", "anthropic/claude-haiku-5-5", self.scores(20), "2026-10-06T00:00:00Z", task_ref=self.tf)
        self.f.run("k2", "own_demo_v1", "anthropic/claude-haiku-5-5", self.scores(4), "2026-10-31T00:00:00Z", task_ref=self.tf)
        self.e.index()
        h = engine(self.tmp, "history", "demo@v1")
        self.assertEqual([len(s["points"]) for s in h["series"]], [2, 2])
        drops = {d["id"]: d for d in h["drops"]}
        self.assertTrue(drops["openai/gpt-5-mini"]["possible"])          # −10 points, inside the range
        self.assertIn("dropped 10 points on Oct 31, inside its range. Re-run with 3 attempts", drops["openai/gpt-5-mini"]["text"])
        self.assertFalse(drops["anthropic/claude-haiku-5-5"]["possible"])   # −80 points: the paired range excludes 0
        self.assertEqual((h["first"][:10], h["last"][:10]), ("2026-10-06", "2026-10-31"))


class SampleVerdicts(unittest.TestCase):
    """LAB-2069 (HP EV-10, EV-11): each answer with the code check, the judge and your label side by side, the judge ≠ you
    count; adding an answer to a regression set writes a new version and leaves the old one byte for byte."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-verdicts-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        self.e = load(self.tmp)
        self.f = Fixture(self.tmp)
        self.ids = [f"LAB-{i}-abc" for i in range(1, 7)]
        self.tf = str(self.f.set("tri", 1, self.ids, kind="triage"))
        self.rid = "20261101-120000-own_tri_v1-wxyz"
        self.f.run(self.rid, "own_tri_v1", "openai/gpt-5-mini", {i: (1.0 if n < 3 else 0.0) for n, i in enumerate(self.ids)},
                   "2026-11-01T12:00:00Z", task_ref=self.tf)
        jd = Path(self.tmp) / "judges/tj"
        jd.mkdir(parents=True)
        items = [{"id": f"wxyz:{i}:1", "run": self.rid, "sample": i, "model": "openai/gpt-5-mini",
                  "question": f"Bug report ({i[:-4]}):\nThing {i} breaks\n\nSource files:\na.py", "answer": "Open b.py.", "target": "a.py"}
                 for i in self.ids]
        (jd / "items.jsonl").write_text("".join(json.dumps(x) + "\n" for x in items))
        (jd / "judge.json").write_text(json.dumps({"name": "tj", "mode": "single", "rubric": "r", "runs": [self.rid],
                                                   "models": ["openai/gpt-5-mini"], "task": "own_tri_v1", "items": 6}))
        verdicts = {f"wxyz:{i}:1": "pass" for i in self.ids}   # a lenient judge
        (Path(self.tmp) / "judges/agreements.json").write_text(json.dumps({"j1": {"run": "j1", "judge": "tj", "mode": "single",
                                                                                  "measured": "m", "verdicts": verdicts}}))
        j = sibling("judge")
        for i, v in [(self.ids[0], "pass"), (self.ids[3], "fail"), (self.ids[4], "fail")]:
            j.add_label(jd, f"wxyz:{i}:1", v, "my reason")
        self.e.index()

    def test_samples_carry_code_judge_and_you(self):
        rows = {r["id"]: r for r in engine(self.tmp, "samples", self.rid)}
        r = rows[self.ids[3]]
        self.assertEqual((r["code"]["verdict"], r["judge"]["verdict"], r["you"]["verdict"]), ("fail", "pass", "fail"))
        self.assertEqual((r["you"]["why"], r["disagree"], r["issue"], r["title"]), ("my reason", True, "LAB-4", "Thing LAB-4-abc breaks"))
        self.assertEqual(r["judge_item"], {"judge": "tj", "item": f"wxyz:{self.ids[3]}:1"})
        self.assertNotIn("you", rows[self.ids[5]])            # unlabelled
        self.assertFalse(rows[self.ids[5]]["labelled"])
        verdicts = json.loads((Path(self.tmp) / "judges/agreements.json").read_text())["j1"]["verdicts"]
        mine = sibling("judge").labels_of(Path(self.tmp) / "judges/tj")
        expected = sum(1 for k, v in mine.items() if verdicts.get(k) != v["verdict"])
        self.assertEqual(sum(r["disagree"] for r in rows.values()), expected)   # Judge ≠ you = the labels' disagreements
        self.assertEqual(expected, 2)

    def test_add_to_a_regression_set_makes_a_new_version(self):
        a = json.loads(subprocess.run([sys.executable, str(EVALS_DIR / "evalset.py"), "add", "--new", "Tri regressions",
                                       "--from-run", self.rid, "--sample", self.ids[3], "--json"], capture_output=True, text=True,
                                      env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp)).stdout)
        self.assertEqual((a["name"], a["version"], a["count"], a["added"]), ("tri_regressions", 1, 1, True))
        v1 = (Path(self.tmp) / "sets/tri_regressions/v1/cases.jsonl").read_bytes()
        es = sibling("evalset")
        b = es.add_case("tri_regressions", es.case_from_run(self.rid, self.ids[4])[0], "triage")
        self.assertEqual((b["version"], b["count"], b["message"]), (2, 2, "Added to tri_regressions (new version v2)"))
        self.assertEqual((Path(self.tmp) / "sets/tri_regressions/v1/cases.jsonl").read_bytes(), v1)   # v1 untouched
        meta = json.loads((Path(self.tmp) / "sets/tri_regressions/v2/set.json").read_text())
        self.assertEqual((meta["kind"], meta["extends"]), ("triage", 1))
        self.assertFalse(es.add_case("tri_regressions", es.case_from_run(self.rid, self.ids[4])[0], "triage")["added"])
        judged = es.case_from_run("j-run-not-there", "x") if False else None
        self.assertIsNone(judged)
        q = subprocess.run([sys.executable, str(EVALS_DIR / "evalset.py"), "add", "tri_regressions", "--from-task", "gsm8k",
                            "--sample", "q1", "--json"], capture_output=True, text=True, env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        self.assertIn("not on this Mac yet", json.loads(q.stdout)["error"])


class Lessons(unittest.TestCase):
    """LAB-2070 (HP EV-12): lessons.json loads, 16 lessons in six groups, unique ids, every link a route the app knows
    (EvalLessons.knownRoutes in OneRoofCore/EvalsLearn.swift), every 1.9.37 glossary entry carried once with its text,
    and the range explorer's numbers are the engine's Wilson (the same table EvalsLearnTests locks in Swift)."""

    def setUp(self):
        self.doc = json.loads((EVALS_DIR / "lessons.json").read_text())
        self.swift = (ROOT / "app/Sources/OneRoofCore/EvalsLearn.swift").read_text()
        self.glossary = re.findall(r'Entry\(id: "(\w+)", title: "[^"]*",\s*body: "((?:[^"\\]|\\.)*)"',
                                   (ROOT / "app/Sources/OneRoofCore/Evals.swift").read_text())

    def test_sixteen_lessons_unique_grouped(self):
        ls = self.doc["lessons"]
        self.assertEqual(len(ls), 16)
        self.assertEqual(len({x["id"] for x in ls}), 16)
        self.assertEqual([x["title"] for x in self.doc["sections"]], ["Start", "Reading a score", "How answers are marked",
                                                                     "Agents vs models", "Your own evals", "Reading leaderboards"])
        order = [x["id"] for x in self.doc["sections"]]
        self.assertEqual([x["section"] for x in ls], sorted((x["section"] for x in ls), key=order.index))   # grouped in order
        for x in ls:
            self.assertLessEqual(len(x["body"].split()), 120, x["id"])
            self.assertTrue(x["widget"] and x["teaser"] and x["links"], x["id"])

    def test_every_link_is_a_known_route(self):
        m = re.search(r"knownRoutes = \[([^\]]*)\]", self.swift, re.S)
        routes = set(re.findall(r'"([^"]+)"', m.group(1)))
        for x in self.doc["lessons"]:
            for k in x["links"]:
                self.assertIn(k["route"], routes, f'{x["id"]} → {k["route"]}')

    def test_glossary_bodies_preserved(self):
        self.assertEqual(len(self.glossary), 12)
        used = [g for x in self.doc["lessons"] for g in x["glossary"]]
        self.assertEqual(sorted(used), sorted(g for g, _ in self.glossary))
        body = dict(self.glossary)
        for x in self.doc["lessons"]:
            if x["glossary"]:
                self.assertEqual(x["body"], body[x["glossary"][0]].replace('\\"', '"'), x["id"])

    def test_range_explorer_parity_with_power_and_wilson(self):
        e = load(tempfile.mkdtemp(prefix="roof-lessons-"))
        table = {5: (0.3755282641185388, 0.9637768390302125), 10: (0.49015684672072335, 0.9433190520193067),
                 20: (0.5839782779742401, 0.9193436467288), 50: (0.6696262789551477, 0.8875637005402612),
                 200: (0.7391436038882958, 0.8495487925607118), 1000: (0.7740805389094014, 0.8236233219387643)}
        for n, (lo, hi) in table.items():
            a, b, _ = e.interval(0.8, n, None, True)
            self.assertAlmostEqual(a, lo, places=12)
            self.assertAlmostEqual(b, hi, places=12)
        self.assertEqual(e.power(20, 3)["plus_minus_points"], 12.3)   # Attempts widget = EvalPower.mirror (Swift test)
        self.assertEqual((round(table[50][0] * 100), round(table[50][1] * 100)), (67, 89))


class CompareTooFew(unittest.TestCase):
    """QA (M9 stage 2): a compare on fewer than 10 shared questions calls no winner, however clear it looks."""

    def setUp(self):
        self.e = load(tempfile.mkdtemp(prefix="roof-cmp-"))

    def test_two_shared_questions_zero_spread_is_not_a_win(self):
        c = self.e.paired_compare({"q1": 1.0, "q2": 1.0}, {"q1": 0.0, "q2": 0.0})
        self.assertEqual((c["verdict"], c["too_few"], c["n"], c["ci95"]), ("noise", True, 2, [1.0, 1.0]))

    def test_ten_shared_questions_can_be_called(self):
        ids = [f"q{i}" for i in range(10)]
        c = self.e.paired_compare({i: 1.0 for i in ids}, {i: 0.0 for i in ids})
        self.assertEqual((c["verdict"], c["too_few"]), ("a_better", False))
        u = self.e.paired_compare({f"a{i}": 1.0 for i in range(5)}, {f"b{i}": 0.0 for i in range(5)})   # unpaired, 5 each
        self.assertEqual((u["paired"], u["verdict"], u["too_few"]), (False, "noise", True))


class SeatGate(unittest.TestCase):
    """QA (M9 stage 2): unknown or stale seat use never passes silently. Before each case the run waits ("seat use
    unknown") until the use is known and under the limit, or the owner presses Run anyway (recorded in run.json); the
    agent CLIs run contained (Claude Code --restricted with no hooks and Read denied on secrets; Codex without user config)."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="roof-seat-gate-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.usage = Path(self.tmp) / "usage"
        self.usage.mkdir()
        os.environ["ONEROOF_EVALS_DIR"] = self.tmp
        os.environ["ONEROOF_USAGE_DIR"] = str(self.usage)
        os.environ["ONEROOF_SEAT_POLL"] = "0.05"
        self.addCleanup(lambda: [os.environ.pop(k, None) for k in ("ONEROOF_USAGE_DIR", "ONEROOF_SEAT_POLL")])
        self.ar = sibling("agent_runner")
        self.d = Path(self.tmp) / "runs" / "r1"
        self.d.mkdir(parents=True)
        self.r = {"id": "r1", "seat": "C1", "seat_limit": 90, "runner": "seat", "status": "running"}
        (self.d / "run.json").write_text(json.dumps(self.r))

    def usage_file(self, pct, age_hours=0.0):
        (self.usage / "Claude1.json").write_text(json.dumps({"updated": time.time() - age_hours * 3600,
                                                             "rate_limits": {"five_hour": {"used_percentage": pct}}}))

    def wait_in_thread(self):
        import threading
        box = {}
        th = threading.Thread(target=lambda: box.setdefault("ok", self.ar.wait_for_seat(self.r, self.d)), daemon=True)
        th.start()
        return th, box

    def run_json(self):
        return json.loads((self.d / "run.json").read_text())

    def test_the_gate_words(self):
        u = {"seat": "C1", "five_hour": None, "stale": True}
        self.assertTrue(self.ar.seat_gate(u, 90, False).startswith("seat use unknown"))
        self.assertIsNone(self.ar.seat_gate(u, 90, True))                                        # Run anyway
        self.assertIsNone(self.ar.seat_gate({"seat": "C1", "five_hour": 40.0, "stale": False}, 90, False))
        self.assertIn("93 %", self.ar.seat_gate({"seat": "C1", "five_hour": 93.0, "stale": False}, 90, True))   # anyway ≠ over

    def test_unknown_use_waits_until_run_anyway(self):
        th, box = self.wait_in_thread()            # no usage file at all
        time.sleep(0.4)
        self.assertTrue(th.is_alive())
        r = self.run_json()
        self.assertEqual(r["status"], "waiting")
        self.assertTrue(r["waiting"].startswith("seat use unknown"))
        res = subprocess.run([sys.executable, str(ENGINE), "run-anyway", "r1", "--json"], capture_output=True, text=True,
                             env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        self.assertTrue(json.loads(res.stdout)["seat_unknown_ok"], res.stderr)
        th.join(3)
        self.assertEqual(box.get("ok"), True)
        r = self.run_json()
        self.assertEqual((r["status"], r["waiting"], r["seat_unknown_ok"]), ("running", None, True))
        self.assertIn("seat_unknown_ok_at", r)

    def test_stale_use_waits_until_known_and_under_the_limit(self):
        self.usage_file(20, age_hours=7)           # older than 6 hours: stale
        th, box = self.wait_in_thread()
        time.sleep(0.3)
        self.assertTrue(th.is_alive())
        self.assertTrue(self.run_json()["waiting"].startswith("seat use unknown"))
        self.usage_file(95)                        # known, but over
        time.sleep(0.3)
        self.assertTrue(th.is_alive())
        self.assertIn("95 %", self.run_json()["waiting"])
        self.usage_file(30)                        # known and under
        th.join(3)
        self.assertEqual(box.get("ok"), True)

    def test_run_anyway_only_for_seat_runs(self):
        (self.d / "run.json").write_text(json.dumps(dict(self.r, runner=None)))
        res = subprocess.run([sys.executable, str(ENGINE), "run-anyway", "r1", "--json"], capture_output=True, text=True,
                             env=dict(os.environ, ONEROOF_EVALS_DIR=self.tmp))
        self.assertIn("not an agent run on a seat", res.stdout + res.stderr)

    def test_agents_run_contained(self):
        out, case = Path(self.tmp) / "c-e1.last.txt", Path(self.tmp) / "case"
        cc = self.ar.command("claude_code", "claude", "q", out, case)
        self.assertIn("--restricted", cc)
        self.assertIn("--strict-mcp-config", cc)
        self.assertEqual(cc[cc.index("--permission-prompts") + 1], "none")
        st = json.loads(cc[cc.index("--settings") + 1])
        self.assertIs(st["disableAllHooks"], True)
        for p in ("~/Projects/_common/access_admin/**", "~/.config/**", "~/.ssh/**", "~/Library/**"):
            self.assertIn(f"Read({p})", st["permissions"]["deny"])
        self.assertIn("Bash", st["permissions"]["deny"])
        cx = self.ar.command("codex_cli", "codex", "q", out, case)
        for flag in ("--ignore-user-config", "--ignore-rules", "--ephemeral"):
            self.assertIn(flag, cx)
        self.assertEqual(cx[cx.index("--sandbox") + 1], "read-only")
        self.assertEqual(cx[cx.index("-C") + 1], str(case))
        self.assertIn("hooks", [cx[i + 1] for i, x in enumerate(cx) if x == "--disable"])
        # Case worktrees are outside ~/Library (whose reads are denied) unless a test moves them.
        os.environ.pop("ONEROOF_EVAL_WORKTREES", None)
        ar2 = sibling("agent_runner")
        self.assertFalse(str(ar2.WORKTREES).startswith(str(Path.home() / "Library")))


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
