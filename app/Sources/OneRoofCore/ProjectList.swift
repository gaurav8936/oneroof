import Foundation

/// LAB-2050 · the status a project shows on the Projects page: its chip and its pill use the same words.
/// LAB-2307 (owner, 2026-11-19): One Roof uses Linear's project statuses and the owner's own Linear tab names for them,
/// in the tabs' order: Active · Planned · Backlog · Shipped · Cancelled (All projects = no chip chosen; owner 11-19: one
/// status for stopped work, Paused retired, a paused project reads as Backlog). It works
/// out no status of its own; tickets waiting for the owner's check show as a count on the row (`LinearWorkstream.toCheck`).
public enum ProjectStatus: String, CaseIterable, Sendable, Hashable {
    case active, planned, backlog, shipped, cancelled

    public var label: String {
        switch self {
        case .active: return "In Progress"
        case .planned: return "Planned"
        case .backlog: return "Backlog"
        case .shipped: return "Shipped"
        case .cancelled: return "Canceled"
        }
    }

    /// The pastel of its pill (Stickers.swift names).
    public var pastel: String {
        switch self {
        case .active: return "sky"
        case .planned: return "peach"
        case .backlog: return "butter"
        case .shipped: return "mint"
        case .cancelled: return "stone"
        }
    }

    /// The default (LAB-2307): Active.
    public static let defaultSet: Set<ProjectStatus> = [.active]

    /// From Linear's project status type, as the owner's Linear tabs group them.
    public static func of(type: String) -> ProjectStatus {
        switch type.lowercased() {
        case "backlog", "paused": return .backlog
        case "planned": return .planned
        case "started": return .active
        case "completed": return .shipped
        case "canceled", "cancelled": return .cancelled
        default: return .backlog
        }
    }

    /// Saved choices from before LAB-2307 ("inProgress,completed", "pausedOrCancelled") read as the new tabs.
    private static let renamed: [String: ProjectStatus] = ["inProgress": .active, "completed": .shipped, "canceled": .cancelled, "pausedOrCancelled": .cancelled]

    /// A remembered selection ("active,shipped"); unknown words are skipped. `nil` (never saved) is the default, and so
    /// is a saved choice left with nothing known in it (an old "inReview" alone).
    public static func decode(_ stored: String?) -> Set<ProjectStatus> {
        guard let stored else { return defaultSet }
        let words = stored.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let known = Set(words.compactMap { ProjectStatus(rawValue: $0) ?? renamed[$0] })
        return known.isEmpty && !words.isEmpty ? defaultSet : known
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

    /// Whether the filter differs from the default (Active, no text): then Reset shows.
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
    /// LAB-2307: the first chip, as the owner's first Linear tab: every status (no chip chosen).
    public static let allLabel = "All projects"

    public static func chipLabel(_ s: ProjectStatus, count n: Int, on: Bool) -> String {
        "\(s.label), \(Self.count(n)), \(on ? "showing" : "hidden")"
    }

    /// VoiceOver for a row: "<title>, <code>, Active, 2 live sessions".
    public static func rowLabel(_ w: LinearWorkstream, live: Int) -> String {
        var parts = [w.title]
        if let code = w.wsId { parts.append(code) }
        parts.append(w.status.label)
        if w.toCheck > 0 { parts.append(toCheckLabel(w.toCheck)) }
        if live > 0 { parts.append(live == 1 ? "1 live session" : "\(live) live sessions") }
        return parts.joined(separator: ", ")
    }

    /// LAB-2307/2318: the row's count of tickets in QA: "1 in QA" / "3 in QA" / "50+ in QA".
    public static func toCheckLabel(_ n: Int) -> String { n >= 50 ? "50+ in QA" : "\(n) in QA" }

    /// ↑/↓ through the visible rows: the next (or previous) id, the first (or last) when nothing is picked.
    public static func step(from id: String?, by delta: Int, in rows: [LinearWorkstream]) -> String? {
        guard !rows.isEmpty else { return nil }
        guard let id, let i = rows.firstIndex(where: { $0.id == id }) else { return (delta >= 0 ? rows.first : rows.last)?.id }
        return rows[max(0, min(rows.count - 1, i + delta))].id
    }
}
