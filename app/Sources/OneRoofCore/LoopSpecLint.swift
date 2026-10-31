import Foundation

/// Loop spec hygiene (LAB-1846): a loop's goal, check and round prompt are often copied out of an agent's terminal, and
/// the copy brings the box edge or prompt mark with it ("│ bash check.sh"), wrapping quotes, or a sentence explaining
/// the command. The check is then not a runnable command: every night it fails with exit 127 and the loop stops on
/// "the same failure twice". `clean` drops what a paste adds (on every save); `checkProblem` says why a check can't run
/// (the editor refuses to save it, roofd stops the run with that reason instead of failing twice).
public enum LoopSpecLint {
    /// What a copy from a terminal box or a shell prompt leaves at the start of a line. No command starts with these.
    static let pasteMarks: Set<Character> = ["│", "┃", "║", "╎", "┆", "┊", "|", ">", "❯", "›", "»", "$", "%", "⏺", "●", "•", "▸", "⎿", "└", "├"]
    static let quotePairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’")]
    static let scriptExtensions = ["sh", "bash", "zsh", "py", "rb", "js", "mjs", "ts", "swift", "pl"]

    /// The text without what a paste adds: leading box edges / prompt marks and one pair of wrapping quotes.
    public static func clean(_ text: String) -> String {
        var s = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        while let c = s.first, pasteMarks.contains(c) || isBoxDrawing(c) {
            s = s.dropFirst().drop(while: { $0 == " " || $0 == "\t" })
        }
        var out = String(s).trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in quotePairs where out.count >= 2 && out.first == open && out.last == close {
            let inner = out.dropFirst().dropLast()
            if !inner.contains(open) && !inner.contains(close) { out = String(inner).trimmingCharacters(in: .whitespacesAndNewlines) }
            break
        }
        return out
    }

    /// The loop with its goal, check and round prompt cleaned (the rest as it is).
    public static func cleaned(_ loop: Loop) -> Loop {
        var l = loop
        l.goal = clean(l.goal); l.check = clean(l.check); l.roundPrompt = clean(l.roundPrompt)
        return l
    }

    /// Why `check` can't run as a command, or nil. `folder` (the worktree, else the repo) lets it confirm that a script
    /// the check names is there; nil skips that part.
    public static func checkProblem(_ check: String, folder: String?) -> String? {
        let cmd = check.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return nil }
        if let c = cmd.first, pasteMarks.contains(c) || isBoxDrawing(c) {
            return "The check starts with “\(c)”, left by a copy from a terminal: start it with the command itself."
        }
        if let c = cmd.first(where: isBoxDrawing) {
            return "The check holds “\(c)”, a box edge from a terminal copy: remove it."
        }
        guard let script = scriptToken(cmd) else { return nil }
        if script.proseAfter {
            return "The check has a sentence after the command. Keep only the command; put the explanation in the goal."
        }
        if script.trailingStop {
            return "The check names “\(script.path).”: the full stop makes it a file that isn't there."
        }
        if let folder, !script.path.hasPrefix("$"), !script.path.hasPrefix("~") {
            let full = script.path.hasPrefix("/") ? script.path : (folder as NSString).appendingPathComponent(script.path)
            if !FileManager.default.fileExists(atPath: full) {
                return "The check runs \(script.path), which isn't in \((folder as NSString).abbreviatingWithTildeInPath)."
            }
        }
        return nil
    }

    /// The first word that names a script (`bash tools/x.sh`, `./x.py`), whether a full stop is glued to it, and
    /// whether a plain sentence follows it ("… x.sh. The script passes only when …").
    static func scriptToken(_ cmd: String) -> (path: String, trailingStop: Bool, proseAfter: Bool)? {
        let words = cmd.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        for (i, raw) in words.enumerated() {
            var w = raw, stop = false
            if w.hasSuffix(".") { w.removeLast(); stop = true }
            let ext = (w as NSString).pathExtension.lowercased()
            guard scriptExtensions.contains(ext), !w.hasPrefix("-") else { continue }
            let rest = words.dropFirst(i + 1)
            let prose = stop && rest.count >= 2 && (rest.first?.first?.isUppercase ?? false)
            return (w, stop, prose)
        }
        return nil
    }

    static func isBoxDrawing(_ c: Character) -> Bool {
        c.unicodeScalars.contains { (0x2500...0x257F).contains($0.value) }
    }
}
