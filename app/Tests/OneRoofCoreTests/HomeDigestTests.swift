import XCTest
@testable import OneRoofCore

/// LAB-2198: the overnight river in words (what went wrong, what to do next, what ran fine).
final class HomeDigestTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func run(_ loop: String, _ title: String, _ h: Double, _ result: String, _ summary: String = "") -> HomeFrontPage.LoopRun {
        HomeFrontPage.LoopRun(loop: loop, title: title, started: t0.addingTimeInterval(h * 3600), result: result, summary: summary)
    }

    func test_LAB2198_failuresListedOnceRecommendationsAndFoldedRepeats() {
        let runs = [run("nb", "oneroof-nightly-bugs", 1, "failed", "exit 1"), run("nb", "oneroof-nightly-bugs", 3, "failed", "exit 1"),
                    run("ds", "Docs drift", 2, "failed"), run("ds", "Docs drift", 5, "ok"),
                    run("cw", "Cost watch", 1, "ok"), run("cw", "Cost watch", 2, "ok"), run("cw", "Cost watch", 3, "ok"),
                    run("sa", "Security audit", 4, "ok")]
        let moments = [HomeFrontPage.Moment(at: t0.addingTimeInterval(6 * 3600), kind: .error, text: "exited while working", session: "2.0.1: Bug fixes"),
                       HomeFrontPage.Moment(at: t0.addingTimeInterval(7 * 3600), kind: .done, text: "", session: "Blog")]
        let d = HomeFrontPage.digest(runs: runs, moments: moments)
        // Newest first; each loop once.
        XCTAssertEqual(d.wrong.map(\.name), ["2.0.1: Bug fixes", "oneroof-nightly-bugs", "Docs drift"])
        XCTAssertEqual(d.wrong[1].reason, "failed twice in a row: exit 1")
        XCTAssertEqual(d.wrong[2].reason, "failed (failed)")
        // Recommendations: the streak says it will fail again and offers Run it again; the recovered one only Open.
        let nb = d.next.first { $0.id == "lnb" }
        XCTAssertTrue(nb?.text.contains("2 times in a row") == true)
        XCTAssertEqual(nb?.actions.map(\.title), ["Open the loop", "Run it again"])
        XCTAssertEqual(d.next.first { $0.id == "lds" }?.actions.map(\.title), ["Open the loop"])
        XCTAssertTrue(d.next.contains { $0.id == "sessions" && $0.text.hasPrefix("2.0.1: Bug fixes hit an error") })
        XCTAssertLessThanOrEqual(d.next.count, 3)
        // Fine: most runs first, repeats folded.
        XCTAssertEqual(d.fine.first, "Cost watch ×3")
        XCTAssertTrue(d.fine.contains("Docs drift") && d.fine.contains("Security audit") && d.fine.contains("Blog"))
        XCTAssertEqual(d.total, 10)   // 8 loop runs + 1 error + 1 done
    }

    func test_LAB2198_quietNightHasNothingWrong() {
        let d = HomeFrontPage.digest(runs: [run("cw", "Cost watch", 1, "ok")], moments: [])
        XCTAssertTrue(d.wrong.isEmpty); XCTAssertTrue(d.next.isEmpty)
        XCTAssertEqual(d.fine, ["Cost watch"]); XCTAssertEqual(d.total, 1)
    }
}
