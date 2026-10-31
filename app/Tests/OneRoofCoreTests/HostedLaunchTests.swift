import XCTest
import CryptoKit
@testable import OneRoofCore

final class HostedLaunchTests: XCTestCase {
    func testHostedLaunchBypassesShellAndDropsAllCredentialOverrides() {
        let runtime = RoofdRuntime(roofdPath: "/unused", dir: "/tmp/unused")
        var spec = LaunchSpec(id: "hosted", label: "hosted", cwd: Workspace.projectsRoot, env: ["PYTHONPATH": "/trusted/kit", "OPENAI_API_KEY": "must-be-dropped", "GOOSE_MODE": "auto"], agent: .goose, args: ["-m", "ae.hostedsession"])
        spec.executableOverride = "/trusted/python"
        XCTAssertEqual(runtime.argv(spec), ["/trusted/python", "-m", "ae.hostedsession"])
        let env = runtime.environment(spec)
        XCTAssertNil(env["OPENAI_API_KEY"]); XCTAssertNil(env["GOOSE_MODE"])
        XCTAssertEqual(env["PYTHONPATH"], "/trusted/kit")
    }

    func testQuietStartupAndTelemetryQuestionAreNotNativeInputReadiness() {
        XCTAssertFalse(StatusEngine.hostedInputVisible("Help improve goose\nShare anonymous usage data?\nYes", agent: .goose))
        XCTAssertFalse(StatusEngine.hostedInputVisible("Loading providers", agent: .opencode))
        XCTAssertTrue(StatusEngine.hostedInputVisible("goose is ready\n> ", agent: .goose))
        XCTAssertTrue(StatusEngine.hostedInputVisible("goose is ready\n> Enter to send · Ctrl+J newline", agent: .goose))
        XCTAssertTrue(StatusEngine.hostedInputVisible("Ask anything…\nBuild · fixture\ntab agents  ctrl+p commands", agent: .opencode))
        var engine = StatusEngine()
        let start = Date()
        _ = engine.evaluate(.init(now: start, agent: .goose, lastOutput: start, screen: "Share anonymous usage data?"))
        _ = engine.evaluate(.init(now: start.addingTimeInterval(15), agent: .goose, lastOutput: start, screen: "Share anonymous usage data?"))
        XCTAssertFalse(engine.ready)
    }

    func testChangedProfileAndInjectedStoredArgumentsCannotLaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = Workspace.projectsRoot + "/fixture", profile = root.appendingPathComponent("profile.json")
        let data = try JSONSerialization.data(withJSONObject: ["provider": "together", "model": "fixture/model", "price_checked": HostedConnection.today()])
        try data.write(to: profile)
        var launch = HostedPreparedLaunch(connectionID: "fixture", agent: .goose, provider: .together, model: "fixture/model", executable: "/trusted/python",
            arguments: ["-m", "ae.hostedsession", "--agent", "goose", "--binary", "/trusted/goose", "--home", root.path + "/home", "--cwd", repo, "--profile", profile.path, "--record", root.path + "/usage.json", "--timeout", "60"],
            environment: ["PYTHONPATH": "/trusted/kit"], homeDirectory: root.path + "/home", profilePath: profile.path, recordPath: root.path + "/usage.json", preparedAt: Date(), nativeVersion: "1.57.0",
            profileSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
        var session = Session(name: "hosted", agent: .goose, repoPath: repo, model: launch.model, hostedConnectionID: launch.connectionID)
        session.permissionMode = .manual; session.hostedLaunch = launch
        guard case .success(let spec) = LaunchPlan.spec(session, stored: []) else { return XCTFail("Valid prepared launch must be accepted") }
        XCTAssertEqual(spec.agent, .goose); XCTAssertEqual(spec.cwd, repo); XCTAssertEqual(spec.executableOverride, "/trusted/python")
        launch.arguments += ["--unreviewed", "payload"]; session.hostedLaunch = launch
        guard case .failure(.hostedSetupRequired) = LaunchPlan.spec(session, stored: []) else { return XCTFail("Extra argv must fail closed") }
        session.hostedLaunch?.arguments = spec.args
        try Data("changed".utf8).write(to: profile)
        guard case .failure(.hostedSetupRequired) = LaunchPlan.spec(session, stored: []) else { return XCTFail("Changed profile must fail closed") }
    }

    func testPlanPreservesExplicitHostedConnectionAndRejectsUnknownIdentity() throws {
        let text = "```oneroof-plan\n{\"steps\":[{\"id\":\"s1\",\"title\":\"x\",\"agent\":\"goose\",\"model\":\"fixture/model\",\"hosted_connection_id\":\"connection-1\",\"prompt\":\"hello\"}]}\n```"
        let plan = try XCTUnwrap(PlanParser.parse(text))
        XCTAssertEqual(plan.steps.first?.resolvedAgentKind, .goose)
        XCTAssertEqual(plan.steps.first?.hosted_connection_id, "connection-1")
        XCTAssertNil(PlanParser.parse(text.replacingOccurrences(of: "\"goose\"", with: "\"unknown\"")))
    }
}
