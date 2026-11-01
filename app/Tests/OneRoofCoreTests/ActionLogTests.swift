import XCTest
@testable import OneRoofCore

/// LAB-2047 · LAB-2048 · the Action log: the Inbox header's entry copy, the stored ask (options, screen, chosen), the
/// Decisions tab's filters and order, opening an entry, and Rules' Stop noting this rule + Undo.
final class ActionLogTests: XCTestCase {
    var path = ""
    let now = Date()
    override func setUp() { path = NSTemporaryDirectory() + "oneroof-actionlog-\(UUID().uuidString).sqlite" }
    override func tearDown() { for ext in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + ext) } }

    private func ask(_ s: String, _ cmd: String?, answered hoursAgo: Double, _ a: Answer, reply: String? = nil, chosen: String? = nil,
                     choices: [DecisionChoice]? = nil, pattern: String? = nil) -> Decision {
        let at = now.addingTimeInterval(-hoursAgo * 3600)
        return Decision(sessionId: s, agent: .claude, kind: cmd == nil ? .other : .runCommand, command: cmd, why: "why", touches: "t", risk: .low,
                        ifNo: "n", pattern: pattern ?? cmd ?? "ask:q", repo: "acme/web", askedAt: at.addingTimeInterval(-30), answeredAt: at,
                        answer: a, replyText: reply, choices: choices, screen: choices == nil ? nil : ["  Which order?", "  › 1. A", "    2. B"], chosen: chosen)
    }

    // MARK: LAB-2047 entry point

    func test_LAB2047_entryCopySingularPluralZeroAndCompact() {
        XCTAssertEqual(ActionLog.entryLine(decidedToday: 555, rules: 74), "Action log · 555 decided today · 74 rules ›")
        XCTAssertEqual(ActionLog.entryLine(decidedToday: 1, rules: 1), "Action log · 1 decided today · 1 rule ›")
        XCTAssertEqual(ActionLog.entryLine(decidedToday: 0, rules: 74), "Action log · nothing decided today · 74 rules ›")
        let c = ActionLog.entry(decidedToday: 5, rules: 2, compact: true)
        XCTAssertEqual(c.lead, "Action log ›", "under 1100 pt the counts drop")
        XCTAssertEqual(c.decided + c.rules, "")
        XCTAssertEqual(ActionLog.entryTooltip, "What you decided and the always-allow rules One Roof notes (Action log)")
        XCTAssertEqual(ActionLog.entryAccessibility(decidedToday: 555, rules: 74), "Action log, 555 decided today, 74 rules. Opens the action log.")
        XCTAssertTrue(ActionLog.rulesAccessibility(rules: 74).contains("Rules"))
    }

    // MARK: LAB-2048 data

    func test_LAB2048_optionsScreenAndChosenRoundTripAndOldAsksSayNotRecorded() throws {
        let store = try SessionStore(path: path)
        let opts = [DecisionChoice(label: "A", key: "1"), DecisionChoice(label: "B", key: "2"), DecisionChoice(label: "Type something.", key: "3", freeText: true)]
        let d = ask("s", nil, answered: 1, .reply, reply: "B", chosen: "B", choices: opts, pattern: "ask:Which order?")
        store.save(d, sessionName: "Docs")
        let back = try XCTUnwrap(store.decision(id: d.id))
        XCTAssertEqual(back.choices, opts)
        XCTAssertEqual(back.screen, d.screen)
        XCTAssertEqual(back.chosen, "B")
        XCTAssertEqual(ActionLog.options(back)?.map(\.chosen), [false, true, false], "the chosen one is marked")
        // An ask saved by 1.9.x: no options stored.
        let old = ask("s", "swift test", answered: 2, .allowOnce)
        store.save(old)
        XCTAssertNil(ActionLog.options(try XCTUnwrap(store.decision(id: old.id))))
        XCTAssertTrue(ActionLog.notRecorded.contains("weren't recorded"))
        // A later save without options keeps the stored ones; an answer records the chosen label.
        var again = d; again.choices = nil; again.screen = nil; again.chosen = nil
        store.save(again)
        XCTAssertEqual(store.decision(id: d.id)?.choices, opts)
        store.answer(decision: old.id, .allowOnce, reply: "Yes", chosen: "Yes")
        XCTAssertEqual(store.decision(id: old.id)?.chosen, "Yes")
    }

    func test_LAB2048_decisionsNewestFirstWithRangeSessionAnswerAndSearch() throws {
        let store = try SessionStore(path: path)
        let rows = [ask("a", "swift test", answered: 1, .allowOnce),
                    ask("a", "rm -rf .build", answered: 2, .deny),
                    ask("b", "npm run build", answered: 26, .always),
                    ask("b", nil, answered: 27, .reply, reply: "Folders first", chosen: "Folders first", pattern: "ask:Which order?"),
                    ask("c", "git push", answered: 24 * 3, .reply, reply: "answered in the terminal"),
                    ask("c", "git status", answered: 24 * 40, .allowOnce)]
        for r in rows { store.save(r, sessionName: r.sessionId == "c" ? "Gone" : nil) }
        let open = Decision(sessionId: "a", agent: .claude, kind: .runCommand, command: "ls", why: "w", touches: "t", risk: .low, ifNo: "n", pattern: "ls", repo: "r")
        store.save(open)
        let names = ["a": "Flaky login test", "b": "Docs"]
        func cmds(_ q: ActionLogQuery) -> [String] { store.actionLog(q, now: now, names: names).map { $0.decision.command ?? "?" } }
        XCTAssertEqual(cmds(ActionLogQuery()), ["swift test", "rm -rf .build", "npm run build", "?", "git push"], "newest answer first, open asks and > 7 days out")
        XCTAssertEqual(cmds(ActionLogQuery(range: .last30)).count, 5)
        XCTAssertEqual(store.actionLog(ActionLogQuery(range: .custom(from: now.addingTimeInterval(-50 * 86_400), to: now)), now: now, names: names).count, 6)
        XCTAssertEqual(cmds(ActionLogQuery(sessions: ["b"])), ["npm run build", "?"])
        XCTAssertEqual(cmds(ActionLogQuery(answers: [.denied])), ["rm -rf .build"])
        XCTAssertEqual(cmds(ActionLogQuery(answers: [.choseOption])), ["?"])
        XCTAssertEqual(cmds(ActionLogQuery(answers: [.answeredInTerminal])), ["git push"])
        XCTAssertEqual(cmds(ActionLogQuery(text: "folders")), ["?"], "search matches the answer")
        XCTAssertEqual(cmds(ActionLogQuery(text: "docs")), ["npm run build", "?"], "search matches the session's name")
        XCTAssertEqual(cmds(ActionLogQuery(text: "swift")), ["swift test"], "search matches the command")
        XCTAssertEqual(cmds(ActionLogQuery(sessions: ["a"], answers: [.allowedOnce])), ["swift test"], "filters together")
        let gone = try XCTUnwrap(store.actionLog(ActionLogQuery(sessions: ["c"]), now: now, names: names).first)
        XCTAssertEqual(gone.shownName, "Gone (closed)", "a closed session keeps its stored name")
        XCTAssertEqual(store.actionLog(ActionLogQuery(range: .last30), now: now, names: names, limit: 2, offset: 2).count, 2, "paging")
    }

    /// The owner's check: Session = X → Date = Yesterday → open it.
    func test_LAB2048_yesterdaysDecisionForASessionInTwoStepsThenOpen() throws {
        let store = try SessionStore(path: path)
        let cal = Calendar.current
        let yNoon = cal.date(byAdding: .hour, value: 12, to: cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!)!
        var d = ask("b", "npm run build", answered: 0, .always); d.answeredAt = yNoon; d.askedAt = yNoon.addingTimeInterval(-60)
        store.save(d)
        store.save(ask("b", "npm test", answered: 0.1, .allowOnce))
        let rows = store.actionLog(ActionLogQuery(range: .yesterday, sessions: ["b"]), now: now, names: ["b": "Docs"])
        XCTAssertEqual(rows.map(\.id), [d.id])
        XCTAssertEqual(ActionLog.step(from: d.id, by: 1, in: rows), nil)
        XCTAssertTrue(ActionLog.rowAccessibility(rows[0]).contains("Docs, asked Run npm run build, you always allowed"))
    }

    func test_LAB2048_answerKindsAndGlyphs() {
        XCTAssertEqual(ActionLogAnswer.of(ask("a", "x", answered: 1, .allowOnce)), .allowedOnce)
        XCTAssertEqual(ActionLogAnswer.of(ask("a", "x", answered: 1, .always)), .alwaysAllowed)
        XCTAssertEqual(ActionLogAnswer.of(ask("a", "x", answered: 1, .deny)), .denied)
        XCTAssertEqual(ActionLogAnswer.of(ask("a", nil, answered: 1, .reply, reply: "do B")), .replied)
        XCTAssertEqual(ActionLogAnswer.of(ask("a", "x", answered: 1, .allowOnce, reply: "Yes", chosen: "Yes")), .choseOption)
        XCTAssertEqual(ActionLogAnswer.of(ask("a", "x", answered: 1, .reply, reply: "answered in the terminal")), .answeredInTerminal)
        XCTAssertEqual(ActionLogAnswer.of(ask("a", "x", answered: 1, .reply, reply: "set aside")), .setAside)
        XCTAssertEqual(ActionLogAnswer.allowedOnce.glyph, "✓"); XCTAssertEqual(ActionLogAnswer.denied.glyph, "✕"); XCTAssertEqual(ActionLogAnswer.replied.glyph, "↩")
        XCTAssertEqual(ActionLogAnswer.allCases.map(\.title),
                       ["Allowed once", "Always allowed", "Denied", "Replied", "Chose an option", "Answered in the terminal", "Set aside"])
        XCTAssertEqual(ActionLog.answerLine(ask("a", "x", answered: 1, .allowOnce, reply: "Yes", chosen: "Yes")), "Chose: Yes")
        XCTAssertEqual(ActionLog.tabTitle(.decisions, count: 555), "Decisions · 555")
        XCTAssertEqual(ActionLog.tabTitle(.rules, count: 74), "Rules · 74")
    }

    func test_LAB2048_stopNotingARuleAndUndoRestoresTheSameIdAndDate() throws {
        let store = try SessionStore(path: path)
        let made = Date(timeIntervalSince1970: 1_790_000_000)
        let r = DecisionRule(pattern: "swift test", repo: "/p/acme/web", createdAt: made)
        let newer = DecisionRule(pattern: "npm run", repo: "/p/docs", createdAt: made.addingTimeInterval(60))
        store.save(r); store.save(newer)
        XCTAssertEqual(store.decisionRulesNewestFirst().map(\.pattern), ["npm run", "swift test"], "newest first")
        store.deleteRule(id: r.id)
        XCTAssertEqual(store.decisionRules().map(\.id), [newer.id])
        store.save(r)   // Undo
        let back = try XCTUnwrap(store.decisionRules().first { $0.pattern == "swift test" })
        XCTAssertEqual(back.id, r.id)
        XCTAssertEqual(back.createdAt, made)
        XCTAssertEqual(ActionLog.stopRule, "Stop noting this rule")
        XCTAssertTrue(ActionLog.stopped(r).hasPrefix("Stopped noting swift test in "))
        XCTAssertTrue(ActionLog.stopAccessibility(r).hasPrefix("Stop noting this rule: swift test in "))
        XCTAssertTrue(ActionLog.rulesExplainer.contains("only removes One Roof's note"))
    }

    func test_LAB2048_queryRemembersFiltersNotSearchAndChips() throws {
        var q = ActionLogQuery(text: "x", range: .yesterday, sessions: ["b"], answers: [.denied])
        let back = try JSONDecoder().decode(ActionLogQuery.self, from: JSONEncoder().encode(q))
        XCTAssertEqual(back.text, ""); XCTAssertEqual(back.range, .yesterday); XCTAssertEqual(back.sessions, ["b"]); XCTAssertEqual(back.answers, [.denied])
        XCTAssertEqual(q.chips { $0 == "b" ? "Docs" : $0 }.map(\.label), ["Session: Docs", "Answer: Denied", "Date: Yesterday"])
        q.clearFilters()
        XCTAssertFalse(q.isFiltered)
    }
}
