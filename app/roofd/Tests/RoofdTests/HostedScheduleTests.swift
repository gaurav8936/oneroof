import Darwin
import Foundation
import OneRoofCore
import XCTest
@testable import roofd

final class HostedScheduleTests: XCTestCase {
    func testStoredHostedRepeatsCannotLaunchOrSendAnotherPaidTurn() throws {
        let dir = "/tmp/roofd-hosted-schedule-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let oldDir = ProcessInfo.processInfo.environment["ROOFD_DIR"]
        let oldRoot = Workspace.projectsRoot, oldShared = Workspace.sharedRoot
        setenv("ROOFD_DIR", dir, 1)
        defer {
            if let oldDir { setenv("ROOFD_DIR", oldDir, 1) } else { unsetenv("ROOFD_DIR") }
            Workspace.configure(root: oldRoot, shared: oldShared)
            try? FileManager.default.removeItem(atPath: dir)
        }
        let store = try SessionStore(path: dir + "/sessions.sqlite")
        let now = Date()
        for agent in [AgentKind.goose, .opencode] {
            let s = Session(name: "Stored hosted repeat", agent: agent, repoPath: Workspace.projectsRoot,
                openingMessage: "Never send this from a schedule", runtimeId: "existing-hosted-\(agent.rawValue)")
            store.save(s)
            store.save(ScheduleRecord(sessionId: s.id, schedule: .every(minutes: 1), armedAt: now.addingTimeInterval(-120)))
        }
        try Scheduler.save(.init(enabled: true, store: store.path, projects: oldRoot, shared: oldShared))
        Scheduler.tick(now: now, includeLoops: false)
        let records = store.schedules()
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.lastResult?.contains("refused: Hosted agents require manual sessions") == true })
        XCTAssertTrue(store.all().allSatisfy { $0.launchedAt == nil })
        XCTAssertNil(ScheduleClock.hostedRefusal(for: .claude))
        XCTAssertNil(ScheduleClock.hostedRefusal(for: .shell))
    }
}
