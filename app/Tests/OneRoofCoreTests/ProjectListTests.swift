import XCTest
@testable import OneRoofCore

/// LAB-2050 · the Projects list: status mapping (In review worked out from the issues), the default chips, team groups
/// with counts and folding, the text filter on code and title, Reset, keyboard steps, VoiceOver words and contrast.
final class ProjectListTests: XCTestCase {

    private func p(_ code: String, _ title: String, team: String, _ type: String, name: String = "",
                   working: Bool = false, reviewing: Bool = false) -> LinearWorkstream {
        LinearWorkstream(id: code, name: "\(code) · \(title)", state: type, url: "", team: team, milestones: [],
                         statusName: name, working: working, reviewing: reviewing)
    }

    private var teams: [LinearTeamRef] {
        [("LAB", "Labs"), ("HYP", "Hypothesys"), ("ZIB", "Zibajoon"), ("AGM", "Agencium")].map { LinearTeamRef(id: $0.0, key: $0.0, name: $0.1) }
    }

    private var fixture: [LinearWorkstream] {
        [
            p("LAB-ONEROOF-BUGS", "One Roof bugs", team: "LAB", "started", working: true, reviewing: true),
            p("LAB-EVALS", "Evals in One Roof", team: "LAB", "started", reviewing: true),
            p("LAB-PAPERS", "Research papers", team: "LAB", "planned", reviewing: true),
            p("LAB-STARTER", "Starter kit", team: "LAB", "backlog"),
            p("LAB-PITCH", "Pitch deck", team: "LAB", "completed"),
            p("HYP-LAYER", "Layering", team: "HYP", "started", working: true),
            p("HYP-S3", "S3 for all data", team: "HYP", "started", reviewing: true),
            p("HYP-OLD", "Old dataset", team: "HYP", "canceled"),
            p("ZIB-COST", "AWS cost", team: "ZIB", "paused"),
            p("AGM-RUNTIME", "Fleet runtime", team: "AGM", "backlog"),
        ]
    }

    // MARK: Status mapping

    func test_LAB2050_statusMapping() {
        XCTAssertEqual(ProjectStatus.of(type: "backlog"), .backlog)
        XCTAssertEqual(ProjectStatus.of(type: "planned"), .planned)
        XCTAssertEqual(ProjectStatus.of(type: "started"), .inProgress)
        XCTAssertEqual(ProjectStatus.of(type: "paused"), .inProgress, "paused → In progress (spec)")
        XCTAssertEqual(ProjectStatus.of(type: "completed"), .completed)
        XCTAssertEqual(ProjectStatus.of(type: "canceled"), .canceled)
        XCTAssertEqual(ProjectStatus.of(type: "started", name: "In Review"), .inReview, "a project status named In Review")
        XCTAssertEqual(ProjectStatus.of(type: "started", name: "in review"), .inReview)
    }

    /// Agent decision 2026-11-01: In review = started, some open issue In Review, none In Progress.
    func test_LAB2050_inReviewWorkedOutFromIssues() {
        XCTAssertEqual(ProjectStatus.of(type: "started", reviewing: true), .inReview)
        XCTAssertEqual(ProjectStatus.of(type: "started", working: true, reviewing: true), .inProgress, "work still in progress")
        XCTAssertEqual(ProjectStatus.of(type: "started", working: false, reviewing: false), .inProgress)
        XCTAssertEqual(ProjectStatus.of(type: "paused", reviewing: true), .inReview)
        XCTAssertEqual(ProjectStatus.of(type: "planned", reviewing: true), .planned, "the owner's project status wins outside started")
        XCTAssertEqual(ProjectStatus.of(type: "completed", reviewing: true), .completed)
    }

    func test_LAB2050_labelsSayCompletedNeverShipped() {
        XCTAssertEqual(ProjectStatus.allCases.map(\.label), ["Backlog", "Planned", "In progress", "In review", "Completed", "Canceled"])
        let done = p("LAB-X", "Done thing", team: "LAB", "completed")
        XCTAssertEqual(done.stateLabel, "Completed")
        XCTAssertFalse(ProjectStatus.allCases.map(\.label).contains("Shipped"))
    }

    // MARK: Default set and stored selection

    func test_LAB2050_defaultIsInProgressAndInReview() {
        XCTAssertEqual(ProjectStatus.defaultSet, [.inProgress, .inReview])
        XCTAssertEqual(ProjectStatus.decode(nil), ProjectStatus.defaultSet, "never saved = the default")
        XCTAssertEqual(ProjectStatus.decode(""), [], "no chip chosen")
        XCTAssertEqual(ProjectStatus.decode("inReview, completed, bogus"), [.inReview, .completed])
        XCTAssertEqual(ProjectStatus.encode([.completed, .backlog]), "backlog,completed", "chip order")
        XCTAssertEqual(ProjectStatus.decode(ProjectStatus.encode(ProjectStatus.defaultSet)), ProjectStatus.defaultSet)
    }

    func test_LAB2050_defaultViewShowsOnlyInProgressAndInReviewEveryTeamUnfolded() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: ProjectStatus.defaultSet, query: "", folded: [])
        let shown = r.groups.flatMap(\.projects)
        XCTAssertTrue(shown.allSatisfy { [.inProgress, .inReview].contains($0.status) })
        XCTAssertEqual(Set(shown.map { $0.wsId ?? "" }), ["LAB-ONEROOF-BUGS", "LAB-EVALS", "HYP-LAYER", "HYP-S3", "ZIB-COST"])
        XCTAssertTrue(r.groups.allSatisfy { !$0.folded })
    }

    // MARK: Teams

    func test_LAB2050_teamOrderNamesAndCounts() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [], query: "", folded: [])
        XCTAssertEqual(r.groups.map(\.key), ["AGM", "HYP", "LAB", "ZIB"], "alphabetical by key")
        XCTAssertEqual(r.groups.map(\.projects.count), [1, 3, 5, 1])
        XCTAssertEqual(r.groups.first { $0.key == "LAB" }?.heading, "LAB · Labs")
        XCTAssertEqual(r.groups.first { $0.key == "LAB" }?.projects.map(\.title),
                       ["Evals in One Roof", "One Roof bugs", "Pitch deck", "Research papers", "Starter kit"], "by title")
        XCTAssertEqual(r.hiddenTeams, 0)
    }

    func test_LAB2050_emptyTeamsHiddenAndCounted() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [.inReview], query: "", folded: [])
        XCTAssertEqual(r.groups.map(\.key), ["HYP", "LAB"])
        XCTAssertEqual(r.hiddenTeams, 2, "AGM and ZIB have no In review project")
        XCTAssertEqual(ProjectList.hiddenLine(2), "2 teams have no projects in these statuses")
        XCTAssertEqual(ProjectList.hiddenLine(1), "1 team has no projects in these statuses")
        XCTAssertNil(ProjectList.hiddenLine(0))
        // A team Linear lists with no projects at all is counted too.
        let more = teams + [LinearTeamRef(id: "GBL", key: "GBL", name: "GabbleGrid")]
        XCTAssertEqual(ProjectList.groups(projects: fixture, teams: more, statuses: [.inReview], query: "", folded: []).hiddenTeams, 3)
    }

    /// Done-when: "all In progress LAB projects" and "everything In review in HYP" in ≤ 2 clicks from the default view.
    func test_LAB2050_twoClickQueries() {
        // In progress in LAB: click In review off (1). LAB's group then holds exactly its In progress projects.
        var s = ProjectStatus.defaultSet; s.remove(.inReview)
        let a = ProjectList.groups(projects: fixture, teams: teams, statuses: s, query: "", folded: [])
        XCTAssertEqual(a.groups.first { $0.key == "LAB" }?.projects.map { $0.wsId ?? "" }, ["LAB-ONEROOF-BUGS"])
        // In review in HYP: click In progress off (1). HYP's group is exactly its In review projects.
        var s2 = ProjectStatus.defaultSet; s2.remove(.inProgress)
        let b = ProjectList.groups(projects: fixture, teams: teams, statuses: s2, query: "", folded: [])
        XCTAssertEqual(b.groups.first { $0.key == "HYP" }?.projects.map { $0.wsId ?? "" }, ["HYP-S3"])
    }

    func test_LAB2050_foldOneAndOptionClickAll() {
        let shown = ["HYP", "LAB", "ZIB"]
        var f = ProjectList.toggleFold("LAB", folded: [], all: false, shown: shown)
        XCTAssertEqual(f, ["LAB"])
        f = ProjectList.toggleFold("LAB", folded: f, all: false, shown: shown)
        XCTAssertEqual(f, [])
        f = ProjectList.toggleFold("HYP", folded: [], all: true, shown: shown)
        XCTAssertEqual(f, Set(shown), "⌥-click folds every team")
        f = ProjectList.toggleFold("HYP", folded: f, all: true, shown: shown)
        XCTAssertEqual(f, [], "⌥-click again unfolds every team")
        // Remembered as a string (AppStorage projects.foldedTeams), so it survives a restart.
        XCTAssertEqual(ProjectList.decodeTeams(ProjectList.encodeTeams(["ZIB", "LAB"])), ["LAB", "ZIB"])
        XCTAssertEqual(ProjectList.encodeTeams(["ZIB", "LAB"]), "LAB,ZIB")
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [], query: "", folded: ["LAB"])
        XCTAssertTrue(r.groups.first { $0.key == "LAB" }!.folded)
        XCTAssertFalse(r.visibleRows.contains { $0.team == "LAB" }, "a folded team's rows are not stepped through")
        XCTAssertEqual(r.groups.first { $0.key == "LAB" }?.projects.count, 5, "the count stays on a folded header")
    }

    // MARK: Filter, counts, Reset

    func test_LAB2050_queryMatchesCodeAndTitle() {
        let w = p("HYP-S3", "S3 for all data", team: "HYP", "started")
        XCTAssertTrue(ProjectList.matches(w, query: "hyp-s"))
        XCTAssertTrue(ProjectList.matches(w, query: "ALL DATA"))
        XCTAssertTrue(ProjectList.matches(w, query: "  "))
        XCTAssertFalse(ProjectList.matches(w, query: "layer"))
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [], query: "one roof", folded: [])
        XCTAssertEqual(r.groups.flatMap(\.projects).map { $0.wsId ?? "" }.sorted(), ["LAB-EVALS", "LAB-ONEROOF-BUGS"])
    }

    func test_LAB2050_chipCountsEqualRowsShown() {
        for q in ["", "lab", "data", "zzz"] {
            let counts = ProjectList.counts(fixture, query: q)
            for s in ProjectStatus.allCases {
                let rows = ProjectList.groups(projects: fixture, teams: teams, statuses: [s], query: q, folded: []).groups.flatMap(\.projects)
                XCTAssertEqual(counts[s], rows.count, "\(s) with query \(q)")
            }
        }
        let c = ProjectList.counts(fixture, query: "")
        XCTAssertEqual(c[.inProgress], 3); XCTAssertEqual(c[.inReview], 2); XCTAssertEqual(c[.backlog], 2)
        XCTAssertEqual(c[.planned], 1); XCTAssertEqual(c[.completed], 1); XCTAssertEqual(c[.canceled], 1)
        // Several chips at once.
        let two = ProjectList.groups(projects: fixture, teams: teams, statuses: [.completed, .canceled], query: "", folded: [])
        XCTAssertEqual(two.groups.flatMap(\.projects).count, 2)
    }

    func test_LAB2050_noChipShowsEveryStatus() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [], query: "", folded: [])
        XCTAssertEqual(r.groups.flatMap(\.projects).count, fixture.count)
    }

    func test_LAB2050_resetRestoresTheDefault() {
        XCTAssertTrue(ProjectList.isDefault(statuses: ProjectStatus.defaultSet, query: ""))
        XCTAssertFalse(ProjectList.isDefault(statuses: [.inReview], query: ""))
        XCTAssertFalse(ProjectList.isDefault(statuses: ProjectStatus.defaultSet, query: "lab"))
        let r = ProjectList.reset()
        XCTAssertEqual(r.statuses, ProjectStatus.defaultSet)
        XCTAssertEqual(r.query, "")
        XCTAssertTrue(ProjectList.isDefault(statuses: r.statuses, query: r.query))
    }

    func test_LAB2050_noMatchIsEmpty() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [.canceled], query: "lab", folded: [])
        XCTAssertTrue(r.isEmpty)
    }

    // MARK: Keyboard

    func test_LAB2050_arrowStepsThroughVisibleRows() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [], query: "", folded: ["LAB"])
        let rows = r.visibleRows
        XCTAssertEqual(ProjectList.step(from: nil, by: 1, in: rows), rows.first?.id)
        XCTAssertEqual(ProjectList.step(from: nil, by: -1, in: rows), rows.last?.id)
        XCTAssertEqual(ProjectList.step(from: rows[0].id, by: 1, in: rows), rows[1].id)
        XCTAssertEqual(ProjectList.step(from: rows.last!.id, by: 1, in: rows), rows.last!.id, "stops at the end")
        XCTAssertEqual(ProjectList.step(from: rows[0].id, by: -1, in: rows), rows[0].id, "stops at the top")
        XCTAssertNil(ProjectList.step(from: nil, by: 1, in: []))
    }

    // MARK: VoiceOver

    func test_LAB2050_voiceOverLabels() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [], query: "", folded: ["ZIB"])
        XCTAssertEqual(r.groups.first { $0.key == "LAB" }?.accessibilityLabel, "LAB, Labs, 5 projects, expanded")
        XCTAssertEqual(r.groups.first { $0.key == "ZIB" }?.accessibilityLabel, "ZIB, Zibajoon, 1 project, folded")
        XCTAssertEqual(ProjectList.chipLabel(.inProgress, count: 12, on: true), "In progress, 12 projects, showing")
        XCTAssertEqual(ProjectList.chipLabel(.completed, count: 1, on: false), "Completed, 1 project, hidden")
        let w = p("LAB-2050", "Projects page", team: "LAB", "started", working: true)
        XCTAssertEqual(ProjectList.rowLabel(w, live: 2), "Projects page, LAB-2050, In progress, 2 live sessions")
        XCTAssertEqual(ProjectList.rowLabel(w, live: 1), "Projects page, LAB-2050, In progress, 1 live session")
        XCTAssertEqual(ProjectList.rowLabel(w, live: 0), "Projects page, LAB-2050, In progress")
    }

    // MARK: Contrast (pills and team headers ≥ 4.5:1 in Daylight, Graphite and Midnight)

    func test_LAB2050_pillAndHeaderContrast() {
        for s in ProjectStatus.allCases {
            let pastel = Pastel.named(s.pastel)!
            XCTAssertGreaterThanOrEqual(RGB.contrast(pastel.ink(dark: false), pastel.fill(dark: false)), 4.5, "\(s) pill, light")
            XCTAssertGreaterThanOrEqual(RGB.contrast(pastel.ink(dark: true), pastel.fill(dark: true)), 4.5, "\(s) pill, dark")
        }
        for theme in [ThemeName.daylight, .graphite, .midnight] {
            let t = theme.tokens
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.text, t.window), 4.5, "\(theme) team header")
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.text2, t.window), 4.5, "\(theme) team count and project code")
            XCTAssertGreaterThanOrEqual(RGB.contrast(t.text3, t.window), 4.5, "\(theme) hidden-teams line")
        }
    }
}
