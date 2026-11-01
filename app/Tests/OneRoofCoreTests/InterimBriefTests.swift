import XCTest
@testable import OneRoofCore

/// LAB-1971 · OpenCode and Goose have no session-start hook: One Roof asks the kit for the interim brief at launch and
/// puts it before the opening message; nothing changes when the kit prints nothing or fails.
final class InterimBriefTests: XCTestCase {
    func test_onlyHostedAgentsNeedIt() {
        XCTAssertTrue(InterimBrief.needsOpeningBrief(.opencode))
        XCTAssertTrue(InterimBrief.needsOpeningBrief(.goose))
        XCTAssertFalse(InterimBrief.needsOpeningBrief(.claude))
    }

    func test_emptyBrief_keepsTheOpening() {
        XCTAssertEqual(InterimBrief.opening(brief: "  \n", opening: "Fix LAB-1"), "Fix LAB-1")
        XCTAssertNil(InterimBrief.opening(brief: "", opening: nil))
    }

    func test_briefGoesFirst() {
        let o = InterimBrief.opening(brief: "INTERIM BRIEF (automatic, 14:02): …", opening: "Fix LAB-1")!
        XCTAssertTrue(o.hasPrefix("INTERIM BRIEF"))
        XCTAssertTrue(o.hasSuffix("Fix LAB-1"))
    }

    func test_briefAlone_tellsTheAgentToWait() {
        XCTAssertTrue(InterimBrief.opening(brief: "INTERIM BRIEF", opening: nil)!.contains("wait for the owner"))
    }

    func test_fetch_runsTheKitCommand_andIgnoresFailures() throws {
        let kit = FileManager.default.temporaryDirectory.appendingPathComponent("ib-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: kit.appendingPathComponent("ae"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: kit.appendingPathComponent("ae/handoff.py").path, contents: Data())
        let r = HostedRuntimeConfiguration(pythonExecutable: "/bin/sh", kitDirectory: kit.path, nativeExecutables: [:], storageDirectory: "/tmp")
        var seen: [String] = []
        let ok = InterimBrief.fetch(runtime: r, cwd: "/tmp") { _, args, _, env in
            seen = args; XCTAssertEqual(env["PYTHONPATH"], kit.path); return (0, "INTERIM BRIEF x") }
        XCTAssertEqual(ok, "INTERIM BRIEF x")
        XCTAssertEqual(seen, ["-m", "ae.handoff", "interim", "--if-active", "--budget", "3"])
        XCTAssertEqual(InterimBrief.fetch(runtime: r, cwd: "/tmp") { _, _, _, _ in (1, "boom") }, "")
        let noKit = HostedRuntimeConfiguration(pythonExecutable: "/bin/sh", kitDirectory: "/nonexistent", nativeExecutables: [:], storageDirectory: "/tmp")
        XCTAssertEqual(InterimBrief.fetch(runtime: noKit, cwd: "/tmp") { _, _, _, _ in (0, "x") }, "")
    }
}
