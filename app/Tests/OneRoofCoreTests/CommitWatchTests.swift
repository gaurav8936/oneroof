import XCTest
@testable import OneRoofCore

/// LAB-474: a commit that names one of a session's issues moves that issue to In Review, once.
final class CommitWatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func session() -> Session {
        var s = Session(name: "t", repoPath: "/r", ticket: "LAB-472", ticketId: "a", ticketTeam: "LAB")
        s.moreTickets = [SessionIssue(key: "LAB-474", id: "b", team: "LAB")]
        s.launchedAt = t0
        return s
    }

    private func commit(_ subject: String, at offset: TimeInterval, sha: String = "abc1234") -> CommitWatch.Commit {
        .init(sha: sha, subject: subject, time: t0.addingTimeInterval(offset), repo: "/r")
    }

    func test_namesMatchesWholeKeysOnly() {
        XCTAssertTrue(CommitWatch.names("LAB-474 · [lab-oneroof-bugs] fix", key: "LAB-474"))
        XCTAssertTrue(CommitWatch.names("fix lab-474: panel", key: "LAB-474"))
        XCTAssertFalse(CommitWatch.names("LAB-4741 · other", key: "LAB-474"))
        XCTAssertFalse(CommitWatch.names("LAB-474 · x", key: "LAB-47"))
        XCTAssertFalse(CommitWatch.names("XLAB-474 · x", key: "LAB-474"))
    }

    func test_eachIssueMatchesItsOwnCommitAfterLaunch() {
        let commits = [commit("LAB-474 · old", at: -3600, sha: "old"), commit("LAB-474 · new", at: 600, sha: "new"),
                       commit("LAB-472 · fix", at: 300, sha: "fix"), commit("LAB-999 · other", at: 100)]
        let m = CommitWatch.matches(session(), in: commits)
        XCTAssertEqual(m.map(\.0.key), ["LAB-472", "LAB-474"])
        XCTAssertEqual(m.map(\.1.sha), ["fix", "new"])
    }

    func test_reviewedIssuesAreNotMovedAgain() {
        var s = session()
        s.reviewedTickets = ["LAB-472"]
        XCTAssertEqual(CommitWatch.pending(s).map(\.key), ["LAB-474"])
        XCTAssertEqual(CommitWatch.matches(s, in: [commit("LAB-472 · again", at: 60)]).count, 0)
        s.reviewedTickets.append("lab-474")
        XCTAssertFalse(CommitWatch.watches(s, now: t0.addingTimeInterval(60)))
    }

    func test_watchOnlyRecentLaunchedSessions() {
        var s = session()
        XCTAssertTrue(CommitWatch.watches(s, now: t0.addingTimeInterval(3600)))
        XCTAssertFalse(CommitWatch.watches(s, now: t0.addingTimeInterval(CommitWatch.window + 1)))
        s.launchedAt = nil
        XCTAssertFalse(CommitWatch.watches(s))
    }

    func test_parseLog() {
        let out = "abc1234\u{1f}1800000600\u{1f}LAB-474 · [x] a · b\nbad line\n"
        let c = CommitWatch.parseLog(out, repo: "/r")
        XCTAssertEqual(c, [.init(sha: "abc1234", subject: "LAB-474 · [x] a · b", time: t0.addingTimeInterval(600), repo: "/r")])
    }
}
