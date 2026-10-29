import Foundation

/// LAB-1524 · when a finished session's shell is closed by itself. A session is "finished" when its agent ended and the
/// shell it left (`claude …; exec zsh`) is still open. It is closed only when all of these hold:
///   the agent is gone · the shell is at its prompt (nothing running in it) · nobody touched it for `minutes` ·
///   it is not pinned · the setting is not "keep" (-1).
/// Closing ends the shell in roofd; the row stays, as history, and Resume works from the session catalog.
public enum FinishedShellPolicy {
    public static let choices: [(minutes: Int, label: String)] = [
        (-1, "Keep the shell"), (0, "Close it right away"), (10, "Close after 10 minutes"), (60, "Close after 1 hour"),
    ]
    /// LAB-1535 (owner rules, 10-29): exiting an agent closes its session after 10 minutes untouched.
    public static let defaultMinutes = 10

    /// LAB-1535: the line under a finished terminal — what happens next, and where the conversation lives.
    public static func endedLine(agent: AgentKind, minutes: Int) -> String {
        let when = minutes < 0 ? nil : minutes == 0 ? "This terminal closes in a moment." : "This terminal closes in \(minutes) minute\(minutes == 1 ? "" : "s")."
        let keep = agent == .claude ? "The conversation stays in All sessions (⌃⌘O), where you can resume it any time." : nil
        return (["\(agent.displayName) session ended."] + [when, keep].compactMap { $0 }).joined(separator: " ")
    }

    public static func shouldClose(finishedShell: Bool, liveAgent: Bool, pinned: Bool, atPrompt: Bool,
                                   lastActive: Date?, minutes: Int, now: Date = Date()) -> Bool {
        guard minutes >= 0, finishedShell, !liveAgent, !pinned, atPrompt else { return false }
        guard let last = lastActive else { return minutes == 0 }
        return now.timeIntervalSince(last) >= Double(minutes) * 60
    }

    /// At its prompt: every process in the terminal's foreground group is the shell itself (a running command — a dev
    /// server, a build — takes the foreground away from the shell).
    public static func atPrompt(shellPid: Int32?, foreground: [Int32]) -> Bool {
        guard let shellPid, !foreground.isEmpty else { return false }
        return foreground.allSatisfy { $0 == shellPid }
    }
}

/// LAB-1535 · housekeeping without asking (owner, 10-28): a running session nobody has touched for a day is closed by
/// itself — agent, shell and holder — because its conversation can always be resumed. Closing a window still only hides
/// it. A session is closed only when all of these hold:
///   untouched for `hours` · not working · not waiting for you (Needs you) · not pinned · not a loop round ·
///   an agent session can be resumed (a Claude session whose conversation id is saved; other agents wait for Resume) ·
///   a plain terminal is at its prompt (nothing runs in it).
public enum IdleSessionPolicy {
    public static let choices: [(hours: Int, label: String)] = [
        (-1, "Never"), (4, "4 hours"), (24, "24 hours"), (72, "3 days"),
    ]
    public static let defaultHours = 24

    public static func isLoop(_ tags: [String]) -> Bool { tags.contains { $0.hasPrefix("loop:") } }

    public static func shouldClose(running: Bool, status: SessionStatus, pinned: Bool, tags: [String], agent: AgentKind,
                                   conversationId: String?, atPrompt: Bool, lastActive: Date?, hours: Int,
                                   now: Date = Date()) -> Bool {
        guard hours >= 0, running, !pinned, !isLoop(tags), status != .running, status != .needsYou,
              let last = lastActive, now.timeIntervalSince(last) >= Double(hours) * 3600 else { return false }
        if agent.isAgent { return agent == .claude && conversationId != nil }
        return atPrompt
    }
}
