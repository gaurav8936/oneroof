import Foundation

/// LAB-861: what a terminal pane's keystrokes go to. When the pane's foreground process group is not its shell (and
/// not the agent the session shows), the pane header says "running: <command>" with a Stop button, so typing into a
/// tab that still runs a local web server is not a surprise.
public enum ForegroundProgram {
    /// Process names that are a shell waiting at its prompt.
    public static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu", "login", "-zsh", "-bash", "-sh"]

    /// The command to show, or nil when typing goes where the owner expects: the shell's prompt, the session's own
    /// agent (`agentShown`: an agent session, or a terminal in which the owner started one), or nothing known.
    public static func label(_ p: RuntimeProcesses, agentShown: Bool) -> String? {
        let fg = p.foreground.sorted { $0.pid < $1.pid }
        guard !fg.isEmpty else { return nil }
        if let shell = p.shellPid, fg.contains(where: { $0.pid == shell }) { return nil }
        if fg.allSatisfy({ shells.contains(name($0)) }) { return nil }
        if agentShown, fg.contains(where: isAgent) { return nil }
        // The group's leader started first (lowest pid): "npm run dev", not the node child it spawned.
        guard let lead = fg.first(where: { !shells.contains(name($0)) }) else { return nil }
        return command(lead)
    }

    /// A process's short name: its executable's last path component.
    static func name(_ p: RuntimeProcesses.Proc) -> String {
        let n = p.name ?? p.argv.first ?? ""
        return (n as NSString).lastPathComponent.lowercased()
    }

    /// claude / codex / gemini / kimi / agy, also when run by node, bun or python.
    static func isAgent(_ p: RuntimeProcesses.Proc) -> Bool {
        let agents = AgentKind.allCases.filter(\.isAgent).map(\.cliName)
        if agents.contains(name(p)) { return true }
        return p.argv.prefix(3).contains { a in agents.contains((a as NSString).lastPathComponent.lowercased()) }
    }

    /// "npm run dev" from the argv (program name without its folder), at most `max` characters.
    public static func command(_ p: RuntimeProcesses.Proc, max: Int = 48) -> String {
        var parts = p.argv
        if parts.isEmpty { parts = [p.name ?? "?"] }
        parts[0] = (parts[0] as NSString).lastPathComponent
        let s = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return s.count > max ? String(s.prefix(max - 1)) + "…" : s
    }
}
