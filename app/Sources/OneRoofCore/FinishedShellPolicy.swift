import Foundation

/// LAB-1524 · when a finished session's shell is closed by itself. A session is "finished" when its agent ended and the
/// shell it left (`claude …; exec zsh`) is still open. It is closed only when all of these hold:
///   the agent is gone · the shell is at its prompt (nothing running in it) · nobody touched it for `minutes` ·
///   it is not pinned · the setting is not "keep" (-1).
/// Closing ends the shell in roofd; the row stays, as history, and Resume works from the session catalog.
public enum FinishedShellPolicy {
    public static let choices: [(minutes: Int, label: String)] = [
        (-1, "Keep the shell"), (0, "Close it right away"), (15, "Close after 15 minutes"),
        (60, "Close after 1 hour"), (240, "Close after 4 hours"),
    ]

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
