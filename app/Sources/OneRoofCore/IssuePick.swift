import Foundation

/// LAB-523: the order and filters of the New session issue picker: work in progress, to do, backlog, and In Review last
/// (it is mostly finished work that crowded the top of the list).
/// LAB-527: ticking an issue never moves it. Rows keep one order whatever is picked (picked rows used to jump to the top,
/// so the list scrolled under the pointer); the Picked chip shows just the picked ones, in pick order.
public enum IssuePick {
    /// 0 in progress · 1 to do · 2 backlog · 3 in review.
    public static func rank(_ i: LinearIssue) -> Int {
        if i.stateType == "started" { return i.state.localizedCaseInsensitiveContains("review") ? 3 : 0 }
        if i.stateType == "unstarted" { return 1 }
        return 2
    }

    /// The Picked chip's filter value (not a Linear state: Linear state names never start with a space).
    public static let pickedFilter = " picked"

    /// The rows to show, by rank, keeping the incoming order (newest first) inside a rank; picking does not reorder them.
    /// `state` nil = All; `pickedFilter` = only the picked, in pick order; otherwise only issues in that state.
    /// `query` matches key, title or description.
    public static func rows(_ issues: [LinearIssue], picked: [String], state: String? = nil, query: String = "") -> [LinearIssue] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ i: LinearIssue) -> Bool {
            q.isEmpty || i.identifier.lowercased().contains(q) || i.title.lowercased().contains(q) || i.description.lowercased().contains(q)
        }
        if state == pickedFilter {
            let byId = Dictionary(issues.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            return picked.compactMap { byId[$0] }.filter(matches)
        }
        return issues.enumerated()
            .filter { matches($0.element) && (state == nil || $0.element.state == state) }
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// LAB-547: sort keys behind the picker's sortable columns. `sorted` applies the clicked column, issue number as
    /// the tie-break; no column clicked keeps `rows`' order.
    public static func sorted(_ rows: [LinearIssue], by order: [KeyPathComparator<LinearIssue>]) -> [LinearIssue] {
        guard !order.isEmpty else { return rows }
        return rows.sorted(using: order + [KeyPathComparator(\LinearIssue.number)])
    }

    /// Filter chips: All, Picked (when any are), then each state present (in rank order) with its count.
    public static func states(_ issues: [LinearIssue], picked: Int = 0) -> [(state: String?, label: String, count: Int)] {
        var seen: [String: (rank: Int, count: Int)] = [:]
        for i in issues { seen[i.state, default: (rank(i), 0)].count += 1 }
        let states = seen.sorted { ($0.value.rank, $0.key) < ($1.value.rank, $1.key) }.map { (state: Optional($0.key), label: $0.key, count: $0.value.count) }
        let mine = picked > 0 ? [(state: Optional(pickedFilter), label: "Picked", count: picked)] : []
        return [(state: nil, label: "All", count: issues.count)] + mine + states
    }
}

extension LinearIssue {
    /// The picker's state order (in progress, to do, backlog, in review), for sorting by State.
    public var pickRank: Int { IssuePick.rank(self) }
}
