import XCTest
@testable import OneRoofCore

/// LAB-2312: the Resources page's numbers add up. Rows show memory in RAM (resident), so rows + "other" = the Mac's
/// "in use" (the footprints they showed before summed past RAM); the header and One Roof's row are one set of processes
/// with one CPU reading; one row per app name (Chrome's code-sign clone); the footer reads roofd's real lines.
/// Synthetic process tables only: nothing here reads or touches roofd or a session.
final class ResourceNumbersTests: XCTestCase {
    let mb = MemoryWatchdog.mb
    typealias FakeSource = MacResourceTests.FakeSource
    static let oneRoof = "/Applications/One Roof.app"
    static let chrome = "/Applications/Google Chrome.app"
    static let clone = "/private/var/folders/xy/abc/X/com.google.Chrome.code_sign_clone/code_sign_clone.Q1w2e3/Google Chrome.app"

    /// `footprint` and `resident` in MB.
    func add(_ s: FakeSource, _ pid: Int32, _ ppid: Int32, _ name: String, _ path: String, footprint: UInt64, resident: UInt64,
             cpu: UInt64 = 0, resp: Int32? = nil) {
        s.procs.append(ProcEntry(pid: pid, ppid: ppid, name: name))
        s.use[pid] = RawUsage(footprint: footprint * mb, cpuNanos: cpu, resident: resident * mb)
        s.paths[pid] = path
        if let resp { s.resp[pid] = resp }
    }

    /// Like the ticket's Mac: 13 GB in use of 16, 9.2 GB of swap; Chrome's footprint 9.8 GB but 4 GB in RAM, ChatGPT
    /// 3.2 GB footprint / 1.2 GB in RAM, One Roof 4.4 GB / 1.7 GB.
    func ticketMac() -> FakeSource {
        let s = FakeSource()
        s.mem = MacMemory(total: 16 << 30, used: 13 << 30, swapUsed: UInt64(9.2 * 1024) * mb, pressure: .warn)
        add(s, 100, 1, "OneRoof", Self.oneRoof + "/Contents/MacOS/OneRoof", footprint: 1500, resident: 600)
        add(s, 110, 100, "llama-server", "/opt/homebrew/bin/llama-server", footprint: 2900, resident: 1100, resp: 100)
        add(s, 200, 1, "Google Chrome", Self.chrome + "/Contents/MacOS/Google Chrome", footprint: 1800, resident: 800)
        add(s, 201, 200, "Google Chrome He", Self.chrome + "/Contents/Frameworks/x/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/h",
            footprint: 8000, resident: 3200, resp: 200)
        add(s, 300, 1, "ChatGPT", "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", footprint: 3200, resident: 1200)
        return s
    }

    func testRowsPlusOtherAddUpToInUse() throws {
        let b = MacSampler(source: ticketMac()).sample(appPid: 100, regularApps: [100, 200, 300])
        let used = try XCTUnwrap(b.mac?.used)
        let rows = b.groups.reduce(UInt64(0)) { $0 + $1.resident }
        XCTAssertEqual(b.counted, rows)
        XCTAssertEqual(rows, (600 + 1100 + 800 + 3200 + 1200) * mb, "rows show memory in RAM")
        // The margin: rows + other within 1 MB of in use (exact here; the live page differs only by rounding).
        XCTAssertLessThanOrEqual(Int64(rows + b.uncounted) - Int64(used), Int64(mb))
        XCTAssertGreaterThanOrEqual(Int64(rows + b.uncounted) - Int64(used), -Int64(mb))
        XCTAssertEqual(b.overcounted, 0)
        // Before LAB-2312 the rows were footprints: 17.4 GB of rows on a Mac with 13 GB in use and "other" clamped to 0.
        let footprints = b.groups.reduce(UInt64(0)) { $0 + $1.footprint }
        XCTAssertGreaterThan(footprints, used, "the old rows passed RAM")
        XCTAssertEqual(b.notResident, footprints - rows, "what is not in RAM is its own figure")
        XCTAssertEqual(try XCTUnwrap(b.groups.first { $0.name == "Google Chrome" }).notResident, (1000 + 4800) * mb)
    }

    func testRowsThatPassInUseSayByHowMuch() {
        let s = ticketMac()
        s.mem.used = 6 << 30
        let b = MacSampler(source: s).sample(appPid: 100)
        XCTAssertEqual(b.uncounted, 0)
        XCTAssertEqual(b.overcounted, b.counted - (6 << 30), "shown, not hidden behind a zero")
    }

    // MARK: One membership, one CPU meter

    /// One Roof 100 → its local model 110; daemon 200 → holder 300 → zsh 301 (a path outside any bundle and
    /// "responsible" to a terminal app, so the Mac list used to file it elsewhere); a WebKit XPC service 150 macOS holds
    /// One Roof responsible for (not in One Roof's tree); Chrome 400.
    func oneRoofMac() -> FakeSource {
        let s = FakeSource()
        s.mem = MacMemory(total: 16 << 30, used: 8 << 30, swapUsed: 0, pressure: .normal)
        let roofd = Self.oneRoof + "/Contents/Helpers/roofd"
        add(s, 100, 1, "OneRoof", Self.oneRoof + "/Contents/MacOS/OneRoof", footprint: 900, resident: 500)
        add(s, 110, 100, "llama-server", "/opt/homebrew/bin/llama-server", footprint: 2000, resident: 700, resp: 100)
        add(s, 150, 1, "com.apple.WebKit", "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
            footprint: 120, resident: 90, resp: 100)
        add(s, 200, 1, "roofd", roofd, footprint: 8, resident: 12)
        add(s, 300, 200, "roofd", roofd, footprint: 7, resident: 14)
        add(s, 301, 300, "zsh", "/bin/zsh", footprint: 5, resident: 6, resp: 999)
        add(s, 400, 1, "Google Chrome", Self.chrome + "/Contents/MacOS/Google Chrome", footprint: 1000, resident: 600)
        add(s, 999, 1, "Terminal", "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", footprint: 80, resident: 60)
        return s
    }

    func testHeaderEqualsOneRoofsRow() throws {
        let s = oneRoofMac()
        let res = ResourceSampler(source: s), macs = MacSampler(source: s)
        let targets = ResourceTargets(appPid: 100, daemonPid: 200, sessions: [.init(runtimeId: "a", pid: 301)])
        func tick() -> (ResourceSnapshot, MacBreakdown) {
            let snap = res.sample(targets)
            let known = Dictionary(snap.allProcs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
            return (snap, macs.sample(appPid: 100, known: known, regularApps: [100, 400]))
        }
        _ = tick()
        s.clock += 3_000_000_000
        s.use[100]!.cpuNanos = 600_000_000      // 20 % of one core
        s.use[110]!.cpuNanos = 1_500_000_000    // 50 %
        s.use[150]!.cpuNanos = 120_000_000      // 4 %, only the Mac list reads it
        let (snap, mac) = tick()
        let row = try XCTUnwrap(mac.oneRoof)
        XCTAssertTrue(Set(snap.allProcs.map(\.pid)).isSubset(of: Set(row.procs.map(\.pid))),
                      "every process the header counts is in One Roof's row (zsh 301 too, whatever its path)")
        XCTAssertEqual(Set(row.procs.map(\.pid)), [100, 110, 150, 200, 300, 301])
        XCTAssertNil(mac.groups.first { $0.name == "Terminal" }?.procs.first { $0.pid == 301 })
        let header = OneRoofTotals.of(snap, mac: mac)
        XCTAssertEqual(header.memory, row.resident)
        XCTAssertEqual(header.processes, row.procs.count)
        XCTAssertEqual(header.cpu, row.cpu, accuracy: 1e-9)
        XCTAssertEqual(header.cpu, 74, accuracy: 0.01, "one reading per process: 20 + 50 + 4")
        for p in snap.allProcs {
            let m = try XCTUnwrap(row.procs.first { $0.pid == p.pid })
            XCTAssertEqual(m.cpu, p.cpu, "pid \(p.pid): the Mac list takes the snapshot's CPU reading, not its own")
            XCTAssertEqual(m.resident, p.resident)
        }
        // Without the whole-Mac sample the header falls back to One Roof's own tree.
        let own = OneRoofTotals.of(snap, mac: nil)
        XCTAssertEqual(own.memory, snap.resident)
        XCTAssertEqual(own.processes, 5)
    }

    func testCPUMeterDropsAReadingAcrossAPause() {
        var m = CPUMeter(maxWindowNanos: CPUMeter.window)
        XCTAssertNil(m.percent(pid: 1, cpuNanos: 0, at: 0))
        XCTAssertEqual(m.percent(pid: 1, cpuNanos: 1_500_000_000, at: 3_000_000_000)!, 50, accuracy: 0.001)
        XCTAssertNil(m.percent(pid: 1, cpuNanos: 61_500_000_000, at: 603_000_000_000), "10 minutes since the last tick: not a reading of now")
        XCTAssertEqual(m.percent(pid: 1, cpuNanos: 62_100_000_000, at: 606_000_000_000)!, 20, accuracy: 0.001, "the next tick reads again")
        XCTAssertEqual(ResourceFormat.cpuUnit, "% of one core")
    }

    // MARK: One row per app name

    func testChromesCodeSignCloneIsOneRowWithChrome() throws {
        let s = FakeSource()
        add(s, 200, 1, "Google Chrome", Self.chrome + "/Contents/MacOS/Google Chrome", footprint: 900, resident: 800)
        add(s, 201, 200, "Google Chrome He", Self.clone + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/h",
            footprint: 500, resident: 400)
        add(s, 202, 200, "Google Chrome He", Self.chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers/Google Chrome Helper (GPU).app/Contents/MacOS/h",
            footprint: 300, resident: 250, resp: 200)
        let b = MacSampler(source: s).sample(appPid: 1, regularApps: [200])
        let chromes = b.groups.filter { $0.name == "Google Chrome" }
        XCTAssertEqual(chromes.count, 1, "one row per app name")
        let c = try XCTUnwrap(chromes.first)
        XCTAssertEqual(c.id, Self.chrome, "kept under the installed copy")
        XCTAssertEqual(c.bundlePath, Self.chrome)
        XCTAssertEqual(c.mainPid, 200)
        XCTAssertEqual(Set(c.procs.map(\.pid)), [200, 201, 202])
        XCTAssertEqual(c.resident, (800 + 400 + 250) * mb)
        XCTAssertTrue(c.quittable)
        XCTAssertTrue(MacResources.isClone(Self.clone))
        XCTAssertFalse(MacResources.isClone(Self.chrome))
    }

    // MARK: Footer

    func testFooterReadsRoofdsLines() {
        let d = ResourceFormat.guardNote(holder: .holderDefault, daemon: .daemonDefault)
        XCTAssertTrue(d.contains("the daemon warns at \(ResourceFormat.bytes(MemoryWatchdog.daemonWarnMB * mb))"), d)
        XCTAssertTrue(d.contains("512 MB"), "MemoryWatchdog.daemonWarnMB today: \(d)")
        XCTAssertTrue(d.contains("passes \(ResourceFormat.bytes(MemoryWatchdog.holderWarnMB * mb)) and ends the session at \(ResourceFormat.bytes(MemoryWatchdog.holderLimitMB * mb))"), d)
        // A holder and a daemon started with other lines: the footer says those.
        var snap = ResourceSnapshot(daemonHeadroom: .daemon(env: ["ROOFD_DAEMON_MEM_WARN_MB": "256"]))
        snap.sessions["a"] = SessionUsage(runtimeId: "a", holderPid: 300, procs: [], headroom: .holder(env: ["ROOFD_SESSION_MEM_WARN_MB": "768", "ROOFD_SESSION_MEM_LIMIT_MB": "1536"]))
        let n = ResourceFormat.guardNote(snap)
        XCTAssertTrue(n.contains("passes 768 MB and ends the session at 1.5 GB"), n)
        XCTAssertTrue(n.contains("the daemon warns at 256 MB"), n)
        XCTAssertTrue(ResourceFormat.guardNote(ResourceSnapshot()).contains("passes 1.0 GB"), "no session: the defaults")
    }

    // MARK: Session gauge vs session total

    func testSessionTotalIsTheWholeSessionAndTheGaugeTheHolder() {
        let u = SessionUsage(runtimeId: "a", holderPid: 300, procs: [
            ProcUsage(pid: 300, ppid: 200, name: "roofd", depth: 0, role: .holder, footprint: 6 * mb, cpu: nil, resident: 14 * mb),
            ProcUsage(pid: 301, ppid: 300, name: "node", depth: 1, role: .agent, footprint: 600 * mb, cpu: nil, resident: 420 * mb),
        ])
        XCTAssertEqual(u.holderFootprint, 6 * mb, "the gauge: the holder alone, by footprint (what the limit checks)")
        XCTAssertEqual(u.resident, 434 * mb, "the total: every process of the session, in RAM")
    }

    // MARK: This Mac now (read-only, opt-in)

    /// ONEROOF_LAB2312_LIVE=1 swift test --filter ResourceNumbersTests/testPrintThisMac prints what the page adds up on
    /// this Mac. It only reads process stats (proc_pid_rusage, host_statistics64); it never talks to roofd or a session.
    func testPrintThisMac() throws {
        guard ProcessInfo.processInfo.environment["ONEROOF_LAB2312_LIVE"] == "1" else { throw XCTSkip("set ONEROOF_LAB2312_LIVE=1") }
        let macs = MacSampler(source: LiveResourceSource())
        _ = macs.sample()
        Thread.sleep(forTimeInterval: 3)
        let b = macs.sample()
        let m = try XCTUnwrap(b.mac)
        func f(_ x: UInt64) -> String { ResourceFormat.bytes(x) }
        var out = "This Mac: \(f(m.used)) of \(f(m.total)) in use, swap \(f(m.swapUsed))\n"
        out += "rows in RAM \(f(b.counted)) + other \(f(b.uncounted)) (over by \(f(b.overcounted))) · rows by footprint (before) \(f(b.groups.reduce(0) { $0 + $1.footprint }))\n"
        for g in b.groups.prefix(8) {
            out += "  \(g.name): \(f(g.resident)) in RAM (footprint \(f(g.footprint))) · \(ResourceFormat.cpu(g.cpu)) · \(g.procs.count) processes\n"
        }
        let dup = Dictionary(grouping: b.groups, by: \.name).filter { $0.value.count > 1 }.keys
        out += "names with two rows: \(dup.isEmpty ? "none" : dup.joined(separator: ", "))"
        print(out)
        XCTAssertTrue(dup.isEmpty)
    }
}
