import XCTest
@testable import OneRoofCore

/// LAB-2102 · Settings › Linear: the mapping from a workspace's own state and label names to One Roof's, saved and used
/// when reading (Type labels, the review state) and writing (moves, new tickets); the connection test. Fixtures only.
final class LinearMappingTests: XCTestCase {
    private let teamStates: [(id: String, name: String, type: String)] = [
        ("s1", "Inbox", "backlog"), ("s2", "Ready", "unstarted"), ("s3", "Doing", "started"),
        ("s4", "Code review", "started"), ("s5", "Shipped", "completed"), ("s6", "Dropped", "canceled"),
    ]

    func test_LAB2102_standardMappingKeepsTodaysNames() {
        let m = LinearMapping.standard
        XCTAssertEqual(LinearMapping.canonicalStates.map(m.stateName), ["Backlog", "Todo", "In Progress", "In Review", "Done", "Canceled"])
        XCTAssertEqual(m.reviewState, "In Review")
        XCTAssertEqual(m.labelNames(.defect), ["Bug", "type:defect"])
        XCTAssertEqual(m.kind(fromLabel: "Task"), .chore)
        XCTAssertTrue(m.isStandard)
    }

    func test_LAB2102_onlyDifferencesAreStored() {
        var m = LinearMapping.standard
        m.setState("Done", to: "Shipped")
        m.setState("Todo", to: "Todo")          // same as recommended: not stored
        m.setLabel(.defect, to: "Defect")
        m.setLabel(.chore, to: " Task ")        // recommended (trimmed): not stored
        XCTAssertEqual(m.states, ["Done": "Shipped"])
        XCTAssertEqual(m.typeLabels, ["defect": "Defect"])
        m.setState("Done", to: "")
        XCTAssertNil(m.states["Done"], "blank goes back to the recommended name")
    }

    func test_LAB2102_resolveStateByMappedNameThenCaseThenType() {
        var m = LinearMapping.standard
        m.setState("In Review", to: "Code review")
        XCTAssertEqual(m.resolveState("In Review", in: teamStates)?.id, "s4")
        XCTAssertEqual(m.resolveState("In Progress", in: teamStates)?.id, "s3", "In Progress never picks the review state")
        XCTAssertEqual(m.resolveState("Done", in: teamStates)?.name, "Shipped", "falls back to the state of that type")
        XCTAssertEqual(m.resolveState("canceled", in: teamStates)?.id, "s6")
        XCTAssertEqual(LinearMapping.standard.resolveState("In Review", in: teamStates)?.id, "s4", "a started state named …review")
        XCTAssertNil(m.resolveState("Blocked", in: teamStates), "not one of One Roof's states")
        XCTAssertEqual(m.canonical(forTeamState: "code review"), "In Review")
    }

    func test_LAB2102_mappedLabelsReadAndWritten() {
        var m = LinearMapping.standard
        m.setLabel(.defect, to: "Defect")
        XCTAssertEqual(m.kind(fromLabel: "defect"), .defect)
        XCTAssertEqual(m.kind(fromLabel: "Bug"), .defect, "the standard name still reads")
        XCTAssertEqual(m.labelNames(.defect).first, "Defect", "new tickets get the workspace's label")
    }

    func test_LAB2102_hiddenTeamsLeaveProjectsOut() {
        var m = LinearMapping.standard
        m.setTeam("OPS", shown: false)
        m.setTeam("API", shown: false)
        m.setTeam("API", shown: true)
        XCTAssertEqual(m.hiddenTeams, ["OPS"])
        let ps = [LinearWorkstream(id: "1", name: "WEB-A · a", state: "started", url: "", team: "WEB", milestones: []),
                  LinearWorkstream(id: "2", name: "OPS-B · b", state: "started", url: "", team: "OPS", milestones: [])]
        XCTAssertEqual(m.visible(ps).map(\.id), ["1"])
    }

    func test_LAB2102_problemsNameWhatATeamLacks() {
        var m = LinearMapping.standard
        m.setState("In Review", to: "Code review")
        let p = m.problems(teamKey: "WEB", states: teamStates, labels: ["Bug", "Feature", "Spike"])
        XCTAssertTrue(p.isEmpty == false)
        XCTAssertTrue(p.contains("WEB: no Deliverable label (Type: deliverable)"))
        XCTAssertFalse(p.contains { $0.contains("state") }, "every state resolves")
        XCTAssertTrue(m.problems(teamKey: "WEB", states: [], labels: []).contains("WEB: no state for Done (looked for \"Done\")"))
    }

    func test_LAB2102_mappingSavedAndLoaded() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lab2102-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = dir.appendingPathComponent("linear-mapping.json").path
        XCTAssertEqual(LinearMapping.load(path: path), .standard, "no file = the recommended names")
        var m = LinearMapping.standard
        m.setState("Done", to: "Shipped"); m.setTeam("OPS", shown: false)
        try m.save(to: path)
        XCTAssertEqual(LinearMapping.load(path: path), m)
        try Data("{\"states\":{\"Todo\":\"Ready\"}}".utf8).write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(LinearMapping.load(path: path).stateName("Todo"), "Ready", "older or partial files still load")
    }

    /// The client uses the mapping: the review state goes into the project query, and moves resolve through it.
    func test_LAB2102_clientUsesMapping() throws {
        var m = LinearMapping.standard
        m.setState("In Review", to: "Code review")
        let c = LinearClient(key: "test-key", mapping: m)
        var bodies: [[String: Any]] = []
        c.transport = { req in
            let q = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
            bodies.append(q)
            let query = q["query"] as? String ?? ""
            let data: [String: Any]
            if query.contains("projects(") {
                data = ["projects": ["pageInfo": ["hasNextPage": false], "nodes": []]]
            } else if query.contains("viewer") {
                data = ["viewer": ["name": "Someone"], "organization": ["name": "Example Co"], "teams": ["nodes": [["id": "a"], ["id": "b"]]]]
            } else {
                data = ["issueUpdate": ["success": true]]
            }
            return (200, try JSONSerialization.data(withJSONObject: ["data": data]))
        }
        _ = try c.workstreams()
        XCTAssertEqual((bodies.last?["variables"] as? [String: Any])?["review"] as? String, "Code review")
        let team = LinearTeam(id: "t", key: "WEB", states: teamStates, labels: [:])
        try c.setState(issue: "i1", team: team, named: "In Review")
        XCTAssertEqual(((bodies.last?["variables"] as? [String: Any])?["s"] as? String), "s4")
        try c.setState(issue: "i1", team: team, named: "Done")
        XCTAssertEqual(((bodies.last?["variables"] as? [String: Any])?["s"] as? String), "s5")
        let r = try c.testConnection()
        XCTAssertEqual(r.user, "Someone"); XCTAssertEqual(r.workspace, "Example Co"); XCTAssertEqual(r.teams, 2)
        XCTAssertEqual(c.with(mapping: .standard).mapping, .standard)
    }

    func test_LAB2102_noKeyPointsToSettings() {
        XCTAssertTrue("\(LinearClient.Failure.noKey)".contains("Settings › Linear"))
        XCTAssertThrowsError(try LinearClient(key: nil).testConnection())
    }
}
