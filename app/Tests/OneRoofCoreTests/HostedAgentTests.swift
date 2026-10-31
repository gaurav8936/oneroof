import XCTest
@testable import OneRoofCore

final class HostedAgentTests: XCTestCase {
    func testOpenAgentsAreStableDetectedIdentities() throws {
        for name in ["opencode", "goose"] {
            let kind = try XCTUnwrap(AgentKind(rawValue: name))
            XCTAssertTrue(kind.isAgent)
            XCTAssertEqual(AgentKind(detectedName: name), kind)
            XCTAssertFalse(kind.displayName.isEmpty)
            XCTAssertEqual(try JSONDecoder().decode(AgentKind.self, from: JSONEncoder().encode(kind)), kind)
        }
    }

    func testUnknownPlanAgentIsRejectedInsteadOfRunningClaude() {
        let text = #"```oneroof-plan\n{"steps":[{"id":"s1","title":"x","agent":"not-an-agent","prompt":"hello"}]}\n```"#.replacingOccurrences(of: "\\n", with: "\n")
        XCTAssertNil(PlanParser.parse(text))
    }

    func testOriginalAgentRawValuesRemainUnchanged() {
        for name in ["claude", "codex", "gemini", "agy", "kimi", "shell"] {
            XCTAssertEqual(AgentKind(rawValue: name)?.rawValue, name)
        }
    }

    func testHostedConnectionReferenceRoundTripsAndOldRowsDecodeWithoutIt() throws {
        let s = Session(name: "native", agent: .goose, repoPath: Workspace.projectsRoot,
                        model: "fixture-model", hostedConnectionID: "connection-1")
        let data = try JSONEncoder().encode(s)
        let restored = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(restored.agent, .goose)
        XCTAssertEqual(restored.hostedConnectionID, "connection-1")
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        old.removeValue(forKey: "hostedConnectionID")
        old["agent"] = "codex"
        let legacy = try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertEqual(legacy.agent, .codex)
        XCTAssertNil(legacy.hostedConnectionID)
    }

    func testHostedLaunchIsBlockedUntilSupervisedConnectionSetupExists() {
        let s = Session(name: "needs-setup", agent: .opencode, repoPath: Workspace.projectsRoot)
        switch LaunchPlan.spec(s, stored: []) {
        case .failure(.hostedSetupRequired): break
        default: XCTFail("Must not launch the raw CLI or substitute another agent")
        }
        XCTAssertEqual(AppSettings().permissionMode(for: .goose), .manual)
        var attemptedAuto = AppSettings(); attemptedAuto.permissionModes["goose"] = .auto
        XCTAssertEqual(attemptedAuto.permissionMode(for: .goose), .manual)
        XCTAssertEqual(AppSettings().permissionMode(for: .codex), .auto)
        XCTAssertTrue(AnswerKeys.keys(for: .allowOnce, prompt: nil, agent: .goose).sends.isEmpty)
    }

    func testPlanAgentNamesAreValidatedRatherThanFuzzyProcessMatches() {
        let text = "```oneroof-plan\n{\"steps\":[{\"id\":\"s1\",\"title\":\"x\",\"agent\":\"not-a-real-claude\",\"prompt\":\"hello\"}]}\n```"
        XCTAssertNil(PlanParser.parse(text))
    }
}
