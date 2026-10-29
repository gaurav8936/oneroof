import Foundation

/// LAB-1559: the New session sheet's Team and Project pickers can be searched. A row matches when every word typed
/// appears in it, in any order and any case ("bugs oneroof" finds "LAB-ONEROOF-BUGS · One Roof bug fixes").
public enum PickerSearch {
    public static func matches(_ query: String, _ text: String) -> Bool {
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty else { return true }
        let hay = text.lowercased()
        return words.allSatisfy { hay.contains($0) }
    }

    /// The rows that match, in their order.
    public static func filter<T>(_ rows: [T], query: String, text: (T) -> String) -> [T] {
        rows.filter { matches(query, text($0)) }
    }
}

/// LAB-1571: "Active only" in the New session pickers. A project is active when Linear has it In Progress; an issue
/// when its state is a started one (In Progress, In Review).
public enum ActiveFilter {
    public static func project(_ state: String) -> Bool { state == "started" }
    public static func issue(_ stateType: String) -> Bool { stateType == "started" }
}

