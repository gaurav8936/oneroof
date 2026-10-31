import XCTest
@testable import OneRoofCore

/// LAB-1606: an agent that ends its turn with a plain-text question shows in Needs you, marked as a question.
final class EndOfTurnTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 2_000_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    func obs(_ s: Double, out: Double?, screen: String = "> ") -> StatusEngine.Observation {
        .init(now: at(s), agent: .claude, lastOutput: out.map(at), screen: screen)
    }

    func test_LAB1606_theLastSentenceWhenItIsAQuestion() {
        XCTAssertEqual(EndOfTurn.question("All 12 tests pass. Should I commit this?"), "Should I commit this?")
        XCTAssertEqual(EndOfTurn.question("Done.\n\n**Want me to push it to develop?**"), "Want me to push it to develop?")
        XCTAssertEqual(EndOfTurn.question("Two options:\n- A\n- B\n\nWhich do you prefer: A or B?"), "Which do you prefer: A or B?")
        XCTAssertEqual(EndOfTurn.question("Fixed the bug!   Shall I release 1.9.30? "), "Shall I release 1.9.30?")
    }

    func test_LAB1606_notAQuestion() {
        XCTAssertNil(EndOfTurn.question("Committed as 879c79e. Ready when you are."))
        XCTAssertNil(EndOfTurn.question("What changed? Two files. Both are committed."), "a question earlier, a statement last")
        XCTAssertNil(EndOfTurn.question("Here it is:\n```swift\nlet ok = x ?\n"), "inside a code block")
        XCTAssertNil(EndOfTurn.question(""))
        XCTAssertNil(EndOfTurn.question("?"))
    }

    func test_LAB1606_lastClaudeTextFromTheConversationTail() {
        let lines = [
            #"{"type":"user","message":{"role":"user","content":"fix the bug"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Looking."},{"type":"tool_use","name":"Bash"}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Fixed. Should I commit this?"}]}}"#,
        ]
        XCTAssertEqual(EndOfTurn.lastClaudeText(transcriptTail: lines.joined(separator: "\n")), "Fixed. Should I commit this?")
        XCTAssertNil(EndOfTurn.lastClaudeText(transcriptTail: lines[0]), "the owner's prompt is the newest: nothing said yet")
        XCTAssertEqual(EndOfTurn.question(stopPayload: ["last_assistant_message": "Ok. Ship it?"]), "Ship it?")
    }

    func test_LAB1606_aQuestionWaitsInNeedsYouUntilYouReply() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0))
        e.hook("SessionStart", at: at(0))
        e.hook("UserPromptSubmit", at: at(1))
        e.hook("Stop", question: "Should I commit this?", at: at(10))
        XCTAssertEqual(e.evaluate(obs(11, out: 10)), .blocked)
        XCTAssertEqual(e.question, "Should I commit this?")
        e.hook("Notification", message: "Claude is waiting for your input", at: at(70))
        XCTAssertEqual(e.evaluate(obs(71, out: 10)), .blocked, "still waiting a minute later")
        // You answer in the terminal: Claude's next turn starts.
        e.input(at: at(80))
        e.hook("UserPromptSubmit", at: at(81))
        XCTAssertEqual(e.evaluate(obs(82, out: 81.5)), .working)
        XCTAssertNil(e.question)
        e.hook("Stop", at: at(90))
        XCTAssertEqual(e.evaluate(obs(91, out: 90)), .done, "a turn that ends without a question is done, as before")
    }

    func test_LAB1606_typingAnAnswerLeavesNeedsYou() {
        var e = StatusEngine()
        e.evaluate(obs(0, out: 0))
        e.hook("SessionStart", at: at(0))
        e.hook("Stop", question: "Ship it?", at: at(10))
        XCTAssertEqual(e.evaluate(obs(11, out: 10)), .blocked)
        e.input(at: at(20))
        XCTAssertNotEqual(e.evaluate(obs(23, out: 20.5)), .blocked)
        XCTAssertNil(e.question)
    }

    func test_LAB1606_aReplyIsTheTextAndEnterWithNoEsc() {
        XCTAssertEqual(AnswerKeys.reply("yes, commit").sends, ["yes, commit", "\r"])
        XCTAssertEqual(AnswerKeys.reply("  ").sends, [])
        let d = Decision(sessionId: "s", agent: .claude, kind: .other, why: "Ship it?", touches: "", risk: .low, ifNo: "",
                         pattern: Decision.questionPrefix + "Ship it?", repo: "r")
        XCTAssertTrue(d.isQuestion)
    }
}
