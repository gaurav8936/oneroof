import XCTest
@testable import OneRoofCore

/// LAB-2044 · LAB-2045 · LAB-2046 · History: the place, kinds and their look, the query (search, sort, filters, dates),
/// the store (30 days, closed sessions kept, handover events, indexes), paging and speed.
final class HistoryQueryTests: XCTestCase {
    var path = ""
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }()
    /// Sat 31 Oct 2026, 15:00 UTC.
    let now = Date(timeIntervalSince1970: 1_793_458_800)

    override func setUp() { path = NSTemporaryDirectory() + "oneroof-history-\(UUID().uuidString).sqlite" }
    override func tearDown() { for ext in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + ext) } }

    private func entry(_ id: String, _ session: String, _ kind: ScrollEntry.Kind, _ text: String, hoursAgo: Double, answer: String? = nil, open: Bool = false) -> ScrollEntry {
        ScrollEntry(id: id, at: now.addingTimeInterval(-hoursAgo * 3600), sessionId: session, kind: kind, text: text,
                    decisionId: answer == nil && !open ? nil : UUID(), open: open, answer: answer)
    }

    private let sessions: [String: HistorySession] = [
        "a": HistorySession(id: "a", name: "oneroof-1937", agent: .claude),
        "b": HistorySession(id: "b", name: "Docs", agent: .codex),
        "c": HistorySession(id: "c", name: "Nightly export", agent: .kimi),
    ]

    private var sample: [ScrollEntry] {
        [entry("1", "a", .error, "build failed", hoursAgo: 1),
         entry("2", "a", .ask, "Run swift test", hoursAgo: 2, answer: "Allowed once"),
         entry("3", "b", .finding, "the index is stale", hoursAgo: 20),            // yesterday (19:00 the day before)
         entry("4", "b", .error, "lint failed", hoursAgo: 26),                      // yesterday
         entry("5", "c", .done, "export done", hoursAgo: 24 * 5),
         entry("6", "c", .sessionStarted, "Kimi · acme/api", hoursAgo: 24 * 10),   // outside 7 days
         entry("7", "a", .question, "Which branch?", hoursAgo: 0.5, open: true)]
    }

    // MARK: LAB-2044 the place

    func test_LAB2044_historyIsAPlaceUnderTheInboxWithCtrlCmd9() {
        // LAB-2114: History moved to the bottom of the rail (was right under the Inbox); its key stays ⌃⌘9.
        XCTAssertEqual(Place.allCases, [.home, .needsYou, .sessions, .work, .machine, .loops, .learn, .evals, .history])
        XCTAssertEqual(Place.history.title, "History")
        XCTAssertEqual(Place.history.symbol, "clock.arrow.circlepath")
        XCTAssertEqual(Place.history.controlKey, "9")
        let old: [Place: Character] = [.home: "1", .needsYou: "2", .sessions: "3", .work: "4", .machine: "5", .loops: "6", .learn: "7", .evals: "8"]
        for (p, k) in old { XCTAssertEqual(p.controlKey, k, "\(p) keeps ⌃⌘\(k)") }
        XCTAssertEqual(Set(Place.allCases.map(\.controlKey)).count, Place.allCases.count, "no two places share a key")
        XCTAssertEqual(Place.history.defaultStep, .full)
    }

    func test_LAB2044_aShortcutSavedUnderScrollReachesHistory() {
        let carried = MenuRenames.carry(["Scroll": "⌃⌥⌘S"])
        XCTAssertEqual(carried["History"], "⌃⌥⌘S")
    }

    func test_LAB2044_subtitleEmptyAndPill() {
        XCTAssertEqual(HistoryFormat.subtitle(sessions: 6, moments: 128, order: .newestFirst), "6 sessions · 128 moments · newest first")
        XCTAssertEqual(HistoryFormat.subtitle(sessions: 1, moments: 1, order: .oldestFirst), "1 session · 1 moment · oldest first")
        XCTAssertEqual(HistoryFormat.newPill(3), "3 new ↑")
        XCTAssertEqual(HistoryFormat.closedName("Release 1.9.37"), "Release 1.9.37 (closed)")
    }

    func test_LAB2044_anOpenAskReadsWaitingInTheInbox() {
        let e = entry("7", "a", .question, "Which branch?", hoursAgo: 0.5, open: true)
        XCTAssertTrue(e.needsInput)
        XCTAssertTrue(HistoryFormat.accessibility(e, session: "oneroof-1937").hasSuffix("Waiting in the Inbox"))
        XCTAssertTrue(HistoryFormat.accessibility(e, session: "oneroof-1937").contains(", Question, oneroof-1937: Which branch?"),
                      "VoiceOver reads the word, not the glyph")
    }

    // MARK: LAB-2045 kinds and their look

    func test_LAB2045_everyKindHasItsOwnGlyphWordAndTreatment() {
        let all = ScrollEntry.Kind.allCases
        XCTAssertEqual(Set(all.map(\.style.word)).count, all.count, "every kind has its own word")
        for k in all { XCTAssertFalse(k.style.glyph.isEmpty, "\(k) has a glyph") }
        XCTAssertEqual(ScrollEntry.Kind.error.style.treatment, .errorFill)
        XCTAssertEqual(ScrollEntry.Kind.error.style.colour, .errorText)
        for k in [ScrollEntry.Kind.ask, .question, .finished] { XCTAssertEqual(k.style.treatment, .bar(.accent), "\(k)") }
        XCTAssertEqual(ScrollEntry.Kind.done.style.colour, .done)
        XCTAssertEqual(ScrollEntry.Kind.finding.style.colour, .now)
        for k in all where k.isHandover { XCTAssertEqual(k.style.treatment, .divider, "\(k) is a divider row") }
        XCTAssertEqual(all.filter(\.isHandover).count, 7, "started, closed, handed off, handoff written, release started / finished / failed")
        XCTAssertEqual(ScrollEntry.Kind.rotated.style.word, "Handed off")
        XCTAssertEqual(ScrollEntry.Kind.answerStyle.word, "You")
        // The (glyph, colour, treatment) look of each non-divider kind differs from the others where it matters most:
        let looks = [ScrollEntry.Kind.error, .ask, .done, .finding, .step].map { "\($0.style.colour)\($0.style.treatment)" }
        XCTAssertEqual(Set(looks).count, looks.count)
    }

    // MARK: LAB-2046 dates

    func test_LAB2046_everyLineShowsDateAndTime() {
        let d = Date(timeIntervalSince1970: 1_793_488_000)   // Sat 31 Oct 2026 23:06:40 UTC
        let utc = TimeZone(identifier: "UTC")!
        let s = HistoryFormat.stamp(d, locale: Locale(identifier: "en_GB"), timeZone: utc)
        XCTAssertEqual(s, "Sat 31 Oct · 23:06")
        XCTAssertTrue(HistoryFormat.full(d, locale: Locale(identifier: "en_GB"), timeZone: utc).contains("23:06:40"), "the tooltip has seconds")
        XCTAssertEqual(HistoryFormat.dayHeader(d, now: d, calendar: cal), "Today")
        XCTAssertEqual(HistoryFormat.dayHeader(d.addingTimeInterval(-86_400), now: d, calendar: cal), "Yesterday")
        XCTAssertNotEqual(HistoryFormat.dayHeader(d.addingTimeInterval(-3 * 86_400), now: d, calendar: cal), "Yesterday")
    }

    func test_LAB2046_rangesAreInclusiveDays() {
        let today = cal.startOfDay(for: now)
        XCTAssertEqual(HistoryRange.today.bounds(now: now, calendar: cal).from, today)
        XCTAssertEqual(HistoryRange.yesterday.bounds(now: now, calendar: cal).to, today)
        XCTAssertTrue(HistoryRange.last7.contains(today.addingTimeInterval(-6 * 86_400), now: now, calendar: cal))
        XCTAssertFalse(HistoryRange.last7.contains(today.addingTimeInterval(-6 * 86_400 - 1), now: now, calendar: cal))
        let from = today.addingTimeInterval(-2 * 86_400 + 5000), to = today.addingTimeInterval(-86_400 + 100)
        let c = HistoryRange.custom(from: to, to: from)   // either order
        XCTAssertTrue(c.contains(today.addingTimeInterval(-2 * 86_400), now: now, calendar: cal), "from day included from midnight")
        XCTAssertTrue(c.contains(today.addingTimeInterval(-1), now: now, calendar: cal), "to day included to midnight")
        XCTAssertFalse(c.contains(today, now: now, calendar: cal))
        XCTAssertTrue(HistoryRange.last7.isDefault)
    }

    // MARK: LAB-2046 the query

    func test_LAB2046_defaultIsLast7DaysNewestFirst() {
        let r = HistoryQuery().apply(sample, session: { self.sessions[$0] }, now: now, calendar: cal)
        XCTAssertEqual(r.map(\.id), ["7", "1", "2", "3", "4", "5"], "newest first, 10-day-old moment out")
        let o = HistoryQuery(order: .oldestFirst).apply(sample, session: { self.sessions[$0] }, now: now, calendar: cal)
        XCTAssertEqual(o.map(\.id), r.map(\.id).reversed())
    }

    func test_LAB2046_eachFilterAloneAndTogether() {
        func ids(_ q: HistoryQuery) -> [String] { q.apply(sample, session: { self.sessions[$0] }, now: now, calendar: cal).map(\.id) }
        XCTAssertEqual(ids(HistoryQuery(sessions: ["b"])), ["3", "4"])
        XCTAssertEqual(ids(HistoryQuery(agents: [.kimi])), ["5"])
        XCTAssertEqual(ids(HistoryQuery(kinds: [.errors])), ["1", "4"], "every error this week: one step (7 days is the default)")
        XCTAssertEqual(ids(HistoryQuery(kinds: [.asks])), ["7", "2"])
        XCTAssertEqual(ids(HistoryQuery(kinds: [.answers])), ["2"])
        XCTAssertEqual(ids(HistoryQuery(kinds: [.handovers], range: .last30)), ["6"])
        XCTAssertEqual(ids(HistoryQuery(range: .yesterday)), ["3", "4"])
        XCTAssertEqual(ids(HistoryQuery(sessions: ["b"], range: .yesterday)), ["3", "4"], "everything session X did yesterday: two steps")
        XCTAssertEqual(ids(HistoryQuery(sessions: ["b"], kinds: [.errors], range: .yesterday)), ["4"])
        XCTAssertEqual(ids(HistoryQuery(text: "STALE")), ["3"], "search matches text")
        XCTAssertEqual(ids(HistoryQuery(text: "docs")), ["3", "4"], "search matches the session name")
        XCTAssertEqual(ids(HistoryQuery(text: "allowed once")), ["2"], "search matches your answer")
        XCTAssertEqual(ids(HistoryQuery(text: "failed", kinds: [.errors], range: .today)), ["1"])
    }

    func test_LAB2046_chipsAndClearAll() {
        var q = HistoryQuery(sessions: ["a"], kinds: [.errors], range: .yesterday)
        let chips = q.chips { self.sessions[$0]?.name ?? $0 }
        XCTAssertEqual(chips.map(\.label), ["Session: oneroof-1937", "Kind: Errors", "Date: Yesterday"])
        q.remove(chips[1].remove)
        XCTAssertTrue(q.kinds.isEmpty)
        XCTAssertTrue(q.isFiltered)
        q.clearFilters()
        XCTAssertFalse(q.isFiltered)
        XCTAssertEqual(q.range, .last7)
    }

    func test_LAB2046_filtersAndSortAreRememberedButNotTheSearch() throws {
        let q = HistoryQuery(text: "secret", sessions: ["a"], agents: [.codex], kinds: [.errors], range: .last30, order: .oldestFirst)
        let back = try JSONDecoder().decode(HistoryQuery.self, from: JSONEncoder().encode(q))
        XCTAssertEqual(back.sessions, ["a"]); XCTAssertEqual(back.agents, [.codex]); XCTAssertEqual(back.kinds, [.errors])
        XCTAssertEqual(back.range, .last30); XCTAssertEqual(back.order, .oldestFirst)
        XCTAssertEqual(back.text, "", "the search text is not remembered")
        let custom = HistoryQuery(range: .custom(from: now, to: now))
        XCTAssertEqual(try JSONDecoder().decode(HistoryQuery.self, from: JSONEncoder().encode(custom)).range, custom.range)
    }

    func test_LAB2046_resultLine() {
        XCTAssertEqual(HistoryFormat.resultLine(moments: 128, sessions: 6), "128 moments · 6 sessions")
        XCTAssertEqual(HistoryFormat.resultLine(moments: 1, sessions: 1), "1 moment · 1 session")
        XCTAssertEqual(HistoryFormat.resultLine(moments: 0, sessions: 0), "No moments match.")
    }

    func test_LAB2046_daysAndSessionGroups() {
        let r = HistoryQuery().apply(sample, session: { self.sessions[$0] }, now: now, calendar: cal)
        let days = HistoryPaging.days(r, calendar: cal)
        XCTAssertEqual(days.count, 3, "today, yesterday, five days ago")
        XCTAssertEqual(days[0].groups.map(\.sessionId), ["a"], "a run of one session's moments is one card")
        XCTAssertEqual(days[0].groups[0].entries.map(\.id), ["7", "1", "2"])
        XCTAssertEqual(days[1].groups.map(\.sessionId), ["b"])
    }

    func test_LAB2105_linesOpenAndCloseEachCard() {
        let r = HistoryQuery().apply(sample, session: { self.sessions[$0] }, now: now, calendar: cal)
        let days = HistoryPaging.days(r, calendar: cal), lines = HistoryPaging.rows(days)
        XCTAssertEqual(lines.count, days.count)
        for (d, l) in zip(days, lines) {
            XCTAssertEqual(l.rows.count, d.groups.reduce(0) { $0 + 1 + $1.entries.count }, "one line per card header and per moment")
            XCTAssertEqual(l.rows.filter(\.closesCard).count, d.groups.count, "every card is closed once")
            XCTAssertEqual(l.rows.filter(\.closesDay).count, 1)
            XCTAssertTrue(l.rows.last?.closesDay ?? false)
            XCTAssertTrue(l.rows.first?.firstInDay ?? false)
            if case .head = l.rows.first?.part {} else { XCTFail("a day starts with a card header") }
        }
        XCTAssertEqual(lines[0].rows.dropFirst().map(\.id), ["7", "1", "2"], "moments keep their ids (scroll targets)")
    }

    func test_LAB2105_stampsMatchAfterCaching() {
        let d = Date(timeIntervalSince1970: 1_761_980_000), en = Locale(identifier: "en_GB"), utc = TimeZone(identifier: "UTC")!
        let first = HistoryFormat.stamp(d, locale: en, timeZone: utc)
        XCTAssertEqual(HistoryFormat.stamp(d, locale: en, timeZone: utc), first)
        XCTAssertNotEqual(HistoryFormat.stamp(d, locale: en, timeZone: TimeZone(identifier: "Asia/Kolkata")!), first, "the time zone is part of the cache key")
    }

    // MARK: LAB-2046 handover signals

    func test_LAB2046_handoffsAndReleasesFromToolCalls() {
        let text = """
        ⏺ Write(/Users/someone/work/next-steps/2026-10-31_handoff.txt)
          ⎿  Wrote 40 lines
        ⏺ Bash(bash ../_common/scripts/release/oneroof-release.sh 1.9.37)
          ⎿  Error: Exit code 1
             notarytool timed out
        ⏺ Bash(bash scripts/ci/cicd-trace.sh --repo oneroof all "ship")
          ⎿  7/7 green
        ⏺ Read(README.md)
        ⏺ Bash(ship-domain labs)
        """
        let s = HistorySignals.scan(text, finished: false)
        XCTAssertEqual(s.handoffs.count, 1)
        XCTAssertEqual(s.releases.map(\.ok), [false, true, nil], "failed, finished ok, still running")
        XCTAssertEqual(HistorySignals.scan(text, finished: true).releases.last?.ok, true, "the turn ended: it finished")
        XCTAssertEqual(HistorySignals.eventId("s", .releaseStarted, "x"), HistorySignals.eventId("s", .releaseStarted, "x"), "stable ids")
        XCTAssertNotEqual(HistorySignals.eventId("s", .releaseStarted, "x"), HistorySignals.eventId("s", .releaseFinished, "x"))
    }

    // MARK: LAB-2046 store: closed sessions, loop rounds, 30 days, indexes, speed

    func test_LAB2046_storeKeepsClosedSessionsAndLeavesLoopRoundsOut() throws {
        let store = try SessionStore(path: path)
        store.saveHistorySession(HistorySession(id: "gone", name: "Release 1.9.37", agent: .codex, firstAt: now.addingTimeInterval(-7200)))
        store.saveHistorySession(HistorySession(id: "loop", name: "nightly · round 1", agent: .claude, isLoop: true))
        store.saveHistorySession(HistorySession(id: "gone", name: "Release 1.9.37 (renamed)", agent: .codex, lastAt: now))
        let hs = store.historySessions()
        XCTAssertEqual(hs["gone"]?.name, "Release 1.9.37 (renamed)", "renames are written")
        XCTAssertEqual(hs["gone"]?.firstAt, now.addingTimeInterval(-7200), "the first time seen is kept")
        XCTAssertEqual(hs["gone"]?.lastAt, now)
        store.append(FeedEvent(at: now.addingTimeInterval(-60), sessionId: "gone", kind: .error, text: "notarytool timed out"))
        store.append(FeedEvent(at: now.addingTimeInterval(-60), sessionId: "loop", kind: .done, text: "round done"))
        XCTAssertTrue(store.appendHistory(HistoryEvent(id: "h1", at: now.addingTimeInterval(-30), sessionId: "gone", kind: .sessionClosed, text: "")))
        XCTAssertFalse(store.appendHistory(HistoryEvent(id: "h1", at: now, sessionId: "gone", kind: .sessionClosed, text: "")), "once only")
        let d = Decision(sessionId: "gone", agent: .codex, kind: .runCommand, command: "xcrun notarytool", why: "w", touches: "t", risk: .low,
                         ifNo: "n", pattern: "xcrun", repo: "r", askedAt: now.addingTimeInterval(-90), answeredAt: now.addingTimeInterval(-80), answer: .allowOnce)
        store.save(d, sessionName: "Release 1.9.37")
        let e = store.historyEntries(from: now.addingTimeInterval(-86_400), to: now.addingTimeInterval(1)) { hs[$0]?.isLoop }
        XCTAssertEqual(e.map(\.kind), [.ask, .error, .sessionClosed], "a deleted session's moments stay")
        XCTAssertFalse(e.contains { $0.sessionId == "loop" }, "loop rounds stay in Loops (LAB-1933)")
        XCTAssertEqual(e.first?.answer, "Allowed once")
    }

    func test_LAB2046_retentionIs30Days() throws {
        let store = try SessionStore(path: path)
        store.append(FeedEvent(at: now.addingTimeInterval(-29 * 86_400), sessionId: "s", kind: .done, text: "kept"))
        store.append(FeedEvent(at: now.addingTimeInterval(-31 * 86_400), sessionId: "s", kind: .done, text: "pruned"))
        store.appendHistory(HistoryEvent(id: "old", at: now.addingTimeInterval(-31 * 86_400), sessionId: "s", kind: .sessionStarted, text: ""))
        store.appendHistory(HistoryEvent(id: "new", at: now.addingTimeInterval(-86_400), sessionId: "s", kind: .sessionStarted, text: ""))
        let old = Decision(sessionId: "s", agent: .claude, kind: .runCommand, why: "w", touches: "t", risk: .low, ifNo: "n", pattern: "p", repo: "r",
                           askedAt: now.addingTimeInterval(-90 * 86_400), answeredAt: now.addingTimeInterval(-90 * 86_400), answer: .deny)
        store.save(old)
        store.pruneFeed(now: now)
        XCTAssertEqual(HistoryFeed.retentionDays, 30)
        XCTAssertEqual(store.recentFeed().map(\.text), ["kept"])
        XCTAssertEqual(store.historyEvents(from: .distantPast, to: .distantFuture).map(\.id), ["new"])
        XCTAssertNotNil(store.decision(id: old.id), "decisions are kept forever (the action log)")
    }

    func test_LAB2046_indexesAndColumnsAreAddedIdempotently() throws {
        do { _ = try SessionStore(path: path) }
        let store = try SessionStore(path: path)   // second open: nothing fails, nothing doubles
        XCTAssertTrue(store.indexNames("feed").contains("feed_at"))
        XCTAssertTrue(store.indexNames("decisions").isSuperset(of: ["decisions_asked", "decisions_answered"]))
        XCTAssertTrue(store.indexNames("chapters").contains("chapters_ended"))
        XCTAssertTrue(store.indexNames("history_events").contains("history_events_at"))
        XCTAssertTrue(store.columnNames("decisions").isSuperset(of: ["choices_json", "screen_json", "chosen", "session_name"]))
        XCTAssertEqual(store.schemaVersion, SessionStore.migrations.count, "no version bump: an older One Roof still opens the store")
    }

    /// 20 000 moments: the first page and a search, measured against a generous bound (the real numbers are logged).
    func test_LAB2046_twentyThousandMomentsAreFast() throws {
        let store = try SessionStore(path: path)
        try store.exec("BEGIN")
        for k in 0..<20_000 {
            store.append(FeedEvent(at: now.addingTimeInterval(-Double(k) * 120), sessionId: "s\(k % 40)",
                                   kind: [.stepDone, .finding, .done, .error][k % 4], text: "moment \(k) of the nightly build"))
        }
        try store.exec("COMMIT")
        let names = Dictionary(uniqueKeysWithValues: (0..<40).map { ("s\($0)", HistorySession(id: "s\($0)", name: "Session \($0)", agent: .claude)) })
        var t = Date()
        let b = HistoryRange.last30.bounds(now: now, calendar: cal)
        let all = store.historyEntries(from: b.from, to: b.to) { names[$0]?.isLoop }
        let page = Array(HistoryQuery(range: .last30).apply(all, session: { names[$0] }, now: now, calendar: cal).prefix(HistoryPaging.pageSize))
        let first = Date().timeIntervalSince(t)
        t = Date()
        let found = HistoryQuery(text: "moment 1999", range: .last30).apply(all, session: { names[$0] }, now: now, calendar: cal)
        let search = Date().timeIntervalSince(t)
        print("LAB-2046 perf: \(all.count) moments · first page \(Int(first * 1000)) ms · search \(Int(search * 1000)) ms")
        XCTAssertEqual(all.count, 20_000)
        XCTAssertEqual(page.count, 500)
        XCTAssertEqual(found.count, 11, "moment 1999 and 19990…19999")
        XCTAssertLessThan(first, 1.0, "first page (debug build; the target is < 100 ms on a release build)")
        XCTAssertLessThan(search, 1.0, "search (debug build; the target is < 150 ms)")
    }
}
