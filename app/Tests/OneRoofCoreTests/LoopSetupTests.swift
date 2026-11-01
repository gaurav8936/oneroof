import XCTest
@testable import OneRoofCore

/// LAB-2099 (a loop's `journal:runs/…` outcome opens its report) and LAB-2100 (a kit loop with nothing configured says
/// "not configured", not pass). Fixture config text only: the live kit config and loops are never read here.
final class LoopSetupTests: XCTestCase {
    static let config = """
    version: 1
    journal:
      root: ~/work/shared/journal   # where run reports go
      commit: false
    loops:
      scheduler: launchd
      enabled:
      - fleet-sweep
      - cost-watch
      settings:
        cost-watch:
          limits:
            anthropic: 20
          usd_per_mtok: {}
        morning-health:
          commands:
          - name: learn-check
            run: bash scripts/check.sh
        site-prober:
          commands: []
        visual-diff:
          commands:
            - name: pricing
              run: compare pricing
      project: EXAMPLE-LOOPS
    tracker:
      adapter: linear
    """

    // MARK: LAB-2099

    func test_LAB2099_journalLinkIsItsOwnTarget() {
        let t = LoopLedger.LinkTarget("journal:runs/2026/11/2026-11-01_cost-watch_r-1.md")
        XCTAssertEqual(t, .journal("runs/2026/11/2026-11-01_cost-watch_r-1.md"), "2.0.0 read it as an issue key and opened nothing")
        XCTAssertEqual(LoopLedger.LinkTarget("LAB-1"), .key("LAB-1"))
        XCTAssertEqual(LoopLedger.LinkTarget("/tmp/x.md"), .file("/tmp/x.md"))
    }

    func test_LAB2099_journalRootFromConfigThenSharedThenHome() {
        let roots = AEConfig.journalRoots(config: Self.config, home: "/Users/someone", shared: "/Users/someone/shared")
        XCTAssertEqual(roots, ["/Users/someone/work/shared/journal", "/Users/someone/shared/journal", "/Users/someone/.ae/journal"])
        XCTAssertEqual(AEConfig.journalRoots(config: nil, home: "/Users/someone", shared: "/s"), ["/s/journal", "/Users/someone/.ae/journal"])
    }

    func test_LAB2099_resolveJournalPicksTheRootThatHasTheFile() {
        let roots = ["/a/journal", "/b/journal"]
        let rel = "runs/2026/11/r.md"
        XCTAssertEqual(AEConfig.resolveJournal(rel, roots: roots) { $0 == "/b/journal/runs/2026/11/r.md" }, "/b/journal/runs/2026/11/r.md")
        XCTAssertEqual(AEConfig.resolveJournal(rel, roots: roots) { _ in false }, "/a/journal/runs/2026/11/r.md", "missing: the first root (Finder shows its folder)")
        XCTAssertNil(AEConfig.resolveJournal("../../etc/passwd", roots: roots) { _ in true }, "never outside the journal")
        XCTAssertNil(AEConfig.resolveJournal("", roots: roots) { _ in true })
    }

    func test_LAB2099_resolveJournalOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lab2099-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir + "/journal/runs/2026/11", withIntermediateDirectories: true)
        try "# Cost watch · run".write(toFile: dir + "/journal/runs/2026/11/r.md", atomically: true, encoding: .utf8)
        let cfg = "journal:\n  root: \(dir)/journal\n"
        let p = AEConfig.resolveJournal("runs/2026/11/r.md", roots: AEConfig.journalRoots(config: cfg, home: "/nowhere", shared: "/nowhere"))
        XCTAssertEqual(p, dir + "/journal/runs/2026/11/r.md")
    }

    func test_LAB2099_configCandidatesFollowTheKit() {
        let c = AEConfig.candidates(environment: ["AE_CONFIG": "~/x.yaml"], home: "/Users/someone", projects: "/p", shared: "/s")
        XCTAssertEqual(c, ["/Users/someone/x.yaml", "/p/ae.config.yaml", "/s/ae.config.yaml", "/Users/someone/.config/ae/config.yaml"])
    }

    // MARK: Reading the config

    func test_LAB2100_nodeReader() {
        XCTAssertEqual(AEConfig.node(["journal", "root"], in: Self.config)?.inline, "~/work/shared/journal", "comment stripped")
        XCTAssertEqual(AEConfig.node(["loops", "settings", "cost-watch", "limits"], in: Self.config)?.isSet, true)
        XCTAssertEqual(AEConfig.node(["loops", "settings", "cost-watch", "usd_per_mtok"], in: Self.config)?.isSet, false, "{} is empty")
        XCTAssertEqual(AEConfig.node(["loops", "settings", "morning-health", "commands"], in: Self.config)?.isSet, true, "a list at the key's indent")
        XCTAssertEqual(AEConfig.node(["loops", "settings", "site-prober", "commands"], in: Self.config)?.isSet, false, "[] is empty")
        XCTAssertEqual(AEConfig.node(["loops", "settings", "visual-diff", "commands"], in: Self.config)?.isSet, true)
        XCTAssertNil(AEConfig.node(["loops", "settings", "fleet-sweep", "commands"], in: Self.config))
        XCTAssertNil(AEConfig.node(["loops", "project", "x"], in: Self.config))
        XCTAssertEqual(AEConfig.node(["loops", "project"], in: Self.config)?.inline, "EXAMPLE-LOOPS", "a key after a nested block")
        XCTAssertNil(AEConfig.node(["settings"], in: Self.config), "only at the top level, not nested")
    }

    // MARK: LAB-2100

    func test_LAB2100_unconfiguredLoopsAreNamed() {
        let none: (String) -> Bool = { _ in false }
        guard case .notConfigured(let fs)? = LoopSetup.status(loop: "fleet-sweep", config: Self.config, toolInstalled: none) else { return XCTFail() }
        XCTAssertTrue(fs[0].contains("loops.settings.fleet-sweep.commands"))
        if case .notConfigured? = LoopSetup.status(loop: "site-prober", config: Self.config, toolInstalled: none) {} else { XCTFail("[] is not configured") }
        XCTAssertEqual(LoopSetup.status(loop: "visual-diff", config: Self.config, toolInstalled: none), .ready)
        guard case .notConfigured(let cw)? = LoopSetup.status(loop: "cost-watch", config: Self.config, toolInstalled: none) else { return XCTFail() }
        XCTAssertEqual(cw.count, 1, "limits are set; the price table is not")
        XCTAssertTrue(cw[0].contains("usd_per_mtok"))
        guard case .notConfigured(let sa)? = LoopSetup.status(loop: "security-audit", config: Self.config, toolInstalled: none) else { return XCTFail() }
        XCTAssertTrue(sa[0].contains("osv-scanner"))
        XCTAssertEqual(LoopSetup.status(loop: "security-audit", config: nil, toolInstalled: { $0 == "osv-scanner" }), .ready)
        XCTAssertNil(LoopSetup.status(loop: "docs-drift", config: Self.config, toolInstalled: none), "no known needs: the card is unchanged")
        if case .notConfigured(let all)? = LoopSetup.status(loop: "cost-watch", config: nil, toolInstalled: none) { XCTAssertEqual(all.count, 2) } else { XCTFail() }
    }

    func test_LAB2100_cardSaysNotConfiguredInsteadOfPass() {
        XCTAssertEqual(LoopSetup.cardResult("pass ×2", status: .notConfigured(["x"])), "not configured")
        XCTAssertEqual(LoopSetup.cardResult("dry · Nov 1", status: .notConfigured(["x"])), "not configured")
        XCTAssertEqual(LoopSetup.cardResult("pass ×2", status: .ready), "pass ×2")
        XCTAssertEqual(LoopSetup.cardResult("Never run", status: nil), "Never run")
    }

    func test_LAB2100_snippetsAndToolLookup() throws {
        for id in ["fleet-sweep", "site-prober", "visual-diff", "cost-watch", "security-audit"] {
            XCTAssertNotNil(LoopSetup.snippet(id), id)
            XCTAssertFalse(LoopSetup.needs(id).isEmpty, id)
        }
        XCTAssertTrue(LoopSetup.snippet("fleet-sweep")!.contains("fleet-sweep:\n      commands:"))
        // A fleet-sweep snippet pasted under settings makes it configured.
        let pasted = "loops:\n  settings:\n" + LoopSetup.snippet("fleet-sweep")!.components(separatedBy: "\n").dropFirst(2).joined(separator: "\n")
        XCTAssertEqual(LoopSetup.status(loop: "fleet-sweep", config: pasted, toolInstalled: { _ in false }), .ready)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lab2100-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        XCTAssertFalse(LoopSetup.installed("osv-scanner", dirs: [dir]))
        FileManager.default.createFile(atPath: dir + "/osv-scanner", contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        XCTAssertTrue(LoopSetup.installed("osv-scanner", dirs: [dir]))
        XCTAssertTrue(LoopSetup.toolDirs(environment: ["PATH": "/x:/y"], home: "/Users/someone").starts(with: ["/x", "/y"]))
    }
}
