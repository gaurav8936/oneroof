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
}
