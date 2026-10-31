import XCTest
@testable import OneRoofCore

/// LAB-1931 · OpenCode and Goose start at ~/Projects like every other agent. New session no longer refuses the
/// workspace root; preparing a launch there keeps the runtime and credential inside it off limits through the kit's
/// guard (protected_read / protected_write) instead of refusing; a specific repository holding them is still refused.
final class HostedWorkspaceRootTests: XCTestCase {
    private func connection(key: String) -> HostedConnection {
        var c = HostedConnection(name: "fixture", provider: .together, model: "zai-org/GLM-5.3-Flash", keyFile: key)
        c.priceChecked = HostedConnection.today(); c.inputPerMillion = 0.15; c.outputPerMillion = 0.5
        return c
    }

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ws-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("app"), withIntermediateDirectories: true)
        return root
    }

    func test_LAB1931_newSessionAcceptsTheWorkspaceRoot() {
        let c = connection(key: "/private/key-reference.txt")
        XCTAssertNil(HostedSheetRules.blockedReason(hasRuntime: true, connection: c, startSupported: true, repo: Workspace.projectsRoot),
                     "~/Projects is a valid start for a hosted session")
        XCTAssertNil(HostedSheetRules.blockedReason(hasRuntime: true, connection: c, startSupported: true, repo: Workspace.projectsRoot + "/labs/oneroof"))
        XCTAssertNotNil(HostedSheetRules.blockedReason(hasRuntime: false, connection: c, startSupported: true, repo: Workspace.projectsRoot))
        XCTAssertNotNil(HostedSheetRules.blockedReason(hasRuntime: true, connection: nil, startSupported: true, repo: Workspace.projectsRoot))
        XCTAssertNotNil(HostedSheetRules.blockedReason(hasRuntime: true, connection: c, startSupported: false, repo: Workspace.projectsRoot))
    }

    func test_LAB1931_planAtTheWorkspaceRootProtectsRuntimeAndCredentialInsideIt() throws {
        let ws = try tempRoot(); defer { try? FileManager.default.removeItem(at: ws) }
        let kit = ws.appendingPathComponent("labs/kit").path, key = ws.appendingPathComponent("_common/keys/provider.key").path
        let native = ws.appendingPathComponent("bin/goose").path, storage = ws.appendingPathComponent(".private").path
        let runtime = HostedRuntimeConfiguration(pythonExecutable: "/usr/bin/python3", kitDirectory: kit,
                                                 nativeExecutables: ["goose": native], storageDirectory: storage)
        let p = try HostedPreparation.plan(connection: connection(key: key), runtime: runtime, agent: .goose, repo: ws.path,
                                           sharedDocs: "/tmp/shared-docs", workspace: ws.path)
        let cwd = p.arguments.firstIndex(of: "--cwd").map { p.arguments[$0 + 1] }
        XCTAssertEqual(cwd, HostedPreparation.fullPath(ws.path), "the session starts at the workspace root")
        let perms = try XCTUnwrap((p.kitConfig["permissions"] as? [String: Any]))
        let read = try XCTUnwrap(perms["protected_read"] as? [String]), write = try XCTUnwrap(perms["protected_write"] as? [String])
        XCTAssertTrue(read.contains(HostedPreparation.fullPath(key)), "no tool reads the credential")
        XCTAssertTrue(read.contains(HostedPreparation.fullPath(storage)), "nor the private launch files")
        XCTAssertTrue(write.contains(HostedPreparation.fullPath(kit)) && write.contains(HostedPreparation.fullPath(native)), "no tool edits the runtime")
        XCTAssertEqual((p.kitConfig["workspace"] as? [String: Any])?["root"] as? String, HostedPreparation.fullPath(ws.path))

        // The stored launch is accepted at relaunch from the same root.
        let launch = HostedPreparedLaunch(connectionID: p.connectionID, agent: .goose, provider: .together, model: p.model,
            executable: p.executable, arguments: p.arguments, environment: p.environment, homeDirectory: p.homeDirectory,
            profilePath: p.profilePath, recordPath: p.recordPath, preparedAt: Date(), nativeVersion: "1.57.0", profileSHA256: "x")
        XCTAssertTrue(launch.matches(repo: ws.path, workspace: ws.path))
        XCTAssertFalse(launch.matches(repo: ws.appendingPathComponent("app").path, workspace: ws.path), "another root never matches")
    }

    func test_LAB1931_aSpecificRepoHoldingTheRuntimeIsStillRefused() throws {
        let ws = try tempRoot(); defer { try? FileManager.default.removeItem(at: ws) }
        let repo = ws.appendingPathComponent("app")
        let runtime = HostedRuntimeConfiguration(pythonExecutable: "/usr/bin/python3", kitDirectory: repo.appendingPathComponent("kit").path,
                                                 nativeExecutables: ["goose": "/pinned/goose"], storageDirectory: "/tmp/hosted-private")
        XCTAssertThrowsError(try HostedPreparation.plan(connection: connection(key: "/private/key"), runtime: runtime, agent: .goose,
                                                        repo: repo.path, sharedDocs: "/tmp/shared-docs", workspace: ws.path))
        // Outside the root everything stays as before: no protected lists are written.
        let outside = HostedRuntimeConfiguration(pythonExecutable: "/usr/bin/python3", kitDirectory: "/opt/kit",
                                                 nativeExecutables: ["goose": "/pinned/goose"], storageDirectory: "/tmp/hosted-private")
        let p = try HostedPreparation.plan(connection: connection(key: "/private/key"), runtime: outside, agent: .goose,
                                           repo: ws.path, sharedDocs: "/tmp/shared-docs", workspace: ws.path)
        let perms = p.kitConfig["permissions"] as? [String: Any]
        XCTAssertNil(perms?["protected_read"]); XCTAssertNil(perms?["protected_write"])
    }
}
