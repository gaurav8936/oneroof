import XCTest
@testable import OneRoofCore

/// LAB-1917 (the outcome ledger roofd shares with the kit) and LAB-1848 (one alert when a loop stops on a limit).
final class LoopLedgerTests: XCTestCase {
    func tmp() -> String {
        let d = NSTemporaryDirectory() + "loopledger-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    func testRunsAndOutcomesAndSummary() throws {
        let led = try LoopLedger(path: tmp() + "/ledger.sqlite")
        let t0 = Date(timeIntervalSince1970: 1_761_904_800)
        try led.recordRun(loop: "nightly", runId: "a1", started: t0, ended: t0 + 60, result: "failed", summary: "same failure twice")
        try led.recordRun(loop: "nightly", runId: "a2", started: t0 + 86400, ended: t0 + 86460, result: "done", summary: "Done")
        try led.recordRun(loop: "nightly", runId: "a3", started: t0 + 172_800, ended: t0 + 172_860, result: "done", summary: "Done")
        try led.recordRun(loop: "nightly", runId: "a3", started: t0 + 172_800, ended: t0 + 172_900, result: "done", summary: "Done again")
        try led.addOutcome(loop: "nightly", runId: "a3", kind: "commit", title: "fix the menu", link: "commit:abc@loop/nightly")
        XCTAssertThrowsError(try led.addOutcome(loop: "nightly", runId: "a3", kind: "tweet", title: "", link: ""))
        let s = try XCTUnwrap(led.summary().first)
        XCTAssertEqual(s.runs, 3)
        XCTAssertEqual(s.lastResult, "done")
        XCTAssertEqual(s.streak, 2)
        XCTAssertEqual(s.engine, "roofd")
        XCTAssertEqual(s.outcomes, ["commit": 1])
        XCTAssertEqual(s.staged, 1)
        XCTAssertEqual(led.staged().first?["title"], "fix the menu")
    }

    func testAlertReadsTheKitNotifierAndOpensWithTheProjectCode() throws {
        let d = tmp()
        let log = d + "/dm.log"
        let script = d + "/dm.sh"
        try "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \(log)\n".write(toFile: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script)
        let cfg = d + "/config.yaml"
        try """
        version: 1
        loops:
          scheduler: launchd
          project: LAB-LOOPS   # the code every loop message opens with
        notifier:                # slack | none
          adapter: slack
          command: "\(script)"    # the message is the last argument
        """.write(toFile: cfg, atomically: true, encoding: .utf8)
        let s = LoopAlert.settings(configPath: cfg)
        XCTAssertEqual(s.command, script)
        XCTAssertEqual(s.project, "LAB-LOOPS")
        let loop = Loop(id: "nightly", name: "nightly", repoPath: d)
        XCTAssertTrue(LoopAlert.send(loop: loop, reason: "The same failure twice", configPath: cfg))
        XCTAssertEqual(try String(contentsOfFile: log, encoding: .utf8), "LAB-LOOPS · loop nightly stopped: The same failure twice\n")
        XCTAssertFalse(LoopAlert.send(loop: loop, reason: "x"), "under XCTest only an explicit config is used")
    }
}
