import XCTest
@testable import OneRoofCore

/// LAB-ONEROOF-v2.0.9 · Inbox v4.0 (handover 20261121_inbox_redesign).
final class InboxV4Tests: XCTestCase {
    let now = Date()

    private func ask(_ pattern: String, why: String = "w") -> Decision {
        Decision(sessionId: "s", agent: .claude, kind: .other, why: why, touches: "t", risk: .low, ifNo: "n",
                 pattern: pattern, repo: "r", askedAt: now)
    }

    private func staged(_ kind: String) -> LoopInbox.Item {
        let o = LoopLedger.Outcome(id: 1, runId: "r", loop: "docs-drift", kind: kind, link: "", title: "t", status: "staged",
                                   decidedBy: nil, decidedAt: nil, created: "2026-11-21T07:06:25+05:30", detail: "{}")
        return LoopInbox.Item(id: "staged-o-1", kind: .staged, loopId: "docs-drift", loopTitle: "Docs drift", headline: "h",
                              detail: "", when: now, outcomes: [o])
    }

    // MARK: LAB-2338 · IB-3 + IB-5

    func test_LAB2338_sessionTiers() {
        let permission = Decision(sessionId: "a", agent: .claude, kind: .runCommand, command: "swift test", why: "w", touches: "t",
                                  risk: .low, ifNo: "n", pattern: "swift test", repo: "r", askedAt: now)
        XCTAssertEqual(InboxTier.of(permission), .p0, "a permission blocks the agent")
        XCTAssertEqual(InboxTier.of(ask(Decision.questionPrefix + "Which order?")), .p1, "a question waits for a reply")
        XCTAssertEqual(InboxTier.of(ask(Decision.finishedPrefix + "Done. Tests pass.", why: "Done. Tests pass.")), .p2)
        XCTAssertEqual(InboxTier.of(ask(Decision.finishedPrefix + "x", why: "error: the build failed")), .p0, "halt words")
    }

    func test_LAB2338_loopTiers() {
        XCTAssertEqual(InboxTier.of(loopKind: .failed), .p0)
        XCTAssertEqual(InboxTier.of(loopKind: .asks), .p0)
        XCTAssertEqual(InboxTier.of(loopKind: .missed), .p1)
        for k in ["proposal", "issue", "promotion", "commit", "pr", "file"] { XCTAssertEqual(InboxTier.of(staged(k)), .p1, k) }
        for k in ["report", "slack"] { XCTAssertEqual(InboxTier.of(staged(k)), .p2, k) }
    }

    func test_LAB2338_onlyBlockedLoopItemsAreCritical() {
        func block(_ itemId: String) -> InboxBlock { InboxBlock(id: "loop-" + itemId, kind: .loop, at: now, loopItemId: itemId) }
        XCTAssertEqual(InboxUrgency.of(block("staged-o-12")), .informational, "a staged outcome is never red")
        XCTAssertEqual(InboxUrgency.of(block("staged-commit-bugs-r1")), .informational)
        XCTAssertEqual(InboxUrgency.of(block("missed-morning-health")), .informational)
        XCTAssertEqual(InboxUrgency.of(block("failed-morning-health")), .critical, "a loop stopped at a limit")
        XCTAssertEqual(InboxUrgency.of(block("asks-nightly-bugs")), .critical, "a round asks")
        XCTAssertEqual(InboxUrgency.of(InboxBlock(id: "plan-1", kind: .plan, at: now, planId: "1")), .critical)
        XCTAssertEqual(InboxTier.loopKind(ofItemId: "asks-x"), .asks)
        XCTAssertEqual(InboxTier.loopKind(ofItemId: "staged-o-1"), .staged)
    }

    // MARK: LAB-2339 · shell

    private func tierById(_ b: InboxBlock) -> InboxTier { InboxTier.of(b) }

    func test_LAB2339_filterCountsAndSections() {
        let perm = Decision(sessionId: "a", agent: .claude, kind: .runCommand, command: "swift test --repeat 20", why: "w", touches: "t",
                            risk: .low, ifNo: "n", pattern: "swift test", repo: "r", askedAt: now.addingTimeInterval(-240))
        let done = ask(Decision.finishedPrefix + "Done.", why: "Done.")
        let blocks = [InboxBlock(id: "session-a", kind: .permission, at: perm.askedAt, sessionId: "a", decision: perm),
                      InboxBlock(id: "session-s", kind: .finished, at: now, sessionId: "s", decision: done),
                      InboxBlock(id: "loop-failed-mh", kind: .loop, at: now, loopItemId: "failed-mh"),
                      InboxBlock(id: "loop-staged-o-1", kind: .loop, at: now, loopItemId: "staged-o-1"),
                      InboxBlock(id: "loop-staged-o-2", kind: .loop, at: now.addingTimeInterval(-60), loopItemId: "staged-o-2")]
        let c = InboxFeed.counts(blocks, tier: tierById)
        XCTAssertEqual([c.all, c.sessions, c.loops, c.p0, c.p0Sessions, c.p0Loops], [5, 2, 3, 2, 1, 1])
        XCTAssertEqual(InboxFilter.defaultFilter(blocks, tier: tierById), .sessions, "a session blocked on you opens Active sessions")
        XCTAssertEqual(InboxFilter.defaultFilter(Array(blocks.dropFirst()), tier: tierById), .all)
        let s = InboxFeed.sections(blocks, filter: .sessions, tier: tierById, loopOf: { _ in ("x", "X") })
        XCTAssertEqual(s.map(\.id), ["waiting", "not-waiting"])
        let all = InboxFeed.sections(blocks, filter: .all, tier: tierById, loopOf: { _ in ("x", "X") })
        XCTAssertEqual(all.flatMap(\.blocks).map(\.id), ["session-a", "session-s", "loop-failed-mh", "loop-staged-o-1", "loop-staged-o-2"],
                       "sessions first; loops by tier, then newest first")
        let loops = InboxFeed.sections(blocks, filter: .loops, tier: tierById, loopOf: { b in b.loopItemId == "failed-mh" ? ("mh", "Morning") : ("dd", "Docs") })
        XCTAssertEqual(loops.map(\.id), ["loop-mh", "loop-dd"], "loops in the order of their most urgent item")
        XCTAssertEqual(InboxFeed.subLine(c, filter: .sessions, loopCount: 2), "1 waiting on you · 1 finished")
        XCTAssertEqual(InboxFeed.loopsFoldLine(c), "3 loop items · 1 stopped")
    }

    func test_LAB2339_rowTextAndPostmarks() {
        let perm = Decision(sessionId: "a", agent: .claude, kind: .runCommand, command: "swift test --filter LoginTests --repeat 20", why: "w",
                            touches: "t", risk: .low, ifNo: "n", pattern: "swift test", repo: "r", askedAt: now)
        XCTAssertEqual(InboxRowText.ask(perm), "swift test")
        XCTAssertTrue(InboxRowText.isBareId("p-d0ae"))
        XCTAssertFalse(InboxRowText.isBareId("Cut the installed skill list"))
        XCTAssertEqual(Postmark.line(.proposal, sender: "docs-drift", copies: 17), "↻ PROPOSAL · docs-drift · ×17")
        XCTAssertEqual(Postmark.of(InboxBlock(id: "loop-asks-x", kind: .loop, at: now, loopItemId: "asks-x")), .roundAsks)
        XCTAssertEqual(Postmark.of(InboxBlock(id: "loop-staged-o-1", kind: .loop, at: now, loopItemId: "staged-o-1"), loopItem: staged("report")), .report)
    }

    func test_LAB2339_consoleContrast() {
        let k = ConsoleTokens.fixed
        XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, k.ground), 4.5)
        XCTAssertGreaterThanOrEqual(RGB.contrast(k.text, k.selected), 4.5)
        for ink in [k.plan, k.loop, k.stopped, k.system, k.link] { XCTAssertGreaterThanOrEqual(RGB.contrast(ink, k.ground), 4.5) }
        for t in InboxTier.allCases { XCTAssertGreaterThanOrEqual(RGB.contrast(k.tier(t).text, k.tier(t).fill), 4.5, t.label) }
        for a in [AgentKind.claude, .codex, .gemini, .kimi] {
            XCTAssertGreaterThanOrEqual(RGB.contrast(k.agentInk(SeatMark(agent: a, account: nil)), k.ground), 4.5, "\(a)")
        }
    }
}
