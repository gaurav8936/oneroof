import Foundation

/// LAB-2050 · the status a project shows on the Projects page: its chip and its pill use the same words.
/// Linear's project statuses are Backlog · Planned · In Progress · Completed · Canceled (and Paused on older
/// workspaces). Linear has no In Review project status, so One Roof works it out (agent decision 2026-11-01): a project
/// that is started (or paused) is **In review** when it has an open issue In Review and none in another started state
/// (In Progress). A project status named "In Review" (if the owner adds one) counts too.
public enum ProjectStatus: String, CaseIterable, Sendable, Hashable {
    case backlog, planned, inProgress, inReview, completed, canceled

    public var label: String {
        switch self {
        case .backlog: return "Backlog"
        case .planned: return "Planned"
        case .inProgress: return "In progress"
        case .inReview: return "In review"
        case .completed: return "Completed"
        case .canceled: return "Canceled"
        }
    }

    /// The pastel of its pill (Stickers.swift names).
    public var pastel: String {
        switch self {
        case .backlog: return "butter"
        case .planned: return "peach"
        case .inProgress: return "sky"
        case .inReview: return "lavender"
        case .completed: return "mint"
        case .canceled: return "stone"
        }
    }

    /// The owner's default (2026-10-31): In progress + In review.
    public static let defaultSet: Set<ProjectStatus> = [.inProgress, .inReview]

    /// From Linear's project status (`type`, `name`) and whether it has open issues In Progress (`working`) or In Review
    /// (`reviewing`).
    public static func of(type: String, name: String = "", working: Bool = false, reviewing: Bool = false) -> ProjectStatus {
        switch type.lowercased() {
        case "backlog": return .backlog
        case "planned": return .planned
        case "completed": return .completed
        case "canceled", "cancelled": return .canceled
        case "started", "paused":
            if name.caseInsensitiveCompare("In Review") == .orderedSame { return .inReview }
            return reviewing && !working ? .inReview : .inProgress
        default: return .backlog
        }
    }

    /// A remembered selection ("inProgress,inReview"); unknown words are skipped. `nil` (never saved) is the default.
    public static func decode(_ stored: String?) -> Set<ProjectStatus> {
        guard let stored else { return defaultSet }
        return Set(stored.split(separator: ",").compactMap { ProjectStatus(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }

    public static func encode(_ set: Set<ProjectStatus>) -> String {
        allCases.filter(set.contains).map(\.rawValue).joined(separator: ",")
    }
}

/// One team on the Projects page: its key, its name from Linear, and its projects that pass the filter.
public struct ProjectGroup: Equatable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var projects: [LinearWorkstream]
    public var folded: Bool
    public var id: String { key }
    /// "LAB · Labs" (the key alone when Linear's name is the key or missing).
    public var heading: String { name.isEmpty || name == key ? key : "\(key) · \(name)" }
    /// VoiceOver: "LAB, Labs, 14 projects, expanded".
    public var accessibilityLabel: String {
        ([key] + (name.isEmpty || name == key ? [] : [name]) + [ProjectList.count(projects.count), folded ? "folded" : "expanded"])
            .joined(separator: ", ")
    }
}

/// The Projects list (LAB-2050): teams → projects, filtered by status chips and a text filter, teams folding.
public enum ProjectList {
    public struct Result: Equatable, Sendable {
        public var groups: [ProjectGroup]
        /// Teams with no project in the chosen statuses (hidden; the list says how many).
        public var hiddenTeams: Int
        /// Projects per status after the text filter (the chips' counts).
        public var counts: [ProjectStatus: Int]
        /// The rows ↑/↓ move through: projects of unfolded teams, top to bottom.
        public var visibleRows: [LinearWorkstream] { groups.filter { !$0.folded }.flatMap(\.projects) }
        public var isEmpty: Bool { groups.isEmpty }
    }

    /// "1 project" / "14 projects".
    public static func count(_ n: Int) -> String { n == 1 ? "1 project" : "\(n) projects" }

    /// The text filter: the project code or the title (the whole name), case-insensitive. Empty matches all.
    public static func matches(_ w: LinearWorkstream, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return [w.wsId ?? "", w.title, w.name].contains { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Projects per status after the text filter (every status listed, 0 when none).
    public static func counts(_ projects: [LinearWorkstream], query: String) -> [ProjectStatus: Int] {
        var out = Dictionary(uniqueKeysWithValues: ProjectStatus.allCases.map { ($0, 0) })
        for w in projects where matches(w, query: query) { out[w.status, default: 0] += 1 }
        return out
    }

    /// Teams alphabetical by key; inside a team, projects by title. No chip chosen = every status. A team with no
    /// matching project is left out and counted in `hiddenTeams` (teams from `teams` and from the projects both count).
    public static func groups(projects: [LinearWorkstream], teams: [LinearTeamRef], statuses: Set<ProjectStatus>,
                              query: String, folded: Set<String>) -> Result {
        let names = Dictionary(teams.map { ($0.key, $0.name) }, uniquingKeysWith: { a, _ in a })
        let keys = Set(teams.map(\.key)).union(projects.map(\.team)).sorted()
        let shown = projects.filter { matches($0, query: query) && (statuses.isEmpty || statuses.contains($0.status)) }
        var groups: [ProjectGroup] = []
        var hidden = 0
        for k in keys {
            let rows = shown.filter { $0.team == k }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            if rows.isEmpty { hidden += 1; continue }
            groups.append(ProjectGroup(key: k, name: k.isEmpty ? "No team" : names[k] ?? k, projects: rows, folded: folded.contains(k)))
        }
        return Result(groups: groups, hiddenTeams: hidden, counts: counts(projects, query: query))
    }

    /// Whether the filter differs from the default (In progress + In review, no text): then Reset shows.
    public static func isDefault(statuses: Set<ProjectStatus>, query: String) -> Bool {
        statuses == ProjectStatus.defaultSet && query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Reset: the default statuses and no text (folds are left as they are).
    public static func reset() -> (statuses: Set<ProjectStatus>, query: String) { (ProjectStatus.defaultSet, "") }

    /// Fold or unfold one team; with `all` (⌥-click) every shown team follows that team's new state.
    public static func toggleFold(_ team: String, folded: Set<String>, all: Bool, shown: [String]) -> Set<String> {
        let fold = !folded.contains(team)
        if all { return fold ? folded.union(shown) : folded.subtracting(shown) }
        return fold ? folded.union([team]) : folded.subtracting([team])
    }

    public static func decodeTeams(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    public static func encodeTeams(_ set: Set<String>) -> String { set.sorted().joined(separator: ",") }

    /// The muted line under the list: "2 teams have no projects in these statuses".
    public static func hiddenLine(_ n: Int) -> String? {
        switch n {
        case 0: return nil
        case 1: return "1 team has no projects in these statuses"
        default: return "\(n) teams have no projects in these statuses"
        }
    }

    /// VoiceOver for a chip: "In progress, 12 projects, showing" or "…, hidden".
    public static func chipLabel(_ s: ProjectStatus, count n: Int, on: Bool) -> String {
        "\(s.label), \(Self.count(n)), \(on ? "showing" : "hidden")"
    }

    /// VoiceOver for a row: "<title>, <code>, In progress, 2 live sessions".
    public static func rowLabel(_ w: LinearWorkstream, live: Int) -> String {
        var parts = [w.title]
        if let code = w.wsId { parts.append(code) }
        parts.append(w.status.label)
        if live > 0 { parts.append(live == 1 ? "1 live session" : "\(live) live sessions") }
        return parts.joined(separator: ", ")
    }

    /// ↑/↓ through the visible rows: the next (or previous) id, the first (or last) when nothing is picked.
    public static func step(from id: String?, by delta: Int, in rows: [LinearWorkstream]) -> String? {
        guard !rows.isEmpty else { return nil }
        guard let id, let i = rows.firstIndex(where: { $0.id == id }) else { return (delta >= 0 ? rows.first : rows.last)?.id }
        return rows[max(0, min(rows.count - 1, i + delta))].id
    }
}
