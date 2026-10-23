import XCTest
@testable import OneRoofCore

/// LAB-544: Resources › This Mac, by app (synthetic process tables).
final class MacResourceTests: XCTestCase {
    let mb = MemoryWatchdog.mb
    static let chrome = "/Applications/Google Chrome.app"
    static let helpers = chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Helpers"
    static let oneRoof = "/Applications/One Roof.app"

    final class FakeSource: ResourceSource {
        var procs: [ProcEntry] = []
        var use: [Int32: RawUsage] = [:]
        var paths: [Int32: String] = [:]
        var args: [Int32: [String]] = [:]
        var resp: [Int32: Int32] = [:]
        var clock: UInt64 = 1_000_000_000
        var mem = MacMemory(total: 16 << 30, used: 14 << 30, swapUsed: 18 << 30, pressure: .warn)
        func processes() -> [ProcEntry] { procs }
        func usage(_ pid: Int32) -> RawUsage? { use[pid] }
        func environment(_ pid: Int32) -> [String: String]? { nil }
        func name(_ pid: Int32) -> String? { nil }
        func mac() -> MacMemory? { mem }
        func startTime(_ pid: Int32) -> Date? { nil }
        func nowNanos() -> UInt64 { clock }
        func path(_ pid: Int32) -> String? { paths[pid] }
        func argv(_ pid: Int32) -> [String]? { args[pid] }
        func responsible(_ pid: Int32) -> Int32? { resp[pid] }
    }

    /// One Roof 100 (local model 110 its child); Chrome 200 with renderers 201–203, an extension 204 and GPU 205;
    /// a VM XPC service 301 that OrbStack 300 is responsible for; an orphaned local model 400 and a stray roofd 401;
    /// kernel_task 0-ish system process 500 that cannot be read; WindowServer 600 (system path, readable).
    func makeSource() -> FakeSource {
        let s = FakeSource()
        func add(_ pid: Int32, _ ppid: Int32, _ name: String, _ path: String, _ mbs: UInt64, argv: [String] = [], resp: Int32? = nil) {
            s.procs.append(ProcEntry(pid: pid, ppid: ppid, name: name))
            s.use[pid] = RawUsage(footprint: mbs * mb, cpuNanos: 0)
            s.paths[pid] = path
            if !argv.isEmpty { s.args[pid] = argv }
            if let resp { s.resp[pid] = resp }
        }
        let model = ["/opt/homebrew/bin/llama-server", "-m", "/models/Qwen3-1.7B-Q4_K_M.gguf", "--port", "\(LocalModel.port)"]
        let oldModel = ["/opt/homebrew/bin/llama-server", "-m", "/models/Arch-Router-1.5B-Q4_K_M.gguf", "--port", "\(LocalModel.port)"]
        add(100, 1, "OneRoof", Self.oneRoof + "/Contents/MacOS/OneRoof", 300)
        add(110, 100, "llama-server", "/opt/homebrew/bin/llama-server", 900, argv: model, resp: 100)
        add(200, 1, "Google Chrome", Self.chrome + "/Contents/MacOS/Google Chrome", 400)
        for (pid, m) in [(201, 2000), (202, 1500), (203, 800)] {
            add(Int32(pid), 200, "Google Chrome He", Self.helpers + "/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
                UInt64(m), argv: ["helper", "--type=renderer", "--lang=en-US"], resp: 200)
        }
        add(204, 200, "Google Chrome He", Self.helpers + "/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)", 100,
            argv: ["helper", "--type=renderer", "--extension-process"], resp: 200)
        add(205, 200, "Google Chrome He", Self.helpers + "/Google Chrome Helper (GPU).app/Contents/MacOS/Google Chrome Helper (GPU)", 600,
            argv: ["helper", "--type=gpu-process"], resp: 200)
        add(300, 1, "OrbStack", "/Applications/OrbStack.app/Contents/MacOS/OrbStack", 200)
        add(301, 1, "com.apple.Virtua", "/System/Library/Frameworks/Virtualization.framework/XPCServices/com.apple.Virtualization.VirtualMachine.xpc/Contents/MacOS/VM",
            2600, resp: 300)
        add(400, 1, "llama-server", "/opt/homebrew/bin/llama-server", 8400, argv: oldModel)
        add(401, 1, "roofd", "/Users/someone/oneroof/app/build/roofd", 34)
        s.procs.append(ProcEntry(pid: 500, ppid: 1, name: "kernel_task"))   // no usage: unreadable
        add(600, 1, "WindowServer", "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", 700)
        return s
    }

    func sample(_ s: FakeSource) -> MacBreakdown {
        MacSampler(source: s).sample(appPid: 100, oneRoofPids: [100, 110], regularApps: [100, 200, 300])
    }

    func group(_ b: MacBreakdown, _ name: String) -> MacAppGroup? { b.groups.first { $0.name == name } }

    func testHelpersGroupUnderTheirAppHeaviestFirst() throws {
        let b = sample(makeSource())
        let chrome = try XCTUnwrap(group(b, "Google Chrome"))
        XCTAssertEqual(chrome.procs.count, 6)
        XCTAssertEqual(chrome.footprint, (400 + 2000 + 1500 + 800 + 100 + 600) * mb)
        XCTAssertEqual(chrome.procs.first?.pid, 201, "heaviest process first")
        XCTAssertEqual(b.groups.first?.name, "One Roof", "groups heaviest first: One Roof holds the 8.4 GB leftover model")
    }

    func testHelperKindsFromTheCommandLine() throws {
        let chrome = try XCTUnwrap(group(sample(makeSource()), "Google Chrome"))
        let kinds = Dictionary(chrome.procs.map { ($0.pid, $0.kind ?? "") }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(kinds[201], "Tab or site")
        XCTAssertEqual(kinds[204], "Extension")
        XCTAssertEqual(kinds[205], "GPU")
        XCTAssertEqual(kinds[200], "", "the app itself has no helper kind")
        XCTAssertEqual(MacResources.helperKind(["x", "--type=utility", "--utility-sub-type=network.mojom.NetworkService"]), "Network")
        XCTAssertEqual(MacResources.helperKind(["x", "--type=renderer", "--top-chrome-webui"]), "Browser window (tabs, toolbar)")
        XCTAssertNil(MacResources.helperKind(["/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]))
    }

    func testXPCServiceCountsToTheAppResponsibleForIt() throws {
        let orb = try XCTUnwrap(group(sample(makeSource()), "OrbStack"))
        XCTAssertEqual(Set(orb.procs.map(\.pid)), [300, 301])
        XCTAssertFalse(orb.procs.first { $0.pid == 301 }!.endable, "a system binary is never offered for ending")
    }

    func testOneRoofLeftoversAreFlaggedAndTheLiveModelIsNot() throws {
        let b = sample(makeSource())
        let or = try XCTUnwrap(b.groups.first { $0.isOneRoof })
        XCTAssertEqual(Set(or.procs.map(\.pid)), [100, 110, 400, 401])
        XCTAssertEqual(or.leftovers.map(\.pid), [400, 401], "the orphaned model and the stray roofd; not the app's own model")
        XCTAssertEqual(or.leftovers.first?.kind, "Local model (Arch-Router), left over from an earlier run", "named by its -m file")
        XCTAssertEqual(or.procs.first { $0.pid == 110 }?.kind, "Local model (Qwen3 1.7B)")
        XCTAssertEqual(b.leftovers.reduce(0) { $0 + $1.footprint }, (8400 + 34) * mb)
        XCTAssertTrue(or.leftovers.allSatisfy(\.endable))
        XCTAssertFalse(or.procs.first { $0.pid == 100 }!.endable, "never offers to end itself")
        XCTAssertFalse(or.quittable)
    }

    func testQuitOnlyForDockAppsAndNeverTheSystem() throws {
        let b = sample(makeSource())
        XCTAssertTrue(try XCTUnwrap(group(b, "Google Chrome")).quittable)
        XCTAssertEqual(group(b, "Google Chrome")?.mainPid, 200)
        XCTAssertFalse(try XCTUnwrap(group(b, "WindowServer")).quittable)
        XCTAssertFalse(group(b, "WindowServer")!.procs[0].endable)
        XCTAssertTrue(group(b, "Google Chrome")!.procs.first { $0.pid == 201 }!.endable, "a tab's renderer can be ended")
    }

    func testUnreadableProcessesAreCountedNotListed() {
        let b = sample(makeSource())
        XCTAssertEqual(b.unreadable, 1)
        XCTAssertFalse(b.groups.flatMap(\.procs).contains { $0.pid == 500 })
        XCTAssertEqual(b.processCount, 13)
    }

    func testAppBundleIsTheOutermostApp() {
        XCTAssertEqual(MacResources.appBundle(Self.helpers + "/Google Chrome Helper (GPU).app/Contents/MacOS/x"), Self.chrome)
        XCTAssertEqual(MacResources.appBundle("/Applications/Linear.app"), "/Applications/Linear.app")
        XCTAssertNil(MacResources.appBundle("/opt/homebrew/bin/llama-server"))
        XCTAssertEqual(MacResources.appName(Self.chrome), "Google Chrome")
    }

    func testLocalModelIsLlamaServerOnOneRoofsPortOnly() {
        XCTAssertTrue(MacResources.isLocalModel(name: "llama-server", argv: ["llama-server", "--port", "\(LocalModel.port)"]))
        XCTAssertFalse(MacResources.isLocalModel(name: "llama-server", argv: ["llama-server", "--port", "8080"]))
        XCTAssertFalse(MacResources.isLocalModel(name: "node", argv: ["node", "--port", "\(LocalModel.port)"]))
    }

    func testCPUAfterTheSecondSample() throws {
        let s = makeSource()
        let sampler = MacSampler(source: s)
        _ = sampler.sample(appPid: 100)
        s.clock += 3_000_000_000
        s.use[201]!.cpuNanos = 1_500_000_000
        let b = sampler.sample(appPid: 100)
        let p = try XCTUnwrap(b.groups.flatMap(\.procs).first { $0.pid == 201 })
        XCTAssertEqual(p.cpu ?? -1, 50, accuracy: 0.01)
    }
}
