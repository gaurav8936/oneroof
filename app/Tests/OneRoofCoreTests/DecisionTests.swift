import XCTest
@testable import OneRoofCore

final class DecisionMatcherTests: XCTestCase {
    func testClaudeBash() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.claudeBashPrompt, agent: .claude))
        XCTAssertEqual(m.agent, .claude)
        XCTAssertEqual(m.ask, .command)
        XCTAssertEqual(m.command, "swift test --filter CaptionTests")
        XCTAssertEqual(m.question, "Do you want to proceed?")
        XCTAssertEqual(m.options.map(\.key), ["1", "2", AnswerKeys.escape])
    }

    func testClaudeUnboxedPush() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.claudePushPromptUnboxed))
        XCTAssertEqual(m.command, "git push origin work")
    }

    func testClaudeEdit() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.claudeEditPrompt, agent: .claude))
        XCTAssertEqual(m.ask, .edit)
        XCTAssertEqual(m.path, "Sources/OneRoofCore/Feed.swift")
        XCTAssertEqual(m.options[1].label, "Yes, allow all edits during this session")
    }

    func testClaudeFetch() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.claudeFetchPrompt, agent: .claude))
        XCTAssertEqual(m.ask, .fetch)
        XCTAssertEqual(m.url, "https://herdr.dev/docs/protocol")
    }

    func testCodexCommand() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.codexPushPrompt, agent: .codex))
        XCTAssertEqual(m.agent, .codex)
        XCTAssertEqual(m.command, "git push origin work")
        XCTAssertEqual(m.options.map(\.key), ["y", "a", AnswerKeys.escape])
    }

    func testCodexEdits() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.codexEditPrompt, agent: .codex))
        XCTAssertEqual(m.ask, .edit)
        XCTAssertEqual(m.path, "src/config.rs")
    }

    func testKimiBoxed() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.kimiInstallPrompt, agent: .kimi))
        XCTAssertEqual(m.agent, .kimi)
        XCTAssertEqual(m.command, "pip install requests")
        XCTAssertEqual(m.options.count, 3)
    }

    func testKimiInline() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.kimiInlinePrompt, agent: .kimi))
        XCTAssertEqual(m.command, "du -sh *")
        XCTAssertEqual(m.options.map(\.key), ["y", "a", "n"])
    }

    func testGemini() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.geminiDeletePrompt, agent: .gemini))
        XCTAssertEqual(m.agent, .gemini)
        XCTAssertEqual(m.command, "rm -rf build")
        XCTAssertEqual(m.options.first?.label, "Yes, allow once")
    }

    func testAntigravity() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(Fixture.antigravityNetworkPrompt, agent: .agy))
        XCTAssertEqual(m.agent, .agy)
        XCTAssertEqual(m.command, "curl -s https://registry.npmjs.org/left-pad")
        XCTAssertEqual(m.question, "Run this command?")
    }

    func testNoPromptNoMatch() {
        XCTAssertNil(DecisionMatcher.match("⏺ Bash(ls)\n  ⎿  a b c\n\n⏺ Done.", agent: .claude))
        XCTAssertNil(DecisionMatcher.match("Do you want to proceed?\n(no options)", agent: .claude))
    }

    func testFallsBackToOtherMatchers() {
        // Agent unknown to herdr (or wrong): the Codex prompt is still read.
        XCTAssertEqual(DecisionMatcher.match(Fixture.codexPushPrompt, agent: .claude)?.agent, .codex)
    }
}

final class TouchesTests: XCTestCase {
    let repo = "/Users/x/Projects/acme/web"

    func testReadOnly() {
        let t = CommandAnalyzer.analyze("git status && git diff --stat", repo: repo)
        XCTAssertEqual(t.classes, [.readOnly])
        XCTAssertEqual(t.sentence, "Reads the repo, writes nothing. No network. No git changes.")
    }

    func testBuildWritesOnlyBuildFolder() {
        let t = CommandAnalyzer.analyze("swift build", repo: repo)
        XCTAssertEqual(t.sentence, "Reads the repo, writes only to .build/. No network. No git changes.")
        XCTAssertEqual(DecisionBuilder.risk(kind: .runCommand, touches: t), .low)
    }

    func testTestIsDetected() {
        XCTAssertTrue(CommandAnalyzer.analyze("cd app && swift test --filter X", repo: repo).isTest)
        XCTAssertTrue(CommandAnalyzer.analyze("python3 -m pytest -q", repo: repo).isTest)
        XCTAssertTrue(CommandAnalyzer.analyze("bash -lc 'npm test'", repo: repo).isTest)
    }

    func testWritesInsideRepo() {
        let t = CommandAnalyzer.analyze("echo hi > notes/out.txt", repo: repo)
        XCTAssertTrue(t.classes.contains(.writesRepo))
        XCTAssertFalse(t.classes.contains(.readOnly))
        XCTAssertEqual(t.sentence, "Writes inside the repo (notes/out.txt). No network. No git changes.")
        XCTAssertEqual(DecisionBuilder.risk(kind: .runCommand, touches: t), .low)
    }

    func testWritesOutsideRepo() {
        let t = CommandAnalyzer.analyze("cp .build/release/OneRoof /usr/local/bin/OneRoof", repo: repo)
        XCTAssertTrue(t.classes.contains(.writesOutside))
        XCTAssertTrue(t.sentence.hasPrefix("Writes outside the repo (/usr/local/bin/OneRoof)."))
        XCTAssertEqual(DecisionBuilder.risk(kind: .runCommand, touches: t), .high)
    }

    func testNetwork() {
        let t = CommandAnalyzer.analyze("curl -sL https://example.com/data.json -o data.json", repo: repo)
        XCTAssertTrue(t.classes.contains(.network))
        XCTAssertTrue(t.sentence.contains("Uses the network (example.com)."))
        XCTAssertTrue(CommandAnalyzer.analyze("git fetch origin", repo: repo).classes.contains(.network))
    }

    func testInstalls() {
        let t = CommandAnalyzer.analyze("npm install left-pad", repo: repo)
        XCTAssertTrue(t.classes.isSuperset(of: [.installs, .network]))
        XCTAssertTrue(t.sentence.contains("Installs left-pad from npm."))
        XCTAssertTrue(CommandAnalyzer.analyze("brew install ripgrep", repo: repo).classes.contains(.installs))
        XCTAssertTrue(CommandAnalyzer.analyze("pip install -r requirements.txt", repo: repo).classes.contains(.installs))
    }

    func testDeletes() {
        let rm = CommandAnalyzer.analyze("rm -rf build", repo: repo)
        XCTAssertTrue(rm.classes.contains(.deletes))
        XCTAssertTrue(rm.sentence.contains("Deletes build."))
        let reset = CommandAnalyzer.analyze("git reset --hard HEAD~1", repo: repo)
        XCTAssertTrue(reset.classes.isSuperset(of: [.deletes, .gitChanges]))
        XCTAssertTrue(CommandAnalyzer.analyze("git clean -fdx", repo: repo).classes.contains(.deletes))
        XCTAssertEqual(DecisionBuilder.risk(kind: .runCommand, touches: rm), .high)
    }

    func testSecrets() {
        XCTAssertTrue(CommandAnalyzer.analyze("cat .env", repo: repo).classes.contains(.secrets))
        let k = CommandAnalyzer.analyze("security find-generic-password -s herdr -w", repo: repo)
        XCTAssertTrue(k.classes.contains(.secrets))
        XCTAssertTrue(k.sentence.contains("Reads secrets (the keychain)."))
        XCTAssertTrue(CommandAnalyzer.analyze("printenv", repo: repo).classes.contains(.secrets))
    }

    func testPushAndGitChanges() {
        let p = CommandAnalyzer.analyze("git push origin main", repo: repo)
        XCTAssertTrue(p.isPush)
        XCTAssertTrue(p.sentence.hasSuffix("Git: pushes."))
        let c = CommandAnalyzer.analyze("git add -A && git commit -m 'x'", repo: repo)
        XCTAssertTrue(c.classes.contains(.gitChanges))
        XCTAssertTrue(c.sentence.contains("Git: git add, git commit."))
    }

    func testUnknownScriptIsHighRisk() {
        let t = CommandAnalyzer.analyze("./scripts/deploy.sh --prod", repo: repo)
        XCTAssertTrue(t.classes.contains(.unknown))
        XCTAssertEqual(DecisionBuilder.risk(kind: .runCommand, touches: t), .high)
    }

    func testPattern() {
        XCTAssertEqual(CommandAnalyzer.pattern(for: "cd app && swift test --filter X"), "swift test")
        XCTAssertEqual(CommandAnalyzer.pattern(for: "npm run build -- --prod"), "npm run build")
        XCTAssertEqual(CommandAnalyzer.pattern(for: "ls -la"), "ls")
        XCTAssertEqual(CommandAnalyzer.pattern(for: "python3 -m pytest -q"), "python3 -m pytest")
        XCTAssertEqual(CommandAnalyzer.pattern(for: "git -C x push origin"), "git push")
    }
}

final class DecisionBuilderTests: XCTestCase {
    let repo = "/Users/x/Projects/acme/web"
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func ctx(_ text: String, _ agent: AgentKind, past: [Decision] = []) -> DecisionContext {
        DecisionContext(sessionId: "s1", agent: agent, terminalText: text, repoPath: repo, ticket: "ENG-569", step: 2, steps: 4,
                        added: 42, removed: 7, past: past, now: now, projectsRoot: "/Users/x/Projects")
    }

    func testClaudeTestCommand() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.claudeBashPrompt, .claude)))
        XCTAssertEqual(d.kind, .runCommand)
        XCTAssertEqual(d.command, "swift test --filter CaptionTests")
        XCTAssertEqual(d.why, "The parser is in place. I'll run the caption tests to check the heuristics.")
        XCTAssertFalse(d.whyMissing)
        XCTAssertEqual(d.risk, .low)
        XCTAssertEqual(d.ifNo, "skips the tests, marks step 2 not verified")
        XCTAssertEqual(d.where_, "ENG-569 · step 2 of 4 · +42 −7")
        XCTAssertEqual(d.pattern, "swift test")
        XCTAssertEqual(d.repo, "acme/web")
        XCTAssertEqual(d.title, "Claude wants to run swift test --filter CaptionTests")
    }

    func testCodexPush() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.codexPushPrompt, .codex)))
        XCTAssertEqual(d.kind, .push)
        XCTAssertEqual(d.risk, .high)
        XCTAssertEqual(d.ifNo, "commits stay local (Codex ends its turn and waits)")
        XCTAssertEqual(d.why, "I need to push the branch so CI can run.")
    }

    func testKimiInstall() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.kimiInstallPrompt, .kimi)))
        XCTAssertEqual(d.kind, .install)
        XCTAssertEqual(d.title, "Kimi wants to install requests")
        XCTAssertEqual(d.ifNo, "the step stops; you'll be asked how to continue")
    }

    func testGeminiDelete() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.geminiDeletePrompt, .gemini)))
        XCTAssertEqual(d.risk, .high)
        XCTAssertEqual(d.why, "The build folder is stale, so I'll remove it before rebuilding.")
    }

    func testAntigravityNetwork() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.antigravityNetworkPrompt, .agy)))
        XCTAssertEqual(d.kind, .network)
        XCTAssertEqual(d.risk, .high)
    }

    func testEditWithoutWhy() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.claudeEditPrompt, .claude)))
        XCTAssertEqual(d.kind, .editFile)
        XCTAssertTrue(d.whyMissing)
        XCTAssertEqual(d.why, DecisionBuilder.noWhy)
        XCTAssertEqual(d.risk, .low)
        XCTAssertTrue(d.touches.hasPrefix("Edits Sources/OneRoofCore/Feed.swift inside the repo."))
    }

    func testWhyKeepsAtMostTwoSentences() {
        let why = DecisionBuilder.whyText(["⏺ First I read it. Then I fixed it. Now I'll test it."])
        XCTAssertEqual(why, "Then I fixed it. Now I'll test it.")
    }

    func testPlanApproval() {
        let plan = Plan(objective: "Ship engines", done_when: nil, steps: [
            PlanStep(id: "1", title: "a", kind: nil, agent: "claude", account: nil, model: nil, depends: nil, done_when: nil, cost: nil, skill: nil, repo: nil, prompt: ""),
            PlanStep(id: "2", title: "b", kind: nil, agent: "codex", account: nil, model: nil, depends: nil, done_when: nil, cost: nil, skill: nil, repo: nil, prompt: ""),
        ], risks: nil, questions: nil)
        let d = DecisionBuilder.planApproval(sessionId: "p", agent: .claude, planId: UUID(), plan: plan, objective: "Ship engines", repoPath: repo, now: now)
        XCTAssertEqual(d.risk, .plan)
        XCTAssertEqual(d.kind, .approvePlan)
        XCTAssertEqual(d.ifNo, "nothing runs; the planner waits for edits")
        XCTAssertEqual(d.touches, "2 steps by Claude, Codex. Nothing runs until you approve.")
    }

    func past(_ answers: [Answer], pattern: String = "swift test", repo: String = "acme/web", daysAgo: Double = 1) -> [Decision] {
        answers.map { a in
            Decision(sessionId: "x", agent: .claude, kind: .runCommand, why: "", touches: "", risk: .low, ifNo: "", pattern: pattern, repo: repo,
                     askedAt: now.addingTimeInterval(-daysAgo * 86_400), answeredAt: now, answer: a)
        }
    }

    func testHistorySuggestsRuleAfterThreeAllows() {
        let h = DecisionBuilder.history(past([.allowOnce, .allowOnce, .always]), pattern: "swift test", repo: "acme/web", now: now)
        XCTAssertEqual(h.similarAllowed, 3)
        XCTAssertEqual(h.ruleSuggestion, "Always allow swift test in acme/web")
    }

    func testHistoryNoRuleWithDenyOldOrOtherRepo() {
        XCTAssertNil(DecisionBuilder.history(past([.allowOnce, .allowOnce, .allowOnce, .deny]), pattern: "swift test", repo: "acme/web", now: now).ruleSuggestion)
        XCTAssertEqual(DecisionBuilder.history(past([.allowOnce, .allowOnce, .allowOnce], daysAgo: 8), pattern: "swift test", repo: "acme/web", now: now).similarAllowed, 0)
        XCTAssertEqual(DecisionBuilder.history(past([.allowOnce], repo: "_common"), pattern: "swift test", repo: "acme/web", now: now).similarAllowed, 0)
    }

    func testBuildUsesHistory() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.claudeBashPrompt, .claude, past: past([.allowOnce, .allowOnce, .allowOnce]))))
        XCTAssertEqual(d.history.ruleSuggestion, "Always allow swift test in acme/web")
    }

    func testRuleMatches() throws {
        let d = try XCTUnwrap(DecisionBuilder.build(ctx(Fixture.claudeBashPrompt, .claude)))
        XCTAssertTrue(DecisionRule(pattern: "swift test", repo: "acme/web").matches(d))
        XCTAssertFalse(DecisionRule(pattern: "swift test", repo: "_common").matches(d))
    }
}

final class AnswerKeysTests: XCTestCase {
    func keys(_ fixture: String, _ agent: AgentKind, _ a: Answer, reply: String? = nil) -> AnswerKeys {
        AnswerKeys.keys(for: a, prompt: DecisionMatcher.match(fixture, agent: agent), agent: agent, reply: reply)
    }

    func testClaude() {
        XCTAssertEqual(keys(Fixture.claudeBashPrompt, .claude, .allowOnce).sends, ["1"])
        XCTAssertEqual(keys(Fixture.claudeBashPrompt, .claude, .always).sends, ["2"])
        XCTAssertEqual(keys(Fixture.claudeBashPrompt, .claude, .deny).sends, [AnswerKeys.escape])
        XCTAssertEqual(keys(Fixture.claudeBashPrompt, .claude, .reply, reply: "Run only the store tests").sends,
                       [AnswerKeys.escape, "Run only the store tests", "\r"])
    }

    func testCodex() {
        XCTAssertEqual(keys(Fixture.codexPushPrompt, .codex, .allowOnce).sends, ["y"])
        XCTAssertEqual(keys(Fixture.codexPushPrompt, .codex, .always).sends, ["a"])
        XCTAssertEqual(keys(Fixture.codexPushPrompt, .codex, .deny).sends, [AnswerKeys.escape])
    }

    func testKimiGeminiAntigravity() {
        XCTAssertEqual(keys(Fixture.kimiInstallPrompt, .kimi, .always).sends, ["2"])
        XCTAssertEqual(keys(Fixture.kimiInstallPrompt, .kimi, .deny).sends, ["3"])
        XCTAssertEqual(keys(Fixture.geminiDeletePrompt, .gemini, .always).sends, ["2"])
        XCTAssertEqual(keys(Fixture.geminiDeletePrompt, .gemini, .deny).sends, [AnswerKeys.escape])
        XCTAssertEqual(keys(Fixture.antigravityNetworkPrompt, .agy, .allowOnce).sends, ["y"])
        XCTAssertEqual(keys(Fixture.antigravityNetworkPrompt, .agy, .deny).sends, ["n"])
        XCTAssertEqual(keys(Fixture.kimiInlinePrompt, .kimi, .reply, reply: "skip it").sends, ["n", "skip it", "\r"])
    }

    func testAlwaysWithoutOptionFallsBackToOnce() {
        let opts = [PromptMatch.Option(label: "Yes", key: "1"), PromptMatch.Option(label: "No", key: "2")]
        let m = PromptMatch(agent: .claude, ask: .command, question: "Do you want to proceed?", options: opts, startLine: 0)
        let k = AnswerKeys.keys(for: .always, prompt: m, agent: .claude)
        XCTAssertEqual(k.sends, ["1"])
        XCTAssertFalse(k.exact)
    }

    func testInterrupt() {
        XCTAssertEqual(AnswerKeys.interrupt(.claude), "\u{1B}")
        XCTAssertEqual(AnswerKeys.interrupt(.codex), "\u{03}")
    }
}

final class KimiPanelPromptTests: XCTestCase {
    /// Captured from a live Kimi Code pane (2026-10-18).
    let live = """
     ● Running a command · $ python3 /Users/x/.kimi-code/skills/plan-review/scripts/plan_proof_v2.py publish /Users/x/PLAN.md
       Press Ctrl+B to run in background
     ──────────────────────────────────────────────────────────
       ▶ Run this command?

       cwd: /Users/x/Projects
       $ python3 /Users/x/.kimi-code/skills/plan-review/scripts/plan_proof_v2.py publish /Users/x/PLAN.md
         --slug ws-web-goals-01

       ▶ 1. Approve once
         2. Approve for this session
         3. Reject
         4. Reject with feedback

       ↑/↓ select · 1/2/3/4 choose · ↵ confirm
     ──────────────────────────────────────────────────────────
     [Kimi] logged in · Moderato · K2.8 Preview
    """

    func testMatchesTheLivePanel() throws {
        let m = try XCTUnwrap(DecisionMatcher.match(live, agent: .kimi))
        XCTAssertEqual(m.ask, .command)
        XCTAssertEqual(m.command, "python3 /Users/x/.kimi-code/skills/plan-review/scripts/plan_proof_v2.py publish /Users/x/PLAN.md --slug ws-web-goals-01")
        XCTAssertEqual(m.options.map(\.key), ["1", "2", "3", "4"])
        XCTAssertEqual(AnswerKeys.keys(for: .allowOnce, prompt: m, agent: .kimi).sends, ["1"])
        XCTAssertEqual(AnswerKeys.keys(for: .always, prompt: m, agent: .kimi).sends, ["2"])
        XCTAssertEqual(AnswerKeys.keys(for: .deny, prompt: m, agent: .kimi).sends, ["3"])
    }
}
