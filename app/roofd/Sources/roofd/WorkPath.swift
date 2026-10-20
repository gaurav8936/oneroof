import Foundation

/// Where an agent is working, from a hook payload: the file a tool touches, the folder a shell command `cd`s into,
/// or the agent's own working folder. Sessions start at the workspace root, so this is how One Roof learns the repo
/// (owner 10-20: "Group by repo" put every session under ~/Projects).
enum WorkPath {
    static func from(hook payload: [String: Any]) -> String? {
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        for key in ["file_path", "notebook_path", "path"] {
            if let p = input[key] as? String, let a = absolute(p, base: payload["cwd"] as? String) { return a }
        }
        if let cmd = input["command"] as? String, let dir = cdTarget(cmd), let a = absolute(dir, base: payload["cwd"] as? String) {
            return a
        }
        return nil
    }

    /// `cd <dir> && …` (or `;`) at the start of a command.
    static func cdTarget(_ cmd: String) -> String? {
        let t = cmd.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("cd ") else { return nil }
        let rest = t.dropFirst(3).trimmingCharacters(in: .whitespaces)
        var dir = ""
        if let q = rest.first, q == "\"" || q == "'" {
            dir = String(rest.dropFirst().prefix { $0 != q })
        } else {
            dir = String(rest.prefix { !$0.isWhitespace && $0 != ";" && $0 != "&" })
        }
        return dir.isEmpty ? nil : dir
    }

    static func absolute(_ p: String, base: String?) -> String? {
        var s = p
        if s.hasPrefix("~/") { s = NSHomeDirectory() + String(s.dropFirst(1)) }
        if !s.hasPrefix("/") { guard let base else { return nil }; s = (base as NSString).appendingPathComponent(s) }
        return (s as NSString).standardizingPath
    }
}
