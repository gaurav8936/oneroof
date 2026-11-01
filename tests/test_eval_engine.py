#!/usr/bin/env python3
"""Tests for the One Roof eval engine (app/Resources/evals/roof_eval.py, LAB-EVALS).

  python3 tests/test_eval_engine.py            unit tests: offline, no engine needed (seconds)
  ROOF_EVAL_INTEGRATION=1 python3 tests/...    also install the engine into a temp folder and run a tiny task on the
                                               mock model: setup, run, background, status, results, index (needs uv;
                                               the first install downloads packages)
"""
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


if __name__ == "__main__":
    unittest.main(verbosity=2)
