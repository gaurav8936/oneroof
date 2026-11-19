import XCTest
@testable import OneRoofCore

/// LAB-2329 · Agent factory F1: the recipe format and the five built-ins.
final class AgentRecipeTests: XCTestCase {
    func testFiveBuiltInsOnePerPatternAllRunnable() {
        XCTAssertEqual(AgentRecipes.builtIn.count, 5)
        XCTAssertEqual(Set(AgentRecipes.builtIn.map(\.pattern)), Set(RecipePattern.allCases))
        XCTAssertEqual(Set(AgentRecipes.builtIn.map(\.id)).count, 5)
        for r in AgentRecipes.builtIn {
            XCTAssertEqual(r.problems, [], r.id)
            XCTAssertTrue(r.builtIn)
            XCTAssertEqual(r.roles.map(\.name), r.pattern.roleNames, "\(r.id): roles in the order they act")
        }
        XCTAssertGreaterThan(Set(AgentRecipes.builtIn.flatMap(\.agents)).count, 2, "teams mix agents, not only Claude")
    }

    func testMakerCheckerNeedsTwoDifferentAgents() {
        var r = AgentRecipes.builtIn[0]
        XCTAssertEqual(r.pattern, .makerChecker)
        r.roles[1].agent = .claude; r.roles[1].model = "opus"
        XCTAssertTrue(r.problems.contains { $0.contains("same agent and model") })
        r.roles[1].model = "sonnet"
        XCTAssertFalse(r.problems.contains { $0.contains("same agent and model") }, "another model is a different checker")
    }

    func testProblemsInPlainWords() {
        var r = AgentRecipes.builtIn[2]   // fan-out
        r.roles.removeLast(); r.budget.maxParallel = 5; r.finishLine.check = " "; r.finishLine.result = "slack"
        let p = r.problems
        XCTAssertTrue(p.contains { $0.contains("needs the role merger") })
        XCTAssertTrue(p.contains { $0.contains("parallel parts must be 1 to 3") })
        XCTAssertTrue(p.contains("no finish line check"))
        XCTAssertTrue(p.contains("result must be qa, pr or report"))
        var s = AgentRecipes.builtIn[1]; s.roles[0].agent = .shell
        XCTAssertTrue(s.problems.contains { $0.contains("plain shell") })
        var loop = AgentRecipes.builtIn[4]; loop.budget.rounds = 1
        XCTAssertTrue(loop.problems.contains { $0.contains("at least 2 rounds") })
    }

    func testJSONRoundTripAndOwnFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("recipes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var mine = AgentRecipes.builtIn[3]; mine.id = "my-judge"; mine.name = "My judge"
        try AgentRecipes.json(mine).write(to: dir.appendingPathComponent("my-judge.json"), atomically: true, encoding: .utf8)
        try AgentRecipes.json(AgentRecipes.builtIn[0]).write(to: dir.appendingPathComponent("dup.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: dir.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)
        var newer = mine; newer.id = "newer"; newer.format = AgentRecipe.formatVersion + 1
        try AgentRecipes.json(newer).write(to: dir.appendingPathComponent("newer.json"), atomically: true, encoding: .utf8)
        try "x".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let l = AgentRecipes.load(from: dir)
        XCTAssertEqual(l.recipes.count, 6)
        let got = try XCTUnwrap(l.recipes.last)
        XCTAssertEqual(got.id, "my-judge"); XCTAssertFalse(got.builtIn); XCTAssertEqual(got.roles, mine.roles)
        XCTAssertEqual(l.skipped.count, 3)
        XCTAssertTrue(l.skipped.contains { $0.hasPrefix("bad.json") })
        XCTAssertTrue(l.skipped.contains { $0.hasPrefix("dup.json") && $0.contains("already used") })
        XCTAssertTrue(l.skipped.contains { $0.hasPrefix("newer.json") && $0.contains("newer One Roof") })
        XCTAssertEqual(AgentRecipes.load(from: dir.appendingPathComponent("missing")).recipes.count, 5)
    }

    func testLibraryLine() {
        XCTAssertEqual(AgentRecipes.builtIn[0].line, "Maker → checker · Claude + Codex · up to 90 min, $15")
    }
}
