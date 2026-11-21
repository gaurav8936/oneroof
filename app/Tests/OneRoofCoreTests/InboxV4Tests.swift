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
        XCTAssertEqual(InboxFilter.defaultFilter(blocks, tier: tierById), .sessions, "a session blocked on you opens Sessions")
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

    // MARK: LAB-2341 · loop items in their own words, folded

    private func outcome(_ id: Int, _ kind: String, title: String, link: String = "", created: String, detail: String = "{}") -> LoopLedger.Outcome {
        LoopLedger.Outcome(id: id, runId: "r\(id)", loop: "docs-drift", kind: kind, link: link, title: title, status: "staged",
                           decidedBy: nil, decidedAt: nil, created: created, detail: detail)
    }

    func test_LAB2341_proposalFileParsed() {
        let text = """
        # Proposal: Cut the installed skill list in ~/.claude/skills to ≤ 28 (Lessons behind /learn)

        **Loop:** docs-drift · **Run:** r-1 · **Status:** open · **Change:** rule · **Target:** ~/.claude/skills

        > every listed skill costs context each turn; the kit installs Commands only

        ## Evidence

        - 49 entries

        ## Decide

        - not evidence
        """
        let d = LoopDocs.proposal(text, path: "/j/proposals/2026-11-20_p-6421_cut-the-installed-skill-list-in-claude-skills-to.md")
        XCTAssertEqual(d.title, "Cut the installed skill list in ~/.claude/skills to ≤ 28 (Lessons behind /learn)")
        XCTAssertEqual(d.evidence, ["49 entries"])
        XCTAssertEqual(d.change, "rule"); XCTAssertEqual(d.target, "~/.claude/skills")
        XCTAssertEqual(d.why, "every listed skill costs context each turn; the kit installs Commands only")
        XCTAssertEqual(d.slug, "cut-the-installed-skill-list-in-claude-skills-to"); XCTAssertEqual(d.id, "p-6421")
        XCTAssertEqual(LoopDocs.index(["2026-11-20_p-6421_cut.md", "index.jsonl"], folder: "/j")["p-6421"], "/j/2026-11-20_p-6421_cut.md")
    }

    func test_LAB2341_refiledProposalsFoldAndDecideTogether() {
        let staged = (1...17).map { outcome($0, "proposal", title: String(format: "p-%04x", 0xa000 + $0), link: String(format: "journal:p-%04x", 0xa000 + $0),
                                            created: String(format: "2026-11-%02dT06:00:00-08:00", min(21, 4 + $0))) }
        var docs: [String: LoopDoc] = [:]
        for o in staged { docs[o.title] = LoopDoc(title: "Cut the installed skill list", evidence: ["49 entries"], target: "~/.claude/skills", slug: "cut-the-skill-list", id: o.title) }
        let reports = (18...20).map { outcome($0, "report", title: "[docs-drift] 1 finding(s): ~/.claude/skills lists 49 skills (budget 28)",
                                              created: "2026-11-20T19:30:00+05:30", detail: #"{"body": "~/.claude/skills  49 skills"}"#) }
        let items = LoopInbox.fold(LoopInbox.attach(LoopInbox.today(staged + reports), proposals: docs))
        XCTAssertEqual(items.count, 2, "17 proposals → 1, 3 identical reports → 1")
        let p = items.first { $0.outcomeKind == "proposal" }!
        XCTAssertEqual(p.copies, 17); XCTAssertEqual(p.outcomeIds.count, 17, "a decision writes every copy")
        XCTAssertLessThan(p.when, p.lastWhen!)
        XCTAssertEqual(InboxRowText.loopTitle(p), "Cut the installed skill list")
        let r = items.first { $0.outcomeKind == "report" }!
        XCTAssertEqual(r.copies, 3); XCTAssertEqual(r.doc?.title, "1 finding(s): ~/.claude/skills lists 49 skills (budget 28)")
        XCTAssertEqual(LoopInbox.relatedProposal(r, in: items)?.id, p.id, "the report names the proposal's target")
        XCTAssertEqual(LoopInbox.relatedReports(p, in: items).map(\.id), [r.id])
        XCTAssertEqual(InboxTier.of(r), .p2); XCTAssertEqual(InboxTier.of(p), .p1)
        XCTAssertEqual(LoopInbox.muteKey(p), "docs-drift|cut-the-skill-list")
        XCTAssertEqual(InboxRowText.kindTag(p), "Proposal")
    }

    func test_LAB2341_reportsExpireAfterSevenDays() {
        let f = ISO8601DateFormatter()
        let now = f.date(from: "2026-11-21T12:00:00Z")!
        let old = outcome(1, "report", title: "r", created: "2026-11-13T12:00:00Z")
        let fresh = outcome(2, "report", title: "r", created: "2026-11-15T12:00:00Z")
        let oldProposal = outcome(3, "proposal", title: "p-1234", created: "2026-11-01T12:00:00Z")
        XCTAssertEqual(LoopInbox.expired([old, fresh, oldProposal], now: now).map(\.id), [1], "only reports and notes expire")
    }

    // LAB-2343 · the badge count without building the Inbox matches counting P0 blocks of the layout
    func test_LAB2343_p0CountMatchesTheLayout() {
        func dec(_ sid: String, _ pattern: String, why: String = "w", ago: Double) -> Decision {
            Decision(sessionId: sid, agent: .claude, kind: .runCommand, command: "c", why: why, touches: "t", risk: .low, ifNo: "n",
                     pattern: pattern, repo: "r", askedAt: now.addingTimeInterval(-ago))
        }
        let open = [dec("a", "swift test", ago: 60),                                   // P0
                    dec("b", Decision.questionPrefix + "q", ago: 120),                  // P1 (oldest of b) …
                    dec("b", "git push", ago: 30),                                      // … so b does not count
                    dec("c", Decision.finishedPrefix + "x", why: "error: failed", ago: 10), // P0 (halt words)
                    dec("d", Decision.finishedPrefix + "x", why: "Done.", ago: 5)]      // P2
        let loops = [LoopInbox.Item(id: "failed-mh", kind: .failed, loopId: "mh", loopTitle: "M", headline: "h", detail: "", when: now),
                     LoopInbox.Item(id: "staged-o-1", kind: .staged, loopId: "dd", loopTitle: "D", headline: "h", detail: "", when: now)]
        let layout = Inbox.layout(open: open, plans: [("p1", now)], loops: loops.map { ($0.id, $0.when) })
        let viaLayout = layout.all.filter { b in InboxTier.of(b, loopItem: loops.first { $0.id == b.loopItemId }) == .p0 }.count
        XCTAssertEqual(InboxTier.p0Count(open: open, plansWaiting: 1, loops: loops), viaLayout)
        XCTAssertEqual(viaLayout, 4, "a, c, the plan, the stopped loop")
    }
}
