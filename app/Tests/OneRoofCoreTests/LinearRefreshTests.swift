import XCTest
@testable import OneRoofCore

/// LAB-1255: the project list is refreshed like the issues (maxAge), and a project's issues are read page by page
/// (pageInfo / endCursor) up to a cap. Fixtures only, no network.
final class LinearRefreshTests: XCTestCase {

    func test_LAB1255_staleRule() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(LinearClient.isStale(loaded: false, fetchedAt: now, maxAge: 30, now: now), "never loaded")
        XCTAssertTrue(LinearClient.isStale(loaded: true, fetchedAt: nil, maxAge: 30, now: now), "loaded but never timed (1.9.2's one-shot list)")
        XCTAssertFalse(LinearClient.isStale(loaded: true, fetchedAt: now.addingTimeInterval(-29), maxAge: 30, now: now))
        XCTAssertTrue(LinearClient.isStale(loaded: true, fetchedAt: now.addingTimeInterval(-30), maxAge: 30, now: now))
        XCTAssertTrue(LinearClient.isStale(loaded: true, fetchedAt: now, force: true, maxAge: 30, now: now), "force")
    }

    /// A fake Linear: `total` issues served `first` at a time with a cursor; records every request's variables.
    private func fakeIssues(total: Int, stuckCursor: Bool = false) -> (LinearClient, () -> [[String: Any]]) {
        let client = LinearClient(key: "test-key")
        var seen: [[String: Any]] = []
        client.transport = { req in
            let q = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
            let vars = q["variables"] as? [String: Any] ?? [:]
            seen.append(vars)
            let first = vars["first"] as? Int ?? 50
            let start = stuckCursor ? 0 : Int(vars["after"] as? String ?? "0") ?? 0
            let end = min(total, start + first)
            let nodes = (start..<end).map { i -> [String: Any] in
                ["id": stuckCursor ? "id\(i)-\(seen.count)" : "id\(i)", "identifier": "LAB-\(i + 1)", "title": "Issue \(i + 1)",
                 "description": "", "url": "", "state": ["name": "Todo", "type": "unstarted"], "labels": ["nodes": [["name": "Bug"]]]]
            }
            let page: [String: Any] = ["nodes": nodes, "pageInfo": ["hasNextPage": end < total, "endCursor": stuckCursor ? "0" : "\(end)"]]
            let body = try JSONSerialization.data(withJSONObject: ["data": ["project": ["issues": page]]])
            return (200, body)
        }
        return (client, { seen })
    }

    func test_LAB1255_issuesReadEveryPage() throws {
        let (client, seen) = fakeIssues(total: 320)
        let list = try client.issues(project: "p1")
        XCTAssertEqual(list.count, 320, "1.9.2 stopped at 150")
        XCTAssertEqual(list.first?.identifier, "LAB-1")
        XCTAssertEqual(list.last?.identifier, "LAB-320")
        XCTAssertEqual(seen().count, 4, "100 + 100 + 100 + 20")
        XCTAssertNil(seen()[0]["after"])
        XCTAssertEqual(seen()[1]["after"] as? String, "100")
        XCTAssertEqual(seen()[0]["id"] as? String, "p1")
    }

    func test_LAB1255_issuesStopAtTheCap() throws {
        let (client, seen) = fakeIssues(total: 5000)
        let list = try client.issues(project: "p1", cap: 250)
        XCTAssertEqual(list.count, 250)
        XCTAssertEqual(seen().count, 3)
        XCTAssertEqual(seen()[2]["first"] as? Int, 50, "the last page asks only for what the cap leaves")
        XCTAssertEqual(LinearClient.issuesCap, 1000)
    }

    func test_LAB1255_issuesNeverLoopOnACursorThatDoesNotMove() throws {
        let (client, seen) = fakeIssues(total: 400, stuckCursor: true)
        let list = try client.issues(project: "p1")
        XCTAssertLessThanOrEqual(seen().count, 2)
        XCTAssertFalse(list.isEmpty)
    }

    func test_LAB1255_smallProjectIsOneRequest() throws {
        let (client, seen) = fakeIssues(total: 12)
        XCTAssertEqual(try client.issues(project: "p1").count, 12)
        XCTAssertEqual(seen().count, 1)
    }
}

/// LAB-2050 · the project list reads `status { name type }` and whether open issues are In Progress / In Review; the
/// deprecated `state` is the fallback. Fixtures only, no network.
final class LinearProjectStatusParseTests: XCTestCase {
    private func client(_ nodes: [[String: Any]]) -> (LinearClient, () -> String) {
        let c = LinearClient(key: "test-key")
        var query = ""
        c.transport = { req in
            let q = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
            query = q["query"] as? String ?? ""
            let body: [String: Any] = ["data": ["projects": ["pageInfo": ["hasNextPage": false], "nodes": nodes]]]
            return (200, try JSONSerialization.data(withJSONObject: body))
        }
        return (c, { query })
    }

    func test_LAB2050_parsesStatusAndIssueProbes() throws {
        let (c, q) = client([
            ["id": "1", "name": "LAB-A · Alpha", "state": "started", "status": ["name": "In Progress", "type": "started"],
             "teams": ["nodes": [["key": "LAB"]]], "working": ["nodes": []], "reviewing": ["nodes": [["id": "r"]]]],
            ["id": "2", "name": "LAB-B · Beta", "state": "started", "status": ["name": "In Progress", "type": "started"],
             "teams": ["nodes": [["key": "LAB"]]], "working": ["nodes": [["id": "w"]]], "reviewing": ["nodes": [["id": "r"]]]],
            ["id": "3", "name": "HYP-C · Gamma", "state": "started", "status": ["name": "In Review", "type": "started"],
             "teams": ["nodes": [["key": "HYP"]]]],
        ])
        let list = try c.workstreams().sorted { $0.id < $1.id }   // workstreams() sorts by name
        XCTAssertTrue(q().contains("status { name type }"))
        XCTAssertTrue(q().contains("working: issues(") && q().contains("reviewing: issues("))
        XCTAssertEqual(list.map(\.status), [.inReview, .inProgress, .inReview])
        XCTAssertEqual(list[0].statusName, "In Progress")
        XCTAssertTrue(list[0].reviewing); XCTAssertFalse(list[0].working)
        XCTAssertEqual(list[1].stateLabel, "In progress")
    }

    func test_LAB2050_oldStateIsTheFallback() throws {
        let (c, _) = client([["id": "1", "name": "WS-OLD-1 · Old", "state": "completed", "teams": ["nodes": [["key": "CMN"]]]]])
        let list = try c.workstreams()
        XCTAssertEqual(list.first?.state, "completed")
        XCTAssertEqual(list.first?.status, .completed)
        XCTAssertEqual(list.first?.stateLabel, "Completed")
    }
}
