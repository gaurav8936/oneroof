import Foundation

/// LAB-1867 · harvest: a loop's commits become a PR, and only after you approve them in Today.
///
/// A loop never pushes (LAB-1218: the kit's `loop-push-guard`). When you press "Approve → open PR" on a staged commit
/// or PR outcome, One Roof records your approval in the ledger, then gates the loop branch:
///
/// 1. **Tests**: the loop's own check runs in its worktree and must pass.
/// 2. **LLM judge**: a second agent reads the goal and the diff against the PR's base and answers PASS or FAIL with
///    one line why (the command in `ONEROOF_LOOP_JUDGE`, else `claude -p`). No judge = no PR.
///
/// Both pass: the branch is pushed with `AE_LOOP_PUSH_APPROVED=<outcome id>` (the guard's owner-approval key) and
/// `gh pr create` opens the PR. The PR is a new `pr` outcome (status `applied`, its URL as the link); the approved
/// outcomes keep their status and get the PR in their detail. A gate that fails puts them back to `staged` with the
/// reason, so they stay in Today. Nothing is merged.
public enum LoopHarvest {
    public struct Tools: Sendable {
        public var git: String
        /// `gh` (nil = not found: no PR).
        public var gh: String?
        /// The judge command; the prompt is its last argument (nil = not found: no PR).
        public var judge: [String]?
        public var environment: [String: String]
        public var timeout: TimeInterval

        public init(git: String = "/usr/bin/git", gh: String? = nil, judge: [String]? = nil,
                    environment: [String: String] = ProcessInfo.processInfo.environment, timeout: TimeInterval = 600) {
            self.git = git; self.gh = gh; self.judge = judge; self.environment = environment; self.timeout = timeout
        }

        /// The real tools: `gh` and `claude` from PATH or the usual folders; `ONEROOF_GH` / `ONEROOF_LOOP_JUDGE` override.
        public static func live(environment env: [String: String] = ProcessInfo.processInfo.environment) -> Tools {
            let gh = env["ONEROOF_GH"].flatMap { $0.isEmpty ? nil : $0 } ?? which("gh", environment: env)
            let judge: [String]?
            if let j = env["ONEROOF_LOOP_JUDGE"], !j.isEmpty { judge = [j] }
            else if let c = which("claude", environment: env) { judge = [c, "-p", "--output-format", "text"] }
            else { judge = nil }
            return Tools(gh: gh, judge: judge, environment: env)
        }
    }

    public struct Gate: Equatable, Sendable {
        public var testsPassed: Bool
        public var testsOutput: String
        public var judgePassed: Bool
        public var judgeReason: String
        public var passed: Bool { testsPassed && judgePassed }
        /// "tests ✓ · judge ✕ deletes a test".
        public var summary: String {
            "tests " + (testsPassed ? "✓" : "✕") + " · judge " + (judgePassed ? "✓" : "✕") + (judgeReason.isEmpty ? "" : " " + judgeReason)
        }
    }

    public enum Result: Equatable, Sendable {
        case opened(url: String, gate: Gate)
        case refused(String, gate: Gate?)
    }

    /// Approve the outcomes (one run's commits, or a staged PR) and harvest the loop branch into a PR.
    public static func approveAndOpen(loop: Loop, outcomes: [LoopLedger.Outcome], ledger: LoopLedger, tools: Tools,
                                      by: String = NSUserName()) -> Result {
        guard !outcomes.isEmpty else { return .refused("Nothing to approve.", gate: nil) }
        for o in outcomes { _ = try? ledger.decide(o.id, status: "approved", by: by) }
        let r = harvest(loop: loop, approvedIds: outcomes.map(\.id), title: prTitle(loop, outcomes), tools: tools)
        switch r {
        case .opened(let url, let gate):
            let detail = ["from": outcomes.map { String($0.id) }.joined(separator: ","), "gate": gate.summary,
                          "branch": loop.branch]
            _ = try? ledger.add(loop: loop.id, runId: outcomes[0].runId, kind: "pr", title: prTitle(loop, outcomes), link: url,
                                status: "applied", detail: detail)
            for o in outcomes { try? ledger.setDetail(o.id, "pr", url); try? ledger.setDetail(o.id, "gate", gate.summary) }
        case .refused(let why, let gate):
            for o in outcomes {
                try? ledger.restage(o.id)
                try? ledger.setDetail(o.id, "gate", gate?.summary ?? why)
                try? ledger.setDetail(o.id, "harvest", why)
            }
        }
        return r
    }

    static func prTitle(_ loop: Loop, _ outcomes: [LoopLedger.Outcome]) -> String {
        if outcomes.count == 1, outcomes[0].kind == "pr", !outcomes[0].title.isEmpty { return outcomes[0].title }
        let subjects = outcomes.map(\.title).filter { !$0.isEmpty }
        if subjects.count == 1 { return "[loop \(loop.id)] " + subjects[0] }
        return "[loop \(loop.id)] \(outcomes.count) changes: " + subjects.prefix(2).joined(separator: "; ")
    }

    /// Gate the branch and open the PR (no ledger writes; `approveAndOpen` records them).
    public static func harvest(loop: Loop, approvedIds: [Int], title: String, tools: Tools) -> Result {
        let repo = loop.repoPath
        let branch = loop.branch
        let wt = loop.worktreePath
        guard FileManager.default.fileExists(atPath: repo + "/.git") else { return .refused("The loop's repo \(repo) is not a git repo.", gate: nil) }
        guard git(tools, repo, ["rev-parse", "--verify", "--quiet", "refs/heads/" + branch]).0 == 0 else {
            return .refused("The loop branch \(branch) does not exist.", gate: nil)
        }
        let base = baseBranch(loop, tools: tools)
        let baseRef = git(tools, repo, ["rev-parse", "--verify", "--quiet", "refs/remotes/origin/" + base]).0 == 0 ? "origin/" + base : base
        let (lrc, log) = git(tools, repo, ["log", "--format=%h %s", baseRef + ".." + branch])
        let commits = lrc == 0 ? log.split(separator: "\n").map(String.init) : []
        guard !commits.isEmpty else { return .refused("No commits on \(branch) that are not on \(base) already.", gate: nil) }

        // 1. Tests: the loop's check, in its worktree (the code the PR carries).
        let folder = FileManager.default.fileExists(atPath: wt + "/.git") ? wt : repo
        let check = LoopSpecLint.clean(loop.check)
        let tests: LoopCheckResult
        if let problem = LoopSpecLint.checkProblem(check, folder: folder) {
            tests = LoopCheckResult(passed: false, exitCode: 127, output: problem)
        } else {
            tests = LoopCheck.run(check, in: folder, timeout: min(loop.checkTimeout, tools.timeout))
        }
        // 2. The judge reads the goal and the diff.
        let (_, diff) = git(tools, repo, ["diff", "--stat", "--patch", baseRef + "..." + branch], timeout: 60)
        let (jPass, jWhy) = judge(loop: loop, diff: diff, commits: commits, tools: tools)
        let gate = Gate(testsPassed: tests.passed, testsOutput: LoopCheck.tail(tests.output), judgePassed: jPass, judgeReason: jWhy)
        guard gate.passed else {
            return .refused(tests.passed ? "The judge said no: \(jWhy)" : "The loop's check fails on its branch (exit \(tests.exitCode)).", gate: gate)
        }

        // 3. Push (with the owner's approval key) and open the PR.
        guard let gh = tools.gh else { return .refused("gh is not installed: the PR could not be opened.", gate: gate) }
        var env = tools.environment
        env["AE_LOOP_PUSH_APPROVED"] = String(approvedIds.first ?? 0)
        let (prc, pout) = Foundations.run(tools.git, ["-C", repo, "push", "origin", branch + ":refs/heads/" + branch],
                                          timeout: 120, environment: env)
        guard prc == 0 else { return .refused("Push of \(branch) failed: " + LoopCheck.tail(pout, lines: 4), gate: gate) }
        let body = prBody(loop, commits: commits, gate: gate)
        let (grc, gout) = Foundations.run(gh, ["pr", "create", "--head", branch, "--base", base, "--title", title, "--body", body],
                                          cwd: repo, timeout: 120, environment: env)
        let url = gout.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { $0.hasPrefix("http") } ?? ""
        guard grc == 0, !url.isEmpty else { return .refused("gh pr create failed: " + LoopCheck.tail(gout, lines: 4), gate: gate) }
        return .opened(url: url, gate: gate)
    }

    /// The PR's base: the loop's own setting, else `develop` when the remote has it, else the remote's default branch.
    public static func baseBranch(_ loop: Loop, tools: Tools) -> String {
        if let b = loop.harvestBase?.trimmingCharacters(in: .whitespaces), !b.isEmpty { return b }
        let repo = loop.repoPath
        if git(tools, repo, ["rev-parse", "--verify", "--quiet", "refs/remotes/origin/develop"]).0 == 0 { return "develop" }
        let (rc, head) = git(tools, repo, ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        if rc == 0, let b = head.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/", maxSplits: 1).last { return String(b) }
        return "main"
    }

    static func prBody(_ loop: Loop, commits: [String], gate: Gate) -> String {
        """
        Loop `\(loop.id)` (One Roof), approved by its owner in Today.

        Goal: \(loop.goal.isEmpty ? loop.displayTitle : loop.goal)
        Check: `\(loop.check)`

        Gate: \(gate.summary)

        Commits:
        \(commits.prefix(30).map { "- " + $0 }.joined(separator: "\n"))
        """
    }

    /// The judge's prompt: the goal, the check, the commits and the diff (cut to 60 kB).
    public static func judgePrompt(loop: Loop, diff: String, commits: [String]) -> String {
        let cut = diff.count > 60_000 ? String(diff.prefix(60_000)) + "\n… (diff cut at 60 kB)" : diff
        return """
        You review work an unattended loop did on its own branch before it becomes a pull request. Answer with PASS or \
        FAIL on the first line, then one short line why. FAIL if the change deletes, skips or weakens tests, touches \
        secrets or credentials, is unrelated to the goal, or does anything that cannot be undone. Otherwise PASS.

        Goal: \(loop.goal.isEmpty ? loop.displayTitle : loop.goal)
        Check (passes on the branch): \(loop.check)
        Commits:
        \(commits.prefix(30).joined(separator: "\n"))

        Diff:
        \(cut)
        """
    }

    /// Run the judge: (passed, one line why). No judge or no clear verdict = not passed.
    static func judge(loop: Loop, diff: String, commits: [String], tools: Tools) -> (Bool, String) {
        guard let cmd = tools.judge, let exe = cmd.first else { return (false, "no judge available (claude not found)") }
        let (rc, out) = Foundations.run(exe, Array(cmd.dropFirst()) + [judgePrompt(loop: loop, diff: diff, commits: commits)],
                                        cwd: loop.repoPath, timeout: min(tools.timeout, 300), environment: tools.environment)
        return verdict(rc: rc, output: out)
    }

    public static func verdict(rc: Int32, output: String) -> (Bool, String) {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard rc == 0, let i = lines.firstIndex(where: { $0.uppercased().hasPrefix("PASS") || $0.uppercased().hasPrefix("FAIL") }) else {
            return (false, rc == 0 ? "the judge gave no verdict" : "the judge failed (exit \(rc))")
        }
        let first = lines[i]
        let pass = first.uppercased().hasPrefix("PASS")
        var why = String(first.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: " :-·—"))
        if why.isEmpty, i + 1 < lines.count { why = lines[i + 1] }
        return (pass, String(why.prefix(200)))
    }

    static func git(_ t: Tools, _ repo: String, _ args: [String], timeout: TimeInterval = 30) -> (Int32, String) {
        Foundations.run(t.git, ["-C", repo] + args, timeout: timeout, environment: t.environment)
    }

    /// A program on PATH or in the usual install folders.
    public static func which(_ name: String, environment env: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let home = NSHomeDirectory()
        let dirs = (env["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.claude/local", "/usr/bin"]
        for d in dirs where !d.isEmpty {
            let p = (d as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}

extension LoopLedger {
    /// Put an approved outcome back to `staged` (its harvest gate failed: it stays in Today with the reason).
    public func restage(_ id: Int) throws {
        try setStatus(id, "staged")
    }
}
