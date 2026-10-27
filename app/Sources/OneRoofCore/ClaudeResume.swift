import Foundation

/// LAB-1362: resuming a Claude conversation after the CLI exited in a One Roof terminal. roofd runs an agent as
/// `claude …; exec zsh`, so the terminal (and Claude's last screen with its "claude --resume <id>" hint) lives on;
/// Resume types the command into that same terminal: same folder, account, environment and scrollback.
public enum ClaudeResume {
    private static let uuid = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"

    /// The conversation id from Claude's exit hint on the screen (the last one, if the terminal ran several).
    public static func sessionId(fromScreen text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: "claude\\s+(?:--resume|-r)\\s+(\(uuid))") else { return nil }
        let ms = re.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return ms.last.flatMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }

    /// The conversation id from its transcript, `<config>/projects/<folder>/<id>.jsonl`.
    public static func sessionId(transcriptPath path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        guard name.hasSuffix(".jsonl") else { return nil }
        let id = String(name.dropLast(6))
        return id.range(of: "^\(uuid)$", options: .regularExpression) != nil ? id : nil
    }

    /// `claude <launch args> --resume <id>`: the session's model and other arguments, without any conversation
    /// choice it was started with (`--resume`/`-r`, `--session-id` with their value; `--continue`/`-c`).
    public static func command(launchArgs: [String], sessionId: String) -> String {
        (["claude"] + args(launchArgs, sessionId: sessionId)).map(RoofdRuntime.shellQuote).joined(separator: " ")
    }

    /// The arguments alone (for a new launch when the terminal is gone).
    public static func args(_ launchArgs: [String], sessionId: String) -> [String] {
        var args: [String] = [], skip = false
        for a in launchArgs {
            if skip { skip = false; continue }
            if ["--resume", "-r", "--session-id"].contains(a) { skip = true; continue }
            if ["--continue", "-c"].contains(a) || a.hasPrefix("--resume=") || a.hasPrefix("--session-id=") { continue }
            args.append(a)
        }
        return args + ["--resume", sessionId]
    }
}
