import Foundation

/// "Explain this step" (LAB-259): a language model reads one step of a session's terminal and says what was asked,
/// what happened, what was decided and what could go wrong. The model is Claude Code run headless (`claude -p`, no
/// tools, nothing saved), on the session's own Claude account.
public struct StepExplanation: Equatable, Sendable {
    public var question: String
    public var happened: String
    public var decisions: String
    public var risks: String

    public init(question: String, happened: String, decisions: String, risks: String) {
        self.question = question; self.happened = happened; self.decisions = decisions; self.risks = risks
    }
}

public enum StepExplainer {
    public static let headings = ["Question", "What happened", "Decisions", "Risks"]
    /// The model and the most of a step it reads (the end is kept: that is where the outcome is).
    public static let model = "haiku"
    public static let maxChars = 24_000

    /// The command (run in a login shell, so the owner's PATH finds `claude`). The prompt goes on stdin.
    public static let command = "command claude -p --model \(model) --tools \"\" --no-session-persistence --strict-mcp-config --output-format text"

    public static func prompt(title: String, transcript: String) -> String {
        let body = transcript.count > maxChars ? "…\n" + String(transcript.suffix(maxChars)) : transcript
        return """
        Below is one step of a coding agent's terminal session (the owner's prompt, then what the agent did and said). \
        Explain it to the owner, briefly and plainly. Do not use tools.

        Step: \(title)

        <terminal>
        \(body)
        </terminal>

        Answer with exactly these four headings, in this order, each followed by one to four short lines \
        (bullets are fine). Write "None" when a section has nothing.
        ## Question
        (what the owner asked for, in your words)
        ## What happened
        (what the agent did: files, commands, results)
        ## Decisions
        (choices the agent made, and any it left to the owner)
        ## Risks
        (what could be wrong or break, and what to check)
        """
    }

    /// The four sections of the reply. Text before the first heading is ignored; a missing section is empty.
    /// Nil when the reply has none of the headings (an error message, say).
    public static func parse(_ reply: String) -> StepExplanation? {
        var sections: [String: [String]] = [:]
        var current: String?
        for raw in reply.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let bare = line.replacingOccurrences(of: #"^#+\s*|\*\*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #":$"#, with: "", options: .regularExpression)
            if line.hasPrefix("#") || line.hasPrefix("**"), let h = headings.first(where: { $0.caseInsensitiveCompare(bare) == .orderedSame }) {
                current = h; sections[h] = []
                continue
            }
            if let c = current { sections[c, default: []].append(raw) }
        }
        guard !sections.isEmpty else { return nil }
        func text(_ h: String) -> String { (sections[h] ?? []).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        return StepExplanation(question: text("Question"), happened: text("What happened"), decisions: text("Decisions"), risks: text("Risks"))
    }

    /// The lines of a step in a transcript, found by its title (the chapter list is rebuilt from a shorter window, so
    /// its line numbers do not fit a longer read). The last step with that title wins; nil when it is not there.
    public static func stepText(title: String, in transcript: String) -> String? {
        let lines = TerminalText.lines(transcript)
        guard let d = ChapterSplitter.drafts(transcript).last(where: { $0.title == title }) else { return nil }
        return lines[d.range.clamped(to: 0..<lines.count)].joined(separator: "\n")
    }

    /// How many lines above the bottom of the transcript a step starts (the rewind target); nil when not found.
    public static func linesFromBottom(title: String, in transcript: String) -> Int? {
        let lines = TerminalText.lines(transcript)
        guard let d = ChapterSplitter.drafts(transcript).last(where: { $0.title == title }) else { return nil }
        return max(0, lines.count - d.range.lowerBound)
    }
}
