import XCTest
@testable import OneRoofCore

/// LAB-2050 · the Projects list: status mapping (LAB-2307: Linear's five, nothing worked out), the default chips, team groups
/// with counts and folding, the text filter on code and title, Reset, keyboard steps, VoiceOver words and contrast.
final class ProjectListTests: XCTestCase {

    private func p(_ code: String, _ title: String, team: String, _ type: String, name: String = "",
                   toCheck: Int = 0) -> LinearWorkstream {
        LinearWorkstream(id: code, name: "\(code) · \(title)", state: type, url: "", team: team, milestones: [],
                         statusName: name, toCheck: toCheck)
    }

    private var teams: [LinearTeamRef] {
        [("LAB", "Labs"), ("HYP", "Hypothesys"), ("ZIB", "Zibajoon"), ("AGM", "Agencium")].map { LinearTeamRef(id: $0.0, key: $0.0, name: $0.1) }
    }

    private var fixture: [LinearWorkstream] {
        [
            p("LAB-ONEROOF-BUGS", "One Roof bugs", team: "LAB", "started", toCheck: 1),
            p("LAB-EVALS", "Evals in One Roof", team: "LAB", "started", toCheck: 3),
            p("LAB-PAPERS", "Research papers", team: "LAB", "planned", toCheck: 1),
            p("LAB-STARTER", "Starter kit", team: "LAB", "backlog"),
            p("LAB-PITCH", "Pitch deck", team: "LAB", "completed"),
            p("HYP-LAYER", "Layering", team: "HYP", "started"),
            p("HYP-S3", "S3 for all data", team: "HYP", "started", toCheck: 2),
            p("HYP-OLD", "Old dataset", team: "HYP", "canceled"),
            p("ZIB-COST", "AWS cost", team: "ZIB", "paused"),
            p("AGM-RUNTIME", "Fleet runtime", team: "AGM", "backlog"),
        ]
    }

    // MARK: Status mapping

    func test_LAB2050_statusMapping() {
        XCTAssertEqual(ProjectStatus.of(type: "backlog"), .backlog)
        XCTAssertEqual(ProjectStatus.of(type: "planned"), .planned)
        XCTAssertEqual(ProjectStatus.of(type: "started"), .active)
        XCTAssertEqual(ProjectStatus.of(type: "paused"), .pausedOrCancelled, "paused sits with cancelled, as the Linear tab does")
        XCTAssertEqual(ProjectStatus.of(type: "completed"), .shipped)
        XCTAssertEqual(ProjectStatus.of(type: "canceled"), .pausedOrCancelled)
    }

    /// LAB-2307: the chip is Linear's status, whatever the tickets are doing; tickets In Review are a count.
    func test_LAB2307_statusMirrorsLinearTicketsAreACount() {
        let bugs = p("LAB-ONEROOF-BUGS", "One Roof bugs", team: "LAB", "started", toCheck: 1)
        XCTAssertEqual(bugs.status, .active, "Linear says In Progress, so One Roof does")
        XCTAssertEqual(bugs.toCheck, 1)
        XCTAssertEqual(p("LAB-X", "Planned", team: "LAB", "planned", toCheck: 4).status, .planned)
        XCTAssertEqual(ProjectList.toCheckLabel(1), "1 to check")
        XCTAssertEqual(ProjectList.toCheckLabel(3), "3 to check")
        XCTAssertEqual(ProjectList.toCheckLabel(50), "50+ to check")
        XCTAssertFalse(ProjectStatus.allCases.map(\.label).contains("In review"), "no status Linear does not have")
    }

    /// LAB-2307 (owner, 2026-11-19): the chips carry the owner's Linear tab names, in the tabs' order.
    func test_LAB2307_labelsAreTheLinearTabNames() {
        XCTAssertEqual([ProjectList.allLabel] + ProjectStatus.allCases.map(\.label),
                       ["All projects", "Active", "Planned", "Backlog", "Shipped", "Paused or cancelled"])
        let done = p("LAB-X", "Done thing", team: "LAB", "completed")
        XCTAssertEqual(done.stateLabel, "Shipped")
        XCTAssertFalse(ProjectStatus.allCases.map(\.label).contains("Completed"))
    }

    // MARK: Default set and stored selection

    func test_LAB2307_defaultIsActive() {
        XCTAssertEqual(ProjectStatus.defaultSet, [.active])
        XCTAssertEqual(ProjectStatus.decode(nil), ProjectStatus.defaultSet, "never saved = the default")
        XCTAssertEqual(ProjectStatus.decode(""), [], "no chip chosen")
        XCTAssertEqual(ProjectStatus.decode("inReview, completed, bogus"), [.shipped], "unknown words skipped")
        XCTAssertEqual(ProjectStatus.decode("inProgress,inReview"), [.active], "the old default saved")
        XCTAssertEqual(ProjectStatus.decode("completed,canceled"), [.shipped, .pausedOrCancelled], "old words read as the new tabs")
        XCTAssertEqual(ProjectStatus.decode("inReview"), ProjectStatus.defaultSet, "an old In review-only choice: the default, not every status")
        XCTAssertEqual(ProjectStatus.encode([.shipped, .backlog]), "backlog,shipped", "chip order")
        XCTAssertEqual(ProjectStatus.decode(ProjectStatus.encode(ProjectStatus.defaultSet)), ProjectStatus.defaultSet)
    }

    func test_LAB2307_defaultViewShowsOnlyActiveEveryTeamUnfolded() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: ProjectStatus.defaultSet, query: "", folded: [])
        let shown = r.groups.flatMap(\.projects)
        XCTAssertTrue(shown.allSatisfy { $0.status == .active })
        XCTAssertEqual(Set(shown.map { $0.wsId ?? "" }), ["LAB-ONEROOF-BUGS", "LAB-EVALS", "HYP-LAYER", "HYP-S3"])
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
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [.active], query: "", folded: [])
        XCTAssertEqual(r.groups.map(\.key), ["HYP", "LAB"])
        XCTAssertEqual(r.hiddenTeams, 2, "AGM and ZIB have no Active project")
        XCTAssertEqual(ProjectList.hiddenLine(2), "2 teams have no projects in these statuses")
        XCTAssertEqual(ProjectList.hiddenLine(1), "1 team has no projects in these statuses")
        XCTAssertNil(ProjectList.hiddenLine(0))
        // A team Linear lists with no projects at all is counted too.
        let more = teams + [LinearTeamRef(id: "GBL", key: "GBL", name: "GabbleGrid")]
        XCTAssertEqual(ProjectList.groups(projects: fixture, teams: more, statuses: [.active], query: "", folded: []).hiddenTeams, 3)
    }

    /// Done-when: "all Active LAB projects" from the default view with no click; Shipped in one more.
    func test_LAB2050_twoClickQueries() {
        let a = ProjectList.groups(projects: fixture, teams: teams, statuses: ProjectStatus.defaultSet, query: "", folded: [])
        XCTAssertEqual(a.groups.first { $0.key == "LAB" }?.projects.map { $0.wsId ?? "" }, ["LAB-EVALS", "LAB-ONEROOF-BUGS"])
        var s2 = ProjectStatus.defaultSet; s2.insert(.shipped)
        let b = ProjectList.groups(projects: fixture, teams: teams, statuses: s2, query: "", folded: [])
        XCTAssertEqual(b.groups.first { $0.key == "LAB" }?.projects.map { $0.wsId ?? "" }, ["LAB-EVALS", "LAB-ONEROOF-BUGS", "LAB-PITCH"])
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
        XCTAssertEqual(c[.active], 4); XCTAssertEqual(c[.backlog], 2)
        XCTAssertEqual(c[.planned], 1); XCTAssertEqual(c[.shipped], 1); XCTAssertEqual(c[.pausedOrCancelled], 2)
        // Several chips at once.
        let two = ProjectList.groups(projects: fixture, teams: teams, statuses: [.shipped, .pausedOrCancelled], query: "", folded: [])
        XCTAssertEqual(two.groups.flatMap(\.projects).count, 3)
    }

    func test_LAB2050_noChipShowsEveryStatus() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [], query: "", folded: [])
        XCTAssertEqual(r.groups.flatMap(\.projects).count, fixture.count)
    }

    func test_LAB2050_resetRestoresTheDefault() {
        XCTAssertTrue(ProjectList.isDefault(statuses: ProjectStatus.defaultSet, query: ""))
        XCTAssertFalse(ProjectList.isDefault(statuses: [.shipped], query: ""))
        XCTAssertFalse(ProjectList.isDefault(statuses: ProjectStatus.defaultSet, query: "lab"))
        let r = ProjectList.reset()
        XCTAssertEqual(r.statuses, ProjectStatus.defaultSet)
        XCTAssertEqual(r.query, "")
        XCTAssertTrue(ProjectList.isDefault(statuses: r.statuses, query: r.query))
    }

    func test_LAB2050_noMatchIsEmpty() {
        let r = ProjectList.groups(projects: fixture, teams: teams, statuses: [.pausedOrCancelled], query: "lab", folded: [])
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
        XCTAssertEqual(ProjectList.chipLabel(.active, count: 12, on: true), "Active, 12 projects, showing")
        XCTAssertEqual(ProjectList.chipLabel(.shipped, count: 1, on: false), "Shipped, 1 project, hidden")
        let w = p("LAB-2050", "Projects page", team: "LAB", "started")
        XCTAssertEqual(ProjectList.rowLabel(w, live: 2), "Projects page, LAB-2050, Active, 2 live sessions")
        XCTAssertEqual(ProjectList.rowLabel(w, live: 1), "Projects page, LAB-2050, Active, 1 live session")
        XCTAssertEqual(ProjectList.rowLabel(w, live: 0), "Projects page, LAB-2050, Active")
        let r2 = p("LAB-2307", "Status mirror", team: "LAB", "started", toCheck: 2)
        XCTAssertEqual(ProjectList.rowLabel(r2, live: 1), "Status mirror, LAB-2307, Active, 2 to check, 1 live session")
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
