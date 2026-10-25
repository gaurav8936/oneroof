import XCTest
@testable import OneRoofCore

final class LearnMatchTests: XCTestCase {
    let docs = [
        LearnMatch.Doc(id: "handoff", title: "handoff", text: "Write the next-session handoff so a fresh agent resumes cold."),
        LearnMatch.Doc(id: "worktrees", title: "Parallel sessions and worktrees", text: "Run agents in parallel, one git worktree per unit, land with wt-land."),
        LearnMatch.Doc(id: "deploy", title: "ship-domain", text: "Deploy: live to lift to develop to main; the agent ships each repo."),
        LearnMatch.Doc(id: "gg", title: "Plan your goals", text: "Acme plan page and goals."),
    ]

    func testWords() {
        XCTAssertEqual(LearnMatch.words("How do I run agents in parallel worktrees?"), ["run", "agent", "parallel", "worktree"])
        XCTAssertEqual(LearnMatch.stem("deploying"), "deploy")
        XCTAssertEqual(LearnMatch.stem("strategies"), "strategy")
        XCTAssertEqual(LearnMatch.stem("bus"), "bus", "short words keep their s")
        XCTAssertEqual(LearnMatch.stem("matches"), "match")
        XCTAssertEqual(LearnMatch.stem("process"), "process")
    }

    func testRank() {
        XCTAssertEqual(LearnMatch.rank("how do I run two agents in parallel?", docs).first, "worktrees")
        XCTAssertEqual(LearnMatch.rank("write a handoff for the next session", docs).first, "handoff", "title words win")
        XCTAssertEqual(LearnMatch.rank("deploying to main", docs).first, "deploy", "stems match")
        XCTAssertEqual(LearnMatch.rank("how do I", docs), [], "only stop words: nothing")
        XCTAssertFalse(LearnMatch.rank("parallel", docs).contains("gg"), "no shared word: left out")
        XCTAssertEqual(LearnMatch.rank("agent", docs, limit: 2).count, 2)
    }
}

/// LAB-713: the Career Agent playbook (another product's) is left out of Learn; the shared files are not touched.
final class LearnExclusionTests: XCTestCase {
    func test_LAB713_careerAgentPagesAreExcludedFromLearn() {
        XCTAssertTrue(LearnExclusions.isExcluded("/x/ae-folder/agents/career-agent/content/index.html"))
        XCTAssertTrue(LearnExclusions.isExcluded("/x/content/field-manual/playbooks/career-agent/architecture.html"))
        XCTAssertTrue(LearnExclusions.isExcluded("/x/content/field-manual/career-agent.html"))
        XCTAssertFalse(LearnExclusions.isExcluded("/x/content/field-manual/home.html"))
        XCTAssertFalse(LearnExclusions.isExcluded("/x/content/field-manual/playbooks/index.html"))
        XCTAssertFalse(LearnExclusions.isExcluded("/x/skills/career/agent-routing/SKILL.md"))
        XCTAssertTrue(LearnExclusions.hideLinksScript.contains("\"career-agent\""))
    }
}
