import XCTest
@testable import OneRoofCore

/// LAB-2042 · LAB-2043 · the Inbox (the live place that replaced Needs you's queue + detail): block building, kinds,
/// options, what sending does, the copy, images, the name and icon, and the shortcut carry-over.
final class InboxTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func perm(_ sid: String, at s: Double, choices: [DecisionChoice]? = nil, agent: AgentKind = .claude,
                      pattern: String = "swift test", whyMissing: Bool = false) -> Decision {
        Decision(sessionId: sid, agent: agent, kind: .runCommand, command: "swift test", why: "run the tests", whyMissing: whyMissing,
                 touches: "repo", risk: .low, ifNo: "it stops", pattern: pattern, repo: "acme/web", askedAt: t0.addingTimeInterval(s),
                 choices: choices)
    }
    private func question(_ sid: String, at s: Double) -> Decision {
        Decision(sessionId: sid, agent: .kimi, kind: .other, why: "Which one?", touches: "Nothing", risk: .low, ifNo: "waits",
                 pattern: Decision.questionPrefix + "Which one?", repo: "r", askedAt: t0.addingTimeInterval(s))
    }
    private func finished(_ sid: String, at s: Double) -> Decision {
        Decision(sessionId: sid, agent: .claude, kind: .other, why: "Done. Next?", touches: "Nothing", risk: .low, ifNo: "waits",
                 pattern: Decision.finishedPrefix + "x", repo: "r", askedAt: t0.addingTimeInterval(s))
    }
    private func menu(_ sid: String, at s: Double, free: Bool = true) -> Decision {
        var c = [DecisionChoice(label: "Folders first", key: "1"), DecisionChoice(label: "A to Z", key: "2")]
        if free { c.append(DecisionChoice(label: "Type something.", key: "3", freeText: true)) }
        return Decision(sessionId: sid, agent: .codex, kind: .other, why: DecisionBuilder.noWhy, whyMissing: true, touches: "A question",
                        risk: .low, ifNo: "waits", pattern: "ask:Which order?", repo: "r", askedAt: t0.addingTimeInterval(s), choices: c,
                        screen: ["  Which order?", "  › 1. Folders first", "    2. A to Z"])
    }
    let claudeOptions = [DecisionChoice(label: "Yes", key: "1"),
                         DecisionChoice(label: "Yes, and don't ask again for swift test commands", key: "2"),
                         DecisionChoice(label: "No, and tell Claude what to do differently", key: "3", freeText: true)]

    // MARK: Blocks

    func test_LAB2042_blocks_onePerSessionNewestFirst_plansWithThem_loopsAfter() {
        let open = [perm("a", at: 10), question("b", at: 50), perm("a", at: 70), finished("c", at: 30)]
        let l = Inbox.layout(open: open, plans: [(id: "p1", at: t0.addingTimeInterval(40))],
                             loops: [(id: "L1", at: t0.addingTimeInterval(5)), (id: "L2", at: t0.addingTimeInterval(90))])
        XCTAssertEqual(l.asks.map(\.id), ["session-b", "plan-p1", "session-c", "session-a"], "newest at the top (owner 11-01)")
        XCTAssertEqual(l.loops.map(\.id), ["loop-L2", "loop-L1"], "loop items after sessions, newest first, never as sessions")
        XCTAssertEqual(l.all.count, 6)
        let a = l.asks.last!
        XCTAssertEqual(a.decision?.askedAt, t0.addingTimeInterval(10), "a session shows its oldest open ask first")
        XCTAssertEqual(a.more, 1)
        XCTAssertEqual(Inbox.moreLine(a.more), "1 more from this session")
        XCTAssertNil(Inbox.moreLine(0))
    }

    func test_LAB2042_blocks_waitingSessionWithoutAFiledAskStillShows() {
        let l = Inbox.layout(open: [perm("a", at: 1)], plans: [], loops: [], waiting: ["a", "z"])
        XCTAssertEqual(l.asks.map(\.id), ["session-a", "session-z"])
        XCTAssertEqual(l.asks[1].kind, .waiting)
        XCTAssertEqual(l.asks[0].kind, .permission, "a session with a filed ask is not doubled")
    }

    func test_LAB2042_quietSessionsAreCountedNotShown() {
        let l = Inbox.layout(open: [perm("a", at: 1)], plans: [], loops: [])
        XCTAssertEqual(Inbox.quietCount(liveSessions: ["a", "b", "c"], shown: l.all), 2)
        XCTAssertEqual(Inbox.othersLine(2), "2 other sessions working ›")
        XCTAssertEqual(Inbox.othersLine(1), "1 other session working ›")
        XCTAssertNil(Inbox.othersLine(0))
    }

    func test_LAB2042_headerCopy() {
        XCTAssertEqual(Inbox.waitingLine(0), "Nothing waiting")
        XCTAssertEqual(Inbox.waitingLine(1), "1 thing waiting for your attention")
        XCTAssertEqual(Inbox.waitingLine(3), "3 things waiting for your attention")
        XCTAssertEqual(Inbox.newAboveLine(1), "1 new above ↑")
    }

    func test_LAB2042_kindTagPerDecision() {
        XCTAssertEqual(InboxKind.of(perm("a", at: 0)), .permission)
        XCTAssertEqual(InboxKind.of(question("a", at: 0)), .question)
        XCTAssertEqual(InboxKind.of(finished("a", at: 0)), .finished)
        XCTAssertEqual(InboxKind.of(menu("a", at: 0)), .menu)
        XCTAssertEqual(InboxKind.permission.tag, "Permission")
        XCTAssertEqual(InboxKind.menu.tag, "Question")
        XCTAssertEqual(InboxKind.question.tag, "Asked a question")
        XCTAssertEqual(InboxKind.finished.tag, "Finished · waiting for you")
    }

    func test_LAB2042_keyboardStepWrapsAndPickFindsBlocks() {
        let l = Inbox.layout(open: [perm("a", at: 1), question("b", at: 2)], plans: [(id: "p", at: t0)], loops: [(id: "L", at: t0)])
        let ids = l.all.map(\.id)
        XCTAssertEqual(Inbox.step(from: ids[0], by: 1, in: l.all), ids[1])
        XCTAssertEqual(Inbox.step(from: ids[0], by: -1, in: l.all), ids.last, "⌘[ from the top wraps to the bottom")
        XCTAssertEqual(Inbox.step(from: "gone", by: 1, in: l.all), ids[0])
        let d = l.all.first { $0.sessionId == "a" }!.decision!
        XCTAssertEqual(Inbox.block(for: d.id.uuidString, in: l.all)?.id, "session-a", "needspick by decision id")
        XCTAssertEqual(Inbox.block(for: "plan-p", in: l.all)?.kind, .plan)
        XCTAssertEqual(Inbox.block(for: "loop-L", in: l.all)?.kind, .loop, "LOOPPICK's loop-<id> still works")
    }

    // MARK: Options (LAB-1839, LAB-1907)

    func test_LAB2042_optionsAreThePromptsOwnInOrderAndWords() {
        let b = Inbox.buttons(perm("a", at: 0, choices: claudeOptions))
        XCTAssertEqual(b.map(\.title), ["1. Yes  ↩", "2. Yes, and don't ask again for swift test commands",
                                        "3. No, and tell Claude what to do differently"])
        XCTAssertEqual(b.filter(\.primary).count, 1)
        XCTAssertTrue(b[0].primary)
        XCTAssertEqual(Inbox.defaultButton(b)?.title, "1. Yes  ↩", "↩ presses the first option")
        XCTAssertEqual(Inbox.numbered(2, in: b)?.action, .choice(claudeOptions[1]), "2 presses option 2")
        XCTAssertNil(Inbox.numbered(4, in: b))
    }

    func test_LAB2042_notPressableOptionIsDisabledWithTooltip() {
        let c = [DecisionChoice(label: "Allow", key: ""), DecisionChoice(label: "Reject", key: "\u{1B}")]
        let b = Inbox.buttons(perm("a", at: 0, choices: c, agent: .opencode))
        XCTAssertFalse(b[0].enabled)
        XCTAssertEqual(b[0].help, "Allow: pick this one in the agent's own terminal")
        XCTAssertEqual(Inbox.defaultButton(b)?.title, "2. Reject", "↩ skips an option One Roof cannot press")
    }

    func test_LAB2042_fixedAnswersWhenNoOptionsWereRead() {
        let b = Inbox.buttons(perm("a", at: 0))
        XCTAssertEqual(b.map(\.title), ["Allow once ↩", "Always allow this", "Deny esc"])
        XCTAssertEqual(b[1].help, "Always allow swift test in acme/web")
        XCTAssertEqual(Inbox.cancelButton(b)?.action, .deny, "esc denies")
        XCTAssertEqual(Inbox.buttons(perm("a", at: 0, pattern: "ask:Proceed?")).map(\.title), ["Allow once ↩", "Deny esc"],
                       "no Always allow for an ask: pattern")
        let oc = Inbox.buttons(perm("a", at: 0, agent: .opencode))
        XCTAssertEqual(oc.map(\.title), ["Allow once ↩", "Deny esc"])
        XCTAssertFalse(oc[0].enabled, "Allow once is off for OpenCode")
    }

    func test_LAB2042_menuHasItsOptionsAndCancel_finishedHasReplySetAsideClose() {
        let m = Inbox.buttons(menu("a", at: 0))
        XCTAssertEqual(m.map(\.title), ["1. Folders first  ↩", "2. A to Z", "3. Type something.", "Cancel esc"])
        XCTAssertEqual(Inbox.cancelButton(m)?.action, .cancel)
        XCTAssertEqual(Inbox.numbered(3, in: m)?.title, "3. Type something.")
        let f = Inbox.buttons(finished("a", at: 0))
        XCTAssertEqual(f.map(\.title), ["Reply ↩", "Set aside", "Close session"])
        XCTAssertEqual(f[1].help, "Nothing more for now: it leaves the Inbox, the session stays open")
        XCTAssertTrue(f[2].danger)
        XCTAssertEqual(Inbox.planButtons().map(\.title), ["Approve plan", "Edit plan", "Reject"])
    }

    // MARK: Sending (today's semantics)

    func test_LAB2042_sendRulePerKind() {
        XCTAssertEqual(Inbox.send(question("a", at: 0), text: " Postgres "), .reply("Postgres"))
        XCTAssertEqual(Inbox.send(finished("a", at: 0), text: "continue"), .reply("continue"))
        XCTAssertEqual(Inbox.send(perm("a", at: 0), text: "skip the snapshots"), .reply("skip the snapshots"), "Esc, then the text")
        XCTAssertEqual(Inbox.send(perm("a", at: 0, choices: claudeOptions), text: "use --parallel"), .choice(claudeOptions[2], "use --parallel"),
                       "a prompt with a free-text option takes the text through it")
        XCTAssertEqual(Inbox.send(menu("a", at: 0), text: "by date"), .choice(DecisionChoice(label: "Type something.", key: "3", freeText: true), "by date"))
        XCTAssertEqual(Inbox.send(menu("a", at: 0, free: false), text: "x"), .nothing)
        XCTAssertEqual(Inbox.send(perm("a", at: 0), text: "   "), .nothing)
        XCTAssertEqual(Inbox.send(perm("a", at: 0, agent: .goose), text: "x"), .nothing, "hosted agents: the reply box is off")
    }

    func test_LAB2042_freeTextOptionWithEmptyBoxMovesToTheBox() {
        let d = perm("a", at: 0, choices: claudeOptions)
        XCTAssertEqual(Inbox.choose(d, claudeOptions[2], text: ""), .focusBox)
        XCTAssertEqual(Inbox.choose(d, claudeOptions[2], text: "try again"), .choice(claudeOptions[2], "try again"))
        XCTAssertEqual(Inbox.choose(d, claudeOptions[0], text: "ignored"), .choice(claudeOptions[0], nil))
        let m = menu("a", at: 0), free = m.choices![2]
        XCTAssertEqual(Inbox.choose(m, free, text: ""), .choice(free, nil), "a menu's Type something. opens the agent's own field")
    }

    func test_LAB2042_placeholdersAndFooters() {
        XCTAssertEqual(Inbox.placeholder(perm("a", at: 0), agentName: "Claude1"), "Or reply with instructions: \u{201C}Run them, but skip the snapshot tests\u{201D}")
        XCTAssertEqual(Inbox.placeholder(perm("a", at: 0, whyMissing: true), agentName: "Claude1"), "Ask it: why do you want to do this?")
        XCTAssertEqual(Inbox.placeholder(question("a", at: 0), agentName: "Kimi"), "Your answer")
        XCTAssertEqual(Inbox.placeholder(menu("a", at: 0), agentName: "Codex"), "Your own answer")
        XCTAssertNil(Inbox.placeholder(menu("a", at: 0, free: false), agentName: "Codex"), "no box without an own-answer option")
        XCTAssertEqual(Inbox.placeholder(finished("a", at: 0), agentName: "Claude2"), "Next message for Claude2: continue, or ask it something")
        XCTAssertEqual(Inbox.footer(question("a", at: 0), agentName: "Kimi"), "Your answer goes to Kimi as its next message. You can also answer in the terminal.")
        XCTAssertEqual(Inbox.footer(menu("a", at: 0), agentName: "Codex"), "Each button presses that option in Codex's terminal. You can also answer there.")
        XCTAssertTrue(Inbox.footer(perm("a", at: 0, choices: claudeOptions), agentName: "C").hasPrefix("This waits until you choose. ↩ the first option"))
        XCTAssertTrue(Inbox.footer(perm("a", at: 0), agentName: "C").contains("↩ allow once · esc deny"))
        XCTAssertNotNil(Inbox.hostedNote(perm("a", at: 0, agent: .opencode)))
        XCTAssertNil(Inbox.hostedNote(perm("a", at: 0)))
    }

    func test_LAB2042_bodyAsTheTerminalShowsIt() {
        let p = Inbox.body(perm("a", at: 0), agentName: "Claude1")
        XCTAssertEqual(p.headline, "Claude1 wants to run swift test", "the account's name, as today")
        XCTAssertEqual(p.lines, ["$ swift test"])
        let m = Inbox.body(menu("a", at: 0), agentName: "Codex")
        XCTAssertNil(m.headline, "the screen already shows the question: not twice")
        XCTAssertEqual(m.lines.count, 3, "a menu is drawn as its screen")
        var bare = menu("a", at: 0); bare.screen = ["  › 1. Folders first"]
        XCTAssertEqual(Inbox.body(bare, agentName: "Codex").headline, "Which order?")
        XCTAssertEqual(Inbox.body(question("a", at: 0), agentName: "K").lines, ["Which one?"])
        var g = menu("a", at: 0); g.touches = DecisionMatcher.geminiSignInRefused
        XCTAssertEqual(Inbox.body(g, agentName: "G").note, DecisionMatcher.geminiSignInRefused)
    }

    func test_LAB2042_riskLineAndLongFinishedTurns() {
        var d = perm("a", at: 0)
        d.history = DecisionHistory(similarAllowed: 3, ruleSuggestion: "Always allow swift test in acme/web")
        XCTAssertEqual(Inbox.riskSentence(d), "Same command you allowed 3 times this week. Always allow swift test in acme/web.")
        XCTAssertEqual(Inbox.riskSentence(perm("a", at: 0)), "")
        XCTAssertFalse(Inbox.isLong("one\ntwo"))
        XCTAssertTrue(Inbox.isLong(Array(repeating: "line", count: 13).joined(separator: "\n")))
    }

    func test_LAB2042_answeredLineAndUnreachable() {
        var d = perm("a", at: 0); d.answer = .allowOnce
        XCTAssertTrue(Inbox.answeredLine(d).hasPrefix("You: Allowed once"))
        d.answer = .reply; d.replyText = "answered in the terminal"
        XCTAssertEqual(Inbox.answeredLine(d), "You: Answered in its terminal")
        XCTAssertEqual(Inbox.unreachable("Docs"), "Couldn't reach Docs: it isn't running. Open session to see why.")
    }

    func test_LAB2042_voiceOverLabel() {
        let now = t0.addingTimeInterval(4 * 60)
        XCTAssertEqual(Inbox.accessibilityLabel(session: "Docs", kind: .permission, at: t0, ask: "Run swift test", now: now),
                       "Docs, Permission, asked 4 min ago: Run swift test")
        XCTAssertEqual(Inbox.age(t0, now: t0.addingTimeInterval(3 * 3600)), "3 h")
        XCTAssertEqual(Inbox.age(.distantPast), "")
    }

    // MARK: Images

    func test_LAB2042_imagesAttach_max6_20MB_imagesOnly() {
        let r = Inbox.accept(["/a.png", "/b.txt", "/a.png", "/big.jpg"], existing: []) { $0 == "/big.jpg" ? 21 * 1024 * 1024 : 1000 }
        XCTAssertEqual(r.images, ["/a.png"])
        XCTAssertEqual(r.note, "That image is too big (max 20 MB)")
        let six = (1...6).map { "/\($0).png" }
        let full = Inbox.accept(["/7.png"], existing: six) { _ in 1 }
        XCTAssertEqual(full.images, six)
        XCTAssertEqual(full.note, "Up to 6 images per reply")
    }

    func test_LAB2042_replyWithImageNamesItOnOneLine() {
        let m = Inbox.message("Look at this", images: ["/Users/x/Library/Caches/OneRoof/pastes/paste-1.png"])
        XCTAssertEqual(m, "Look at this Attached image (read it): /Users/x/Library/Caches/OneRoof/pastes/paste-1.png")
        XCTAssertFalse(m.contains("\n"))
        XCTAssertEqual(Inbox.send(question("a", at: 0), text: Inbox.message("", images: ["/p.png"])), .reply("Attached image (read it): /p.png"),
                       "an image alone is a reply too")
    }

    // MARK: LAB-2043: the name, the icon, the keys

    func test_LAB2043_placeIsCalledInboxWithATrayIcon() {
        XCTAssertEqual(Place.needsYou.title, "Inbox")
        XCTAssertEqual(Place.needsYou.rawValue, "needsYou", "saved window state and the self-test keep the raw value")
        XCTAssertEqual(Place.needsYou.symbol(count: 0), "tray")
        XCTAssertEqual(Place.needsYou.symbol(count: 3), "tray.full")
        XCTAssertEqual(Place.home.symbol(count: 3), Place.home.symbol)
        XCTAssertEqual(Place.needsYou.controlKey, "2", "⌃⌘2")
    }

    func test_LAB2043_shortcutSavedUnderNeedsYouOrDecisionsAppliesToInbox() {
        XCTAssertEqual(MenuRenames.carry(["Needs You": "⌘J"])["Inbox"], "⌘J")
        XCTAssertEqual(MenuRenames.carry(["Decisions": "⌘J"])["Inbox"], "⌘J", "through the whole chain")
        XCTAssertEqual(MenuRenames.carry(["Decisions": "⌘J", "Inbox": "⌘K"])["Inbox"], "⌘K", "a shortcut set under Inbox wins")
        XCTAssertEqual(MenuRenames.carry(["Launchpad": "⌘L"])["Home"], "⌘L", "Home ← Overview ← Launchpad still resolves")
    }
}
