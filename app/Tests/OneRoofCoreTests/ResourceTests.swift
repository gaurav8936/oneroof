import XCTest
@testable import OneRoofCore

/// LAB-493: Resources — what One Roof itself costs, per session and overall (synthetic process tables).
final class ResourceTests: XCTestCase {
    let mb = MemoryWatchdog.mb

    /// A process table and readings made up for the test; `tick()` moves the clock 3 s.
    final class FakeSource: ResourceSource {
        var procs: [ProcEntry] = []
        var use: [Int32: RawUsage] = [:]
        var env: [Int32: [String: String]] = [:]
        var clock: UInt64 = 1_000_000_000
        var mem = MacMemory(total: 16 << 30, used: 10 << 30, swapUsed: 1 << 30, pressure: .normal)
        func processes() -> [ProcEntry] { procs }
        func usage(_ pid: Int32) -> RawUsage? { use[pid] }
        func environment(_ pid: Int32) -> [String: String]? { env[pid] }
        func name(_ pid: Int32) -> String? { nil }
        func mac() -> MacMemory? { mem }
        func startTime(_ pid: Int32) -> Date? { Date(timeIntervalSince1970: 1000) }
        func nowNanos() -> UInt64 { clock }
        func tick() { clock += 3_000_000_000 }
    }

    /// app 100 → attach 101 (roofd); daemon 200 → holders 300 (session a) and 400 (session b) and 500 (unclaimed);
    /// 300 → zsh 301 → node 302 → mcp 303; 400 → claude 401; an unrelated process 900.
    func makeSource() -> FakeSource {
        let s = FakeSource()
        s.procs = [
            ProcEntry(pid: 1, ppid: 0, name: "launchd"),
            ProcEntry(pid: 100, ppid: 1, name: "OneRoof"),
            ProcEntry(pid: 101, ppid: 100, name: "roofd"),
            ProcEntry(pid: 200, ppid: 1, name: "roofd"),
            ProcEntry(pid: 300, ppid: 200, name: "roofd"),
            ProcEntry(pid: 301, ppid: 300, name: "zsh"),
            ProcEntry(pid: 302, ppid: 301, name: "node"),
            ProcEntry(pid: 303, ppid: 302, name: "mcp-server"),
            ProcEntry(pid: 400, ppid: 200, name: "roofd"),
            ProcEntry(pid: 401, ppid: 400, name: "claude"),
            ProcEntry(pid: 500, ppid: 200, name: "roofd"),
            ProcEntry(pid: 900, ppid: 1, name: "Safari"),
        ]
        for (pid, m) in [(100, 300), (101, 5), (200, 8), (300, 1200), (301, 2), (302, 400), (303, 50), (400, 30), (401, 500), (500, 20), (900, 4000)] {
            s.use[Int32(pid)] = RawUsage(footprint: UInt64(m) * mb, cpuNanos: 0)
        }
        return s
    }

    func targets() -> ResourceTargets {
        ResourceTargets(appPid: 100, daemonPid: 200, sessions: [
            .init(runtimeId: "a", pid: 301, memoryWarning: true), .init(runtimeId: "b", pid: 401),
        ])
    }

    // MARK: Tree

    func testTreeIsDepthFirstWithDepthsAndStopsAtExcluded() {
        let t = ProcTable(makeSource().procs)
        XCTAssertEqual(t.tree(300).map(\.pid), [300, 301, 302, 303])
        XCTAssertEqual(t.tree(300).map(\.depth), [0, 1, 2, 3])
        XCTAssertEqual(t.tree(200, excluding: [300, 500]).map(\.pid), [200, 400, 401])
        XCTAssertEqual(t.tree(777).count, 0, "a pid that is gone has no tree")
    }

    func testTreeSurvivesACycle() {
        let t = ProcTable([ProcEntry(pid: 5, ppid: 6, name: "a"), ProcEntry(pid: 6, ppid: 5, name: "b")])
        XCTAssertEqual(Set(t.tree(5).map(\.pid)), [5, 6])
    }

    // MARK: CPU

    func testCPUPercentIsDeltaCPUOverDeltaWall() {
        var m = CPUMeter()
        XCTAssertNil(m.percent(pid: 1, cpuNanos: 0, at: 0), "first sample: no delta yet")
        XCTAssertEqual(m.percent(pid: 1, cpuNanos: 1_500_000_000, at: 3_000_000_000)!, 50, accuracy: 0.001)
        XCTAssertEqual(m.percent(pid: 1, cpuNanos: 7_500_000_000, at: 6_000_000_000)!, 200, accuracy: 0.001, "two busy threads")
        XCTAssertEqual(m.percent(pid: 1, cpuNanos: 10, at: 9_000_000_000), 0, "counter went back: a reused pid")
        m.keep([])
        XCTAssertEqual(m.tracked, 0)
    }

    // MARK: Sampler

    func testSessionsMapToTheirHolderTrees() {
        let src = makeSource()
        let snap = ResourceSampler(source: src).sample(targets())
        let a = snap.sessions["a"]!
        XCTAssertEqual(a.holderPid, 300)
        XCTAssertEqual(a.procs.map(\.pid), [300, 301, 302, 303])
        XCTAssertEqual(a.procs.map(\.role), [.holder, .child, .agent, .child])
        XCTAssertEqual(a.footprint, (1200 + 2 + 400 + 50) * mb)
        XCTAssertEqual(a.holderFootprint, 1200 * mb)
        XCTAssertEqual(a.level, .warn, "holder over 1 GB")
        XCTAssertTrue(a.memoryWarning)
        XCTAssertEqual(snap.sessions["b"]?.procs.map(\.pid), [400, 401])
        XCTAssertEqual(snap.sessions["b"]?.level, .ok)
    }

    func testAppDaemonAndUnclaimedAreCountedOnceAndStrangersNever() {
        let snap = ResourceSampler(source: makeSource()).sample(targets())
        XCTAssertEqual(snap.app.map(\.pid), [100, 101])
        XCTAssertEqual(snap.daemon?.pid, 200)
        XCTAssertEqual(snap.unclaimed.map(\.holderPid), [500])
        XCTAssertEqual(snap.processCount, 10, "everything but launchd and Safari")
        XCTAssertEqual(snap.footprint, (300 + 5 + 8 + 1200 + 2 + 400 + 50 + 30 + 500 + 20) * mb)
        XCTAssertNotNil(snap.daemon?.started)
        XCTAssertEqual(snap.mac?.pressure, .normal)
    }

    func testAnAppThatStartedTheDaemonDoesNotCountItTwice() {
        let src = makeSource()
        src.procs = src.procs.map { $0.pid == 200 ? ProcEntry(pid: 200, ppid: 100, name: "roofd") : $0 }
        let snap = ResourceSampler(source: src).sample(targets())
        XCTAssertEqual(snap.app.map(\.pid), [100, 101])
        XCTAssertEqual(snap.processCount, 10)
    }

    func testDaemonFoundFromHoldersWhenHelloDidNotAnswer() {
        var t = targets()
        t.daemonPid = nil
        let snap = ResourceSampler(source: makeSource()).sample(t)
        XCTAssertEqual(snap.daemon?.pid, 200)
    }

    func testCPUAppearsOnTheSecondTick() {
        let src = makeSource()
        let s = ResourceSampler(source: src)
        XCTAssertNil(s.sample(targets()).sessions["b"]?.procs.last?.cpu)
        src.tick()
        src.use[401] = RawUsage(footprint: 500 * mb, cpuNanos: 3_000_000_000)
        let b = s.sample(targets()).sessions["b"]!
        XCTAssertEqual(b.procs.last!.cpu!, 100, accuracy: 0.001)
        XCTAssertEqual(b.cpu, 100, accuracy: 0.001)
    }

    func testUnreadableProcessesAreSkipped() {
        let src = makeSource()
        src.use[302] = nil
        let a = ResourceSampler(source: src).sample(targets()).sessions["a"]!
        XCTAssertEqual(a.procs.map(\.pid), [300, 301, 303])
    }

    func testGoneSessionAndNonRoofdParent() {
        let src = makeSource()
        src.procs.append(ProcEntry(pid: 600, ppid: 1, name: "zsh"))
        src.use[600] = RawUsage(footprint: 3 * mb, cpuNanos: 0)
        let t = ResourceTargets(appPid: 100, daemonPid: 200, sessions: [.init(runtimeId: "gone", pid: 999), .init(runtimeId: "odd", pid: 600)])
        let snap = ResourceSampler(source: src).sample(t)
        XCTAssertNil(snap.sessions["gone"])
        XCTAssertNil(snap.sessions["odd"]?.holderPid, "a parent that is not roofd is not taken for the holder")
        XCTAssertEqual(snap.sessions["odd"]?.footprint, 3 * mb)
        XCTAssertEqual(snap.unclaimed.count, 3, "with no session claiming them, every holder under the daemon is unclaimed")
    }

    func testHolderLimitsComeFromItsEnvironment() {
        let src = makeSource()
        src.env[400] = ["ROOFD_SESSION_MEM_WARN_MB": "20", "ROOFD_SESSION_MEM_LIMIT_MB": "32"]
        let b = ResourceSampler(source: src).sample(targets()).sessions["b"]!
        XCTAssertEqual(b.headroom.warnBytes, 20 * mb)
        XCTAssertEqual(b.headroom.limitBytes, 32 * mb)
        XCTAssertEqual(b.level, .nearLimit, "30 MB of 32 MB")
    }

    // MARK: Headroom

    func testHeadroomLevelsAgainstTheLab310Lines() {
        let h = Headroom.holderDefault
        XCTAssertEqual(h.warnBytes, 1024 * mb)
        XCTAssertEqual(h.limitBytes, 2048 * mb)
        XCTAssertEqual(h.level(500 * mb), .ok)
        XCTAssertEqual(h.level(1024 * mb), .warn)
        XCTAssertEqual(h.level(1900 * mb), .nearLimit)
        XCTAssertEqual(h.fraction(1024 * mb), 0.5, accuracy: 0.001)
        XCTAssertEqual(h.fraction(9000 * mb), 1)
        XCTAssertEqual(h.left(1500 * mb), 548 * mb)
        XCTAssertEqual(h.left(3000 * mb), 0)
        XCTAssertEqual(Headroom.holder(env: nil), .holderDefault)
        XCTAssertEqual(Headroom.daemon(env: [:]).warnBytes, 512 * mb)
    }

    func testPressureLevels() {
        XCTAssertEqual(MacMemory.pressure(level: 1), .normal)
        XCTAssertEqual(MacMemory.pressure(level: 2), .warn)
        XCTAssertEqual(MacMemory.pressure(level: 4), .critical)
        XCTAssertEqual(MacMemory.pressure(level: 0), .normal)
    }

    // MARK: History

    func testRingBufferKeepsTheNewestInOrder() {
        var r = RingBuffer<Int>(capacity: 3)
        XCTAssertNil(r.last)
        for i in 1...5 { r.append(i) }
        XCTAssertEqual(r.values, [3, 4, 5])
        XCTAssertEqual(r.last, 5)
        XCTAssertEqual(r.count, 3)
    }

    func testHistoryIsTenMinutesAndDropsSessionsGoneThatLong() {
        XCTAssertEqual(ResourceHistory.capacity, 200)
        var h = ResourceHistory()
        let t0 = Date(timeIntervalSince1970: 0)
        let u = SessionUsage(runtimeId: "a", holderPid: 1, procs: [ProcUsage(pid: 1, ppid: 0, name: "roofd", depth: 0, role: .holder, footprint: 10, cpu: 1)])
        h.record(ResourceSnapshot(at: t0, sessions: ["a": u]))
        for i in 1...250 { h.record(ResourceSnapshot(at: t0.addingTimeInterval(Double(i) * 3))) }
        XCTAssertEqual(h.points(ResourceHistory.totalKey).count, 200)
        XCTAssertTrue(h.points("a").isEmpty, "gone for over ten minutes")
        h.record(ResourceSnapshot(at: t0.addingTimeInterval(800), sessions: ["b": u]))
        h.record(ResourceSnapshot(at: t0.addingTimeInterval(803)))
        XCTAssertEqual(h.points("b").count, 1, "kept while gone for less than ten minutes")
        XCTAssertEqual(h.points("b").first?.footprint, 10)
    }

    // MARK: Grouping

    func row(_ id: String, _ name: String, _ w: String?, _ m: UInt64, cpu: Double = 0) -> ResourceRow {
        ResourceRow(id: id, name: name, windowId: w, usage: SessionUsage(runtimeId: id, holderPid: 1, procs: [
            ProcUsage(pid: 1, ppid: 0, name: "roofd", depth: 0, role: .holder, footprint: m * mb, cpu: cpu)]))
    }

    func testGroupsByWindowHeaviestFirstWithOtherLast() {
        let rows = [row("1", "alpha", "w1", 100), row("2", "beta", "w1", 900), row("3", "gamma", "w2", 5),
                    row("4", "delta", "closed", 50), row("5", "eps", nil, 60)]
        let g = ResourceBoard.group(rows, windows: [("w1", "Main"), ("w2", "Lab"), ("w3", "Empty")], sort: .heaviest)
        XCTAssertEqual(g.map(\.name), ["Main", "Lab", "Other"], "empty windows are left out; Other is last")
        XCTAssertEqual(g[0].rows.map(\.name), ["beta", "alpha"])
        XCTAssertEqual(g[0].footprint, 1000 * mb)
        XCTAssertEqual(g[2].rows.map(\.name), ["eps", "delta"])
        let byName = ResourceBoard.group(rows, windows: [("w1", "Main")], sort: .name)
        XCTAssertEqual(byName[0].rows.map(\.name), ["alpha", "beta"])
        XCTAssertEqual(byName[1].rows.map(\.name), ["delta", "eps", "gamma"])
    }

    func testTiesBreakOnCPUThenName() {
        let g = ResourceBoard.group([row("1", "b", "w", 10, cpu: 1), row("2", "a", "w", 10, cpu: 1), row("3", "c", "w", 10, cpu: 9)],
                                    windows: [("w", "W")], sort: .heaviest)
        XCTAssertEqual(g[0].rows.map(\.name), ["c", "a", "b"])
    }

    // MARK: Format

    func testFormats() {
        XCTAssertEqual(ResourceFormat.bytes(312 * mb), "312 MB")
        XCTAssertEqual(ResourceFormat.bytes(1434 * mb), "1.4 GB")
        XCTAssertEqual(ResourceFormat.bytes(mb / 2), "0.5 MB")
        XCTAssertEqual(ResourceFormat.bytes(12 * 1024 * mb), "12 GB")
        XCTAssertEqual(ResourceFormat.cpu(nil), "–")
        XCTAssertEqual(ResourceFormat.cpu(0.01), "0%")
        XCTAssertEqual(ResourceFormat.cpu(3.25), "3.2%")
        XCTAssertEqual(ResourceFormat.cpu(112.4), "112%")
        XCTAssertEqual(ResourceFormat.uptime(45), "45s")
        XCTAssertEqual(ResourceFormat.uptime(3 * 3600 + 120), "3h 2m")
        XCTAssertEqual(ResourceFormat.uptime(2 * 86400 + 3600), "2d 1h")
    }

    // MARK: roofd fields

    func testRoofdListCarriesThePidAndMemoryWarning() {
        let s = RoofdRuntime.sessionState(["id": "a", "agent": "claude", "status": "idle", "pid": 4242, "memoryWarning": true])
        XCTAssertEqual(s?.pid, 4242)
        XCTAssertEqual(s?.memoryWarning, true)
        let old = RoofdRuntime.sessionState(["id": "s"])
        XCTAssertNil(old?.pid)
        XCTAssertEqual(old?.memoryWarning, false)
    }

    // MARK: Real process

    /// Samples this test process (read-only rusage) and times the tick.
    func testLiveSampleOfThisProcess() {
        let s = ResourceSampler()
        let me = getpid()
        _ = s.sample(ResourceTargets(appPid: me))
        var worst: UInt64 = 0
        var snap = ResourceSnapshot()
        for _ in 0..<5 {
            snap = s.sample(ResourceTargets(appPid: me))
            worst = max(worst, snap.costNanos)
        }
        XCTAssertEqual(snap.app.first?.pid, me)
        XCTAssertGreaterThan(snap.app.first?.footprint ?? 0, 0)
        XCTAssertNotNil(snap.app.first?.cpu)
        XCTAssertNotNil(snap.app.first?.started)
        let mac = try! XCTUnwrap(snap.mac)
        XCTAssertGreaterThan(mac.total, 0)
        XCTAssertGreaterThan(mac.used, 0)
        print("ResourceSampler tick: \(Double(worst) / 1e6) ms (worst of 5), \(snap.processCount) processes")
        XCTAssertLessThan(worst, 50_000_000, "a tick must stay cheap")
    }
}
