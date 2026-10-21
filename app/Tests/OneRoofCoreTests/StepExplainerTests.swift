import XCTest
@testable import OneRoofCore

/// LAB-259: rewind to a step and explain a step.
final class StepExplainerTests: XCTestCase {
    let transcript = """
    > What is the time now?
    ● It's 5:23 PM.
    > What is the capital of France?
    ● The capital of France is Paris.
    > What is the capital of Karnataka?
    ● Bengaluru.
    """

    func testFindsAStepByItsTitle() {
        XCTAssertEqual(StepExplainer.stepText(title: "What is the capital of France?", in: transcript),
                       "> What is the capital of France?\n● The capital of France is Paris.")
        XCTAssertNil(StepExplainer.stepText(title: "Not a step", in: transcript))
    }

    func testRewindTargetCountsLinesFromTheBottom() {
        XCTAssertEqual(StepExplainer.linesFromBottom(title: "What is the capital of France?", in: transcript), 4)
        XCTAssertEqual(StepExplainer.linesFromBottom(title: "What is the capital of Karnataka?", in: transcript), 2)
    }

    func testParsesTheFourSections() {
        let reply = """
        Here you go.
        ## Question
        The capital of France.
        ## What happened
        - Answered from memory
        **Decisions:**
        None
        ## Risks
        None.
        """
        let e = StepExplainer.parse(reply)
        XCTAssertEqual(e?.question, "The capital of France.")
        XCTAssertEqual(e?.happened, "- Answered from memory")
        XCTAssertEqual(e?.decisions, "None")
        XCTAssertEqual(e?.risks, "None.")
        XCTAssertNil(StepExplainer.parse("Error: not logged in"))
    }

    func testPromptKeepsTheEndOfALongStep() {
        let long = String(repeating: "x", count: StepExplainer.maxChars) + "THE END"
        let p = StepExplainer.prompt(title: "t", transcript: long)
        XCTAssertTrue(p.contains("THE END"))
        XCTAssertTrue(p.contains("## Risks"))
        XCTAssertTrue(StepExplainer.command.contains("--tools \"\""), "the explaining model gets no tools")
    }

    func testStepReviewIsOffUntilTheOwnerTurnsItOn() throws {
        // LAB-260: every reviewed step is a model call, so a fresh install and older saved settings start with it off.
        XCTAssertFalse(AppSettings().stepReview)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{\"captionsModel\": true}".utf8))
        XCTAssertFalse(old.stepReview)
        var on = AppSettings(); on.stepReview = true
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(on)).stepReview)
    }
}
