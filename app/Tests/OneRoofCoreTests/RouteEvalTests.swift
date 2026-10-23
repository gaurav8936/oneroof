import XCTest
@testable import OneRoofCore

/// LAB-673: the classifier's test set (scripts/route-eval/tasks.json) stays usable: 35–40 sentences, every kind covered,
/// only known kinds, ambiguous ones with a second fair answer.
final class RouteEvalTests: XCTestCase {
    struct Task: Decodable { let text: String; let kind: String; let accept: [String]? }
    struct Set_: Decodable { let tasks: [Task] }

    func test_routeEval_fixtureCoversEveryKind() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("scripts/route-eval/tasks.json")
        let set = try JSONDecoder().decode(Set_.self, from: Data(contentsOf: url))
        let kinds = Set(RoutingPolicy.kindDescriptions(agenticEngineering: "/nonexistent").keys)
        XCTAssertEqual(kinds.count, 7)
        XCTAssertTrue((35...40).contains(set.tasks.count), "\(set.tasks.count) sentences")
        XCTAssertEqual(Set(set.tasks.map(\.kind)), kinds)
        for t in set.tasks {
            XCTAssertTrue(kinds.isSuperset(of: t.accept ?? []), t.text)
            XCTAssertFalse((t.accept ?? []).contains(t.kind), t.text)
        }
        XCTAssertGreaterThanOrEqual(set.tasks.filter { !($0.accept ?? []).isEmpty }.count, 5, "some ambiguous sentences")
        XCTAssertEqual(Set(set.tasks.map(\.text)).count, set.tasks.count, "no duplicates")
    }

    /// The harness sends the app's prompt: every line of the app's system message (examples and rules included) is in
    /// app/scripts/route-eval.py, so a prompt change without the script (or the other way round) fails here.
    func test_routeEval_harnessMirrorsTheAppPrompt() throws {
        let script = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/route-eval.py"), encoding: .utf8)
        let prompt = LocalModel.systemPrompt(kinds: ["code": "x"])
        for line in prompt.split(separator: "\n").dropFirst(2) {
            let l = line.replacingOccurrences(of: "\"", with: "\\\"")
            XCTAssertTrue(script.contains(String(line)) || script.contains(l), "route-eval.py lacks: \(line)")
        }
        XCTAssertTrue(script.contains("\"Task: \" + text"))
        XCTAssertTrue(script.contains("\"enable_thinking\": False"))
    }
}
