import Foundation

/// LAB-523: the order and filters of the New session issue picker. Picked issues first (in the order they were picked:
/// the plan's starting order), then work in progress, to do, backlog, and In Review last (it is mostly finished work
/// that crowded the top of the list).
public enum IssuePick {
    /// 0 in progress · 1 to do · 2 backlog · 3 in review.
    public static func rank(_ i: LinearIssue) -> Int {
        if i.stateType == "started" { return i.state.localizedCaseInsensitiveContains("review") ? 3 : 0 }
        if i.stateType == "unstarted" { return 1 }
        return 2
    }

    /// The rows to show: picked first in pick order, then by rank, keeping the incoming order (newest first) inside a rank.
    /// `state` nil = All; otherwise only issues in that state (picked ones always stay visible). `query` matches key or title.
    public static func rows(_ issues: [LinearIssue], picked: [String], state: String? = nil, query: String = "") -> [LinearIssue] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ i: LinearIssue) -> Bool {
            q.isEmpty || i.identifier.lowercased().contains(q) || i.title.lowercased().contains(q) || i.description.lowercased().contains(q)
        }
        let byId = Dictionary(issues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let first = picked.compactMap { byId[$0] }
        let chosen = Set(picked)
        let rest = issues.enumerated()
            .filter { !chosen.contains($0.element.id) && matches($0.element) && (state == nil || $0.element.state == state) }
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
        return first + rest
    }

    /// Filter chips: All, then each state present (in rank order) with its count.
    public static func states(_ issues: [LinearIssue]) -> [(state: String?, label: String, count: Int)] {
        var seen: [String: (rank: Int, count: Int)] = [:]
        for i in issues { seen[i.state, default: (rank(i), 0)].count += 1 }
        let states = seen.sorted { ($0.value.rank, $0.key) < ($1.value.rank, $1.key) }.map { (state: Optional($0.key), label: $0.key, count: $0.value.count) }
        return [(state: nil, label: "All", count: issues.count)] + states
    }
}
