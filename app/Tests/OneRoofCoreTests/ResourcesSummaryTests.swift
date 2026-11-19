import XCTest
@testable import OneRoofCore

/// LAB-2313 · Resources, summary first (owner option A): the Sessions and Needs action tiles, the swap line shared with
/// Home, which cards start open (Other opening by itself), and the names of roofd sessions no One Roof row owns.
final class ResourcesSummaryTests: XCTestCase {
    let mb = MemoryWatchdog.mb

    func usage(_ rid: String, holderMB: UInt64, agentMB: UInt64 = 100, cpu: Double = 1, holder: Bool = true, warned: Bool = false,
               started: Date? = nil) -> SessionUsage {
        var procs: [ProcUsage] = []
        if holder {
            procs.append(ProcUsage(pid: 10, ppid: 1, name: "roofd", depth: 0, role: .holder, footprint: holderMB * mb, cpu: 0, started: started))
        }
        procs.append(ProcUsage(pid: 11, ppid: 10, name: "claude", depth: 1, role: .agent, footprint: agentMB * mb, cpu: cpu))
        return SessionUsage(runtimeId: rid, holderPid: holder ? 10 : nil, procs: procs, memoryWarning: warned)
    }

    /// Evals (this window) with two One Roof rows; Other with a closed window's row and two roofd sessions no row owns.
    func board() -> (groups: [ResourceWindowGroup], status: [String: SessionStatus]) {
        let rows = [
            ResourceRow(id: "a", name: "Bug fixes", windowId: "w1", usage: usage("roof-aaaa1111", holderMB: 64)),
            ResourceRow(id: "b", name: "Rebranding", windowId: "w1", usage: usage("roof-bbbb2222", holderMB: 41)),
            ResourceRow(id: "c", name: "Old window's row", windowId: nil, usage: usage("roof-cccc3333", holderMB: 20)),
            ResourceRow(id: "runtime:roof-dddd4444", name: "roof-dddd4444", windowId: nil, usage: usage("roof-dddd4444", holderMB: 33)),
            ResourceRow(id: "runtime:roof-eeee5555", name: "roof-eeee5555", windowId: nil, usage: usage("roof-eeee5555", holderMB: 4)),
        ]
        let groups = ResourceBoard.group(rows, windows: [("w1", "Evals"), ("w2", "TEMP")], sort: .heaviest)
        return (groups, ["a": .running, "b": .done, "c": .idle])
    }

    func test_LAB2313_sessionsTileCountsStatesWindowsAndOrphans() {
        let (groups, status) = board()
        let s = ResourcesSummary.make(groups, status: { status[$0.id] })
        XCTAssertEqual(s.running, 5)
        XCTAssertEqual(s.windows, 1)   // TEMP has no running sessions (hidden, as today); Other is not a window
        XCTAssertEqual(s.states, [.init(status: .running, count: 1), .init(status: .done, count: 1), .init(status: .idle, count: 1)])
        XCTAssertEqual(s.notOneRoofRow, 2)
        XCTAssertEqual(s.windowsLine, "Evals 2 · Other 3")
        XCTAssertEqual(s.otherCount, 3)
        XCTAssertEqual(s.otherMemory, groups.last!.footprint)
    }

    func test_LAB2313_statePillsFollowThePaletteOrder() {
        let rows = ["x": SessionStatus.exited, "n": .needsYou, "i": .idle, "r": .done, "w": .running, "w2": .running].map { id, _ in
            ResourceRow(id: id, name: id, windowId: "w1", usage: usage("roof-\(id)", holderMB: 10))
        }
        let status: [String: SessionStatus] = ["x": .exited, "n": .needsYou, "i": .idle, "r": .done, "w": .running, "w2": .running]
        let s = ResourcesSummary.make(ResourceBoard.group(rows, windows: [("w1", "Main")], sort: .name), status: { status[$0.id] })
        XCTAssertEqual(s.states.map(\.status), [.running, .done, .idle, .needsYou, .exited])
        XCTAssertEqual(s.states.first?.count, 2)
        XCTAssertEqual(s.notOneRoofRow, 0)
    }

    func test_LAB2313_needsActionOnlyWhenSomethingDoes() {
        // Nothing in Other, every holder under its warning line: no tile.
        let calm = [ResourceRow(id: "a", name: "A", windowId: "w1", usage: usage("roof-a", holderMB: 64))]
        let s0 = ResourcesSummary.make(ResourceBoard.group(calm, windows: [("w1", "Evals")], sort: .heaviest), status: { _ in .idle })
        XCTAssertFalse(s0.needsAction)
        XCTAssertNil(s0.nearest)
        XCTAssertEqual(s0.atWarn, 0)

        // Sessions no window owns: the tile, with their count and memory.
        let (groups, status) = board()
        let s1 = ResourcesSummary.make(groups, status: { status[$0.id] })
        XCTAssertTrue(s1.needsAction)
        XCTAssertNil(s1.nearest)

        // Only a holder past its warning line (1 GB by default): the tile names the one nearest its limit.
        let hot = [ResourceRow(id: "a", name: "Warm", windowId: "w1", usage: usage("roof-a", holderMB: 1_100)),
                   ResourceRow(id: "b", name: "Hot", windowId: "w1", usage: usage("roof-b", holderMB: 1_900)),
                   ResourceRow(id: "c", name: "Flagged", windowId: "w1", usage: usage("roof-c", holderMB: 200, warned: true)),
                   ResourceRow(id: "d", name: "No holder", windowId: "w1", usage: usage("roof-d", holderMB: 0, agentMB: 3_000, holder: false))]
        let s2 = ResourcesSummary.make(ResourceBoard.group(hot, windows: [("w1", "Evals")], sort: .heaviest), status: { _ in .running })
        XCTAssertTrue(s2.needsAction)
        XCTAssertEqual(s2.otherCount, 0)
        XCTAssertEqual(s2.atWarn, 3)   // roofd's flag counts; a session with no holder has no limit
        XCTAssertEqual(s2.nearest, .init(name: "Hot", holder: 1_900 * mb, limit: 2_048 * mb, level: .nearLimit))
    }

    func test_LAB2313_swapTurnsAmberAboveHomesLine() {
        func mac(_ swap: UInt64) -> MacMemory { MacMemory(total: 16 << 30, used: 8 << 30, swapUsed: swap, pressure: .normal) }
        XCTAssertEqual(MacMemory.heavySwapBytes, 4 << 30)
        XCTAssertFalse(mac(0).heavySwap)
        XCTAssertFalse(mac(4 << 30).heavySwap)        // at the line: not yet
        XCTAssertTrue(mac((4 << 30) + 1).heavySwap)
        XCTAssertTrue(mac(UInt64(8.5 * 1024) * mb).heavySwap)

        // Home's MAC story uses the same line: a normal-pressure Mac over it gets the swap story, under it none.
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 9))!
        func macStory(_ swap: UInt64) -> HomeFrontPage.Story? {
            var i = HomeFrontPage.Inputs(now: now)
            i.mac = mac(swap)
            let p = HomeFrontPage.build(i, calendar: cal)
            return ([p.lead] + p.side).first { $0.kicker == "MAC" }
        }
        XCTAssertEqual(macStory((4 << 30) + 1)?.headline, "The Mac is using a lot of swap")
        XCTAssertNil(macStory(4 << 30))
    }

    func test_LAB2313_foldDefaultsAndKeys() {
        XCTAssertTrue(ResourcesFold.startsOpen(.window("w1"), thisWindow: "w1"))
        XCTAssertFalse(ResourcesFold.startsOpen(.window("w2"), thisWindow: "w1"))
        XCTAssertTrue(ResourcesFold.startsOpen(.other, thisWindow: "w1"))
        XCTAssertFalse(ResourcesFold.startsOpen(.mac, thisWindow: "w1"))
        XCTAssertFalse(ResourcesFold.startsOpen(.own, thisWindow: "w1"))
        // The owner's choice wins either way.
        XCTAssertFalse(ResourcesFold.isOpen(.window("w1"), stored: false, thisWindow: "w1"))
        XCTAssertTrue(ResourcesFold.isOpen(.mac, stored: true, thisWindow: "w1"))
        XCTAssertTrue(ResourcesFold.isOpen(.other, stored: nil, thisWindow: nil))
        // Kept next to resources.browserTabs.*, one per card.
        XCTAssertEqual(ResourcesFold.key(.mac), "resources.fold.mac")
        XCTAssertEqual(ResourcesFold.key(.own), "resources.fold.own")
        XCTAssertEqual(ResourcesFold.key(.other), "resources.fold.other")
        XCTAssertEqual(ResourcesFold.key(.window("ABC")), "resources.fold.window.ABC")
        XCTAssertEqual(Set([ResourcesFold.Card.mac, .own, .other, .window("a"), .window("b")].map(ResourcesFold.key)).count, 5)
    }

    func test_LAB2313_otherOpensByItselfForANewRow() {
        XCTAssertFalse(ResourcesFold.reopensOther(seen: ["runtime:a", "runtime:b"], now: ["runtime:a", "runtime:b"]))
        XCTAssertFalse(ResourcesFold.reopensOther(seen: ["runtime:a", "runtime:b"], now: ["runtime:a"]))   // one left: stays folded
        XCTAssertTrue(ResourcesFold.reopensOther(seen: ["runtime:a"], now: ["runtime:a", "runtime:c"]))
        XCTAssertTrue(ResourcesFold.reopensOther(seen: [], now: ["runtime:a"]))   // folded while empty, then a row comes
    }

    func test_LAB2313_foldedHeaderVoiceOver() {
        XCTAssertEqual(ResourcesFold.label("Other", open: false, summary: "3 sessions no window owns"), "Other, folded, 3 sessions no window owns")
        XCTAssertEqual(ResourcesFold.label("Evals", open: true, summary: "2 running sessions"), "Evals, opened, 2 running sessions")
        XCTAssertEqual(ResourcesFold.label("One Roof itself", open: true, summary: ""), "One Roof itself, opened")
    }

    func test_LAB2313_orphanNamesFromWhatRoofdSays() {
        let home = "/Users/you"
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-15e2b579-2", isAgent: true, agentName: "claude", cwd: home + "/Projects", title: "zsh", home: home),
                       "roof-15e2b579-2 · Claude in ~/Projects")
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-15e2b579", isAgent: false, agentName: nil, cwd: home + "/Projects", title: nil, home: home),
                       "roof-15e2b579 · shell in ~/Projects")
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-1", isAgent: true, agentName: "kimi-code", cwd: "/tmp/x", title: nil, home: home),
                       "roof-1 · Kimi in /tmp/x")
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-1", isAgent: true, agentName: "mystery", cwd: home, title: nil, home: home),
                       "roof-1 · Mystery in ~")
        // Unknown parts are left out, never guessed.
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-1", isAgent: nil, agentName: nil, cwd: home + "/a", title: nil, home: home), "roof-1 · ~/a")
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-1", isAgent: true, agentName: "codex", cwd: nil, title: nil, home: home), "roof-1 · Codex")
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-1", isAgent: nil, agentName: nil, cwd: nil, title: "Nightly export", home: home),
                       "roof-1 · Nightly export")
        XCTAssertEqual(ResourceOrphanName.name(runtimeId: "roof-1", isAgent: nil, agentName: nil, cwd: "", title: nil, home: home), "roof-1")
        XCTAssertEqual(ResourceOrphanName.folder("/Users/someone/a", home: home), "/Users/someone/a")   // not under home
        XCTAssertEqual(ResourceOrphanName.folder(home + "/a/b", home: home + "/"), "~/a/b")
    }

    func test_LAB2313_orphanSublineAgeAndReplacement() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rows = [
            ResourceRow(id: "row1", name: "Evals work", windowId: "w1", usage: usage("roof-d758af41-2", holderMB: 50)),
            ResourceRow(id: "runtime:roof-d758af41", name: "roof-d758af41", windowId: nil, usage: usage("roof-d758af41", holderMB: 33)),
            ResourceRow(id: "runtime:roof-15e2b579", name: "roof-15e2b579", windowId: nil, usage: usage("roof-15e2b579", holderMB: 4)),
            // A later session of the same name that is itself not a One Roof row does not count as the replacement.
            ResourceRow(id: "runtime:roof-15e2b579-2", name: "roof-15e2b579-2", windowId: nil, usage: usage("roof-15e2b579-2", holderMB: 38)),
        ]
        let names = ["w1": "Evals"]
        let windowName: (String?) -> String? = { id in id.flatMap { names[$0] } ?? "Other" }
        XCTAssertEqual(ResourceOrphanName.replacement(of: "roof-d758af41", rows: rows, windowName: windowName), "relaunched as -2 (Evals)")
        XCTAssertNil(ResourceOrphanName.replacement(of: "roof-15e2b579", rows: rows, windowName: windowName))
        // An earlier generation never "replaces" a later one.
        let newer = [ResourceRow(id: "row", name: "R", windowId: "w1", usage: usage("roof-aa", holderMB: 1))]
        XCTAssertNil(ResourceOrphanName.replacement(of: "roof-aa-3", rows: newer, windowName: windowName))
        // The latest one wins; a row in no window says Other; a custom owner rule (self-test rows) is honoured.
        let many = [ResourceRow(id: "runtime:roof-bb-2", name: "x", windowId: nil, usage: usage("roof-bb-2", holderMB: 1)),
                    ResourceRow(id: "runtime:roof-bb-3", name: "y", windowId: nil, usage: usage("roof-bb-3", holderMB: 1))]
        XCTAssertEqual(ResourceOrphanName.replacement(of: "roof-bb", rows: many, owned: { _ in true }, windowName: windowName), "relaunched as -3 (Other)")

        let started = now.addingTimeInterval(-(2 * 86400 + 4 * 3600))
        XCTAssertEqual(ResourceOrphanName.subline(started: started, now: now, replacedBy: "relaunched as -2 (Evals)"),
                       ["not a One Roof row", "relaunched as -2 (Evals)", "up 2d 4h"])
        XCTAssertEqual(ResourceOrphanName.subline(started: nil, now: now, replacedBy: nil), ["not a One Roof row"])
    }
}
