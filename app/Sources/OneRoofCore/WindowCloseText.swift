import Foundation

/// LAB-1485: what closing a window does, said with the window's real contents. The old text ("Its sessions keep running
/// in roofd") was the same for every window, named an internal program, and did not say how many sessions there were
/// or whether any agent was working. Closing a window never stops a session; it only hides them.
public enum WindowCloseText {
    public enum Kind: Sendable { case working, waiting, finishedShell, saved }
    public struct Row: Sendable {
        public let name: String
        public let kind: Kind
        public init(name: String, kind: Kind) { self.name = name; self.kind = kind }
    }

    /// The sheet's second line. `rows` are the window's sessions; `saved` ones are history (nothing runs for them).
    public static func detail(_ rows: [Row]) -> String {
        let running = rows.filter { $0.kind != .saved }
        let saved = rows.count - running.count
        let back = "Reopen the window from Window \u{25B8} Workspaces."
        guard !rows.isEmpty else { return "This window has no sessions. \(back)" }
        guard !running.isEmpty else {
            return "Nothing is running here: \(count(saved, "saved session")) \(saved == 1 ? "stays" : "stay") in the list. \(back)"
        }
        let working = running.filter { $0.kind == .working }.count
        let waiting = running.filter { $0.kind == .waiting }.count
        let shells = running.filter { $0.kind == .finishedShell }.count
        var parts: [String] = []
        if working > 0 { parts.append("\(count(working, "agent")) working") }
        if waiting > 0 { parts.append("\(count(waiting, "agent")) waiting for you") }
        if shells > 0 { parts.append("\(count(shells, "finished session")) (agent ended, shell still open)") }
        let names = running.sorted { rank($0.kind) < rank($1.kind) }.map(\.name)
        let shown = names.prefix(4).joined(separator: ", ") + (names.count > 4 ? " and \(names.count - 4) more" : "")
        var text = "\(count(running.count, "session")) keep running in the background: \(parts.joined(separator: ", ")). \(shown)."
        if saved > 0 { text += " \(count(saved, "saved session")) \(saved == 1 ? "stays" : "stay") in the list." }
        return text + " " + back
    }

    /// A row's kind from what the board knows: a live agent working or waiting, an agent that ended with its shell open,
    /// or a saved row with nothing running.
    public static func kind(liveAgent: Bool, endedShell: Bool, status: SessionStatus) -> Kind {
        if liveAgent { return status == .running ? .working : .waiting }
        return endedShell ? .finishedShell : .saved
    }

    private static func rank(_ k: Kind) -> Int { k == .working ? 0 : k == .waiting ? 1 : k == .finishedShell ? 2 : 3 }
    private static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
