import Foundation
import OneRoofCore

/// LAB-2044 · LAB-2045 · LAB-2046 · LAB-2048 · History and Action log self-tests (with ONEROOF_SELFTEST_DEMO=1):
///   ONEROOF_SELFTEST_HISTORY=<n>          seed this run's store at 1.0 s: one moment of every kind across the demo
///                                         sessions over three days (today, yesterday, the day before), a session that
///                                         was deleted ("Release 1.9.37", closed), answered asks with their options,
///                                         screen lines and chosen option, three always-allow rules; n > 1 adds n more
///                                         generated moments over 30 days (paging and speed, e.g. 20000)
///   ONEROOF_SELFTEST_HISTORYFILTER=<f…>   History's query, as the script's `history` takes it ("kind=errors date=7d
///                                         session=<name> agent=claude text=<words> order=oldest", space-separated)
///   ONEROOF_SELFTEST_HISTORYNEW=<n>       scroll History down, then n new moments arrive (the "N new ↑" pill)
///   ONEROOF_SELFTEST_ACTIONLOG=decisions|rules|open:<i>   open the Action log on that tab (or open the i-th decision)
///   ONEROOF_SELFTEST_ACTIONLOGFILTER=<f…> the Decisions tab's query ("session=<name> date=yesterday answer=denied text=…")
enum SelfTestHistory {
    static func run(_ app: AppDelegate, env: [String: String]) {
        let m = app.model
        if let n = Int(env["ONEROOF_SELFTEST_HISTORY"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { seed(m, extra: n > 1 ? n : 0) }
        }
        if let f = env["ONEROOF_SELFTEST_HISTORYFILTER"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { app.main.win.historyQuery = query(f, base: app.main.win.historyQuery, model: m) }
        }
        if let n = Int(env["ONEROOF_SELFTEST_HISTORYNEW"] ?? "") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                let q = app.main.win.historyQuery
                let list = HistoryLoader.load(m, query: q)
                if list.count > 6 { NotificationCenter.default.post(name: .historySelfTestScroll, object: list[6].id) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                guard let store = m.store, let s = m.items.first(where: { $0.session.name == "Flaky login test" }) else { return }
                for k in 0..<n {
                    store.append(FeedEvent(at: Date().addingTimeInterval(Double(k)), sessionId: s.id, kind: .finding, text: "New finding \(k + 1): the retry hides a race"))
                }
                NotificationCenter.default.post(name: .historyChanged, object: nil)
            }
        }
        if let a = env["ONEROOF_SELFTEST_ACTIONLOG"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if let f = env["ONEROOF_SELFTEST_ACTIONLOGFILTER"] { app.main.win.actionLogQuery = actionLogQuery(f, base: app.main.win.actionLogQuery, model: m) }
                actionLog(a.replacingOccurrences(of: ":", with: " "), app: app) { _ in }
            }
        }
    }

    // MARK: Seed

    static func seed(_ m: AppModel, extra: Int) {
        guard let store = m.store else { return }
        let cal = Calendar.current, now = Date(), today = cal.startOfDay(for: now)
        /// Today: minutes before now (never before midnight); day d ago: hours into that day.
        func at(_ d: Int, _ v: Double) -> Date {
            if d == 0 { return max(today.addingTimeInterval(60 + v), now.addingTimeInterval(-v * 60)) }
            return (cal.date(byAdding: .day, value: -d, to: today) ?? today).addingTimeInterval(v * 3600)
        }
        func sid(_ name: String) -> String? { m.items.first { $0.session.name == name }?.id }
        let flaky = sid("Flaky login test"), help = sid("Help map as a tree"), nightly = sid("Nightly usage export")
        let checkout = sid("Checkout page stickers"), notes = sid("Release notes")
        for i in m.items {
            store.saveHistorySession(HistorySession(id: i.id, name: i.session.name, agent: i.session.agent, account: i.session.account,
                                                    isLoop: SessionScope.isLoop(i.session), firstAt: at(2, 8)))
        }
        // A session that was deleted: only History remembers it.
        let gone = "selftest-closed-release-1937"
        store.saveHistorySession(HistorySession(id: gone, name: "Release 1.9.37", agent: .codex, firstAt: at(1, 9), lastAt: at(1, 11)))
        func feed(_ s: String?, _ k: FeedKind, _ text: String, _ t: Date) { if let s { store.append(FeedEvent(at: t, sessionId: s, kind: k, text: text)) } }
        func event(_ s: String?, _ k: ScrollEntry.Kind, _ text: String, _ t: Date) {
            if let s { store.appendHistory(HistoryEvent(id: HistorySignals.eventId(s, k, text + "\(t.timeIntervalSince1970)"), at: t, sessionId: s, kind: k, text: text)) }
        }
        // Two days ago
        event(nightly, .sessionStarted, "Kimi · acme/api", at(2, 9))
        feed(nightly, .stepDone, "Read the export job and its schedule", at(2, 9.2))
        feed(nightly, .finding, "Deleted accounts are still exported: the filter runs after the join", at(2, 9.5))
        feed(nightly, .done, "Export fixed; 3 tests added", at(2, 10))
        event(nightly, .sessionClosed, "", at(2, 10.2))
        // Yesterday
        event(gone, .sessionStarted, "Codex · labs/oneroof", at(1, 9))
        event(gone, .releaseStarted, "bash ../_common/scripts/release/oneroof-release.sh 1.9.37", at(1, 9.3))
        feed(gone, .error, "notarytool: the upload timed out after 600 s", at(1, 9.8))
        event(gone, .releaseFailed, "oneroof-release.sh 1.9.37 (exit code 1)", at(1, 9.9))
        event(gone, .releaseStarted, "bash ../_common/scripts/release/oneroof-release.sh 1.9.37", at(1, 10.1))
        event(gone, .releaseFinished, "oneroof-release.sh 1.9.37 · 7/7 green", at(1, 10.8))
        event(gone, .handoffWritten, "next-session-handoff/2026-10-31_2241_lab-evals-released.txt", at(1, 10.9))
        event(gone, .sessionClosed, "", at(1, 11))
        feed(help, .choice, "Chose folders first, then pages (as you answered)", at(1, 14))
        feed(help, .subagents, "2 subagents: one per help folder", at(1, 14.2))
        feed(help, .rotated, "Context full: handed off to a fresh session with the plan", at(1, 15))
        // Today
        event(flaky, .sessionStarted, "Claude · acme/web", at(0, 50))
        feed(flaky, .stepDone, "Reproduced the flaky login test: 3 of 20 runs fail", at(0, 44))
        feed(flaky, .error, "LoginTests.testRetry failed: expected 200, got 503", at(0, 40))
        feed(flaky, .finding, "The retry waits 0 ms on the first attempt", at(0, 36))
        feed(checkout, .done, "Stickers on the checkout page, 214 tests pass", at(0, 30))
        // Asks you answered, with their options (LAB-2048)
        let opts = [DecisionChoice(label: "Yes", key: "1"), DecisionChoice(label: "Yes, allow all edits during this session", key: "2"),
                    DecisionChoice(label: "Yes, and don't ask again for swift test commands in acme/web", key: "3"),
                    DecisionChoice(label: "No, and tell Claude what to do differently", key: "4", freeText: true)]
        let screen = [" Bash command", "", "   swift test --filter LoginTests --repeat 20", "", " Do you want to proceed?",
                      " ❯ 1. Yes", "   2. Yes, allow all edits during this session",
                      "   3. Yes, and don't ask again for swift test commands in acme/web", "   4. No, and tell Claude what to do differently (esc)"]
        func ask(_ s: String?, _ name: String, agent: AgentKind, command: String?, why: String, pattern: String, asked: Date, after: Double,
                 answer: Answer, reply: String? = nil, chosen: String? = nil, choices: [DecisionChoice]? = nil, screen: [String]? = nil) {
            guard let s else { return }
            let d = Decision(sessionId: s, agent: agent, kind: command == nil ? .other : .runCommand, command: command, why: why,
                             touches: command == nil ? "Nothing runs until you answer." : "Runs in the session's repo.", risk: .low,
                             ifNo: "The agent stops and asks what to do instead.", where_: "Step 2 of 4", pattern: pattern, repo: "acme/web",
                             askedAt: asked, answeredAt: asked.addingTimeInterval(after), answer: answer, replyText: reply,
                             choices: choices, screen: screen, chosen: chosen)
            store.save(d, sessionName: name)
        }
        ask(flaky, "Flaky login test", agent: .claude, command: "swift test --filter LoginTests --repeat 20", why: "Check the retry fix holds.",
            pattern: "swift test", asked: at(0, 38), after: 40, answer: .allowOnce, reply: "Yes", chosen: "Yes", choices: opts, screen: screen)
        ask(flaky, "Flaky login test", agent: .claude, command: "rm -rf .build", why: "Clean the build folder.", pattern: "rm",
            asked: at(0, 20), after: 25, answer: .deny)
        ask(help, "Help map as a tree", agent: .codex, command: nil, why: "Which order should the help map use?",
            pattern: "ask:Which order should the help map use?", asked: at(1, 13.8), after: 60, answer: .reply,
            reply: "Folders first, then pages", chosen: "Folders first, then pages",
            choices: [DecisionChoice(label: "Folders first, then pages", key: "1"), DecisionChoice(label: "A to Z, folders and pages mixed", key: "2"),
                      DecisionChoice(label: "Type something.", key: "3", freeText: true)],
            screen: ["  Which order should the help map use?", "", "  › 1. Folders first, then pages", "    2. A to Z, folders and pages mixed", "    3. Type something."])
        ask(help, "Help map as a tree", agent: .codex, command: "npm run build", why: "Build the docs site.", pattern: "npm run",
            asked: at(1, 14.5), after: 30, answer: .always)
        ask(nightly, "Nightly usage export", agent: .kimi, command: nil, why: "Should the export include deleted accounts?",
            pattern: Decision.questionPrefix + "Should the export include deleted accounts?", asked: at(2, 9.4), after: 120,
            answer: .reply, reply: "Only the active ones")
        ask(gone, "Release 1.9.37", agent: .codex, command: "xcrun notarytool submit build/OneRoof.zip --wait", why: "Notarise the release.",
            pattern: "xcrun notarytool", asked: at(1, 9.5), after: 15, answer: .allowOnce)
        ask(notes, "Release notes", agent: .gemini, command: "git push origin main", why: "Back up the notes.", pattern: "git push",
            asked: at(2, 15), after: 10, answer: .reply, reply: "answered in the terminal")
        // Rules (LAB-2048 Rules tab)
        store.save(DecisionRule(pattern: "swift test", repo: Workspace.projectsRoot + "/acme/web", createdAt: at(2, 11)))
        store.save(DecisionRule(pattern: "npm run", repo: Workspace.projectsRoot + "/docs-site", createdAt: at(1, 14.6)))
        store.save(DecisionRule(pattern: "git status", repo: Workspace.projectsRoot + "/labs/oneroof", createdAt: at(0, 15)))
        // n more moments over 30 days (paging and speed).
        if extra > 0 {
            let ids = m.items.map(\.id) + [gone]
            let kinds: [FeedKind] = [.stepDone, .finding, .done, .error, .choice]
            for k in 0..<extra {
                let s = ids[k % ids.count]
                store.append(FeedEvent(at: now.addingTimeInterval(-Double(k) * (30 * 86_400 / Double(extra)) - 3600), sessionId: s,
                                       kind: kinds[k % kinds.count], text: "Generated moment \(k): build step \(k % 97) of the nightly job"))
            }
        }
        NotificationCenter.default.post(name: .historyChanged, object: nil)
    }

    // MARK: Queries

    /// "kind=errors date=7d session=<name> agent=claude text=<words> order=oldest" (space-separated; `clear` resets).
    static func query(_ spec: String, base: HistoryQuery, model m: AppModel) -> HistoryQuery {
        var q = base
        for (k, v) in pairs(spec) {
            switch k {
            case "clear": q = HistoryQuery()
            case "kind": q.kinds = Set(v.split(separator: ",").compactMap { HistoryKindGroup(rawValue: String($0)) })
            case "date": q.range = range(v) ?? q.range
            case "session": q.sessions = Set(HistoryLoader.sessions(m).values.filter { $0.name == v }.map(\.id))
            case "agent": q.agents = Set(v.split(separator: ",").compactMap { AgentKind(rawValue: String($0)) })
            case "text": q.text = v
            case "order": q.order = v.hasPrefix("old") ? .oldestFirst : .newestFirst
            default: break
            }
        }
        return q
    }

    static func actionLogQuery(_ spec: String, base: ActionLogQuery, model m: AppModel) -> ActionLogQuery {
        var q = base
        for (k, v) in pairs(spec) {
            switch k {
            case "clear": q = ActionLogQuery()
            case "date": q.range = range(v) ?? q.range
            case "session": q.sessions = Set(HistoryLoader.sessions(m).values.filter { $0.name == v }.map(\.id))
            case "answer": q.answers = Set(v.split(separator: ",").compactMap { ActionLogAnswer(rawValue: String($0)) })
            case "text": q.text = v
            default: break
            }
        }
        return q
    }

    /// `key=value` pairs; a value runs until the next ` key=` (so names may hold spaces).
    static func pairs(_ spec: String) -> [(String, String)] {
        let keys = ["kind", "date", "session", "agent", "text", "order", "answer"]
        if spec.trimmingCharacters(in: .whitespaces) == "clear" { return [("clear", "")] }
        var out: [(String, String)] = []
        var rest = Substring(spec)
        while let eq = rest.firstIndex(of: "=") {
            let key = rest[..<eq].trimmingCharacters(in: .whitespaces)
            var after = rest[rest.index(after: eq)...]
            var end = after.endIndex
            for k in keys { if let r = after.range(of: " " + k + "="), r.lowerBound < end { end = r.lowerBound } }
            out.append((key, String(after[..<end]).trimmingCharacters(in: .whitespaces)))
            after = after[end...]
            rest = after
        }
        return out
    }

    static func range(_ v: String) -> HistoryRange? {
        switch v { case "today": return .today; case "yesterday": return .yesterday; case "7d": return .last7; case "30d": return .last30; default: return nil }
    }

    /// `actionlog decisions|rules [filter…]` · `actionlog open <i>`.
    static func actionLog(_ arg: String, app: AppDelegate, log: (String) -> Void) {
        let parts = arg.split(separator: " ", maxSplits: 1).map(String.init)
        let w = app.main.win
        app.main.v2Page = nil
        switch parts.first {
        case "rules": w.openActionLog(.rules)
        case "open":
            w.openActionLog(.decisions)
            let i = Int(parts.count > 1 ? parts[1] : "0") ?? 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NotificationCenter.default.post(name: .actionLogSelfTest, object: i) }
        default:
            w.openActionLog(.decisions)
            if parts.count > 1 { w.actionLogQuery = actionLogQuery(parts[1], base: w.actionLogQuery, model: app.model) }
        }
        log("  action log: \(w.actionLog?.rawValue ?? "closed") \(w.actionLogQuery)")
    }
}
