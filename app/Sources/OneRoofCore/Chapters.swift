import Foundation

// Chapters (v2, S02 §1.3): the terminal stream folded into agent steps. A chapter starts at a user prompt or a plan
// step marker; it is a range over scrollback lines (a view, never a copy of the PTY), with a title, a one-line summary
// and how many tool calls it made.

public struct Chapter: Codable, Equatable, Sendable {
    public var index: Int
    public var title: String
    public var summary: String
    public var toolCalls: Int
    public var started: Date
    public var ended: Date?
    /// Scrollback line range [from, to).
    public var scrollbackRange: Range<Int>

    public init(index: Int, title: String, summary: String, toolCalls: Int, started: Date, ended: Date?, scrollbackRange: Range<Int>) {
        self.index = index; self.title = title; self.summary = summary; self.toolCalls = toolCalls
        self.started = started; self.ended = ended; self.scrollbackRange = scrollbackRange
    }

    public var isCurrent: Bool { ended == nil }
}

public enum ChapterSplitter {
    /// What a boundary line starts: the owner's prompt, or a plan step.
    public enum Boundary: Equatable, Sendable { case prompt(String), step(String) }

    /// A chapter's lines and words before times are known.
    public struct Draft: Equatable, Sendable {
        public var title: String
        public var summary: String
        public var toolCalls: Int
        public var range: Range<Int>
    }

    static let stepPattern = #"^(?:#+\s*)?(?:\*\*)?Step\s+(\d+)(?:\s+of\s+\d+)?\s*(?:[:.·—–-]\s*(.*))?$"#

    /// Is this line the start of a chapter? Prompts: Claude/Gemini `> text`, Codex `› text`, Kimi `✨ text` (not the
    /// empty input box); plan steps: "Step 2 of 4: Write tests", "## Step 3 — Ship".
    public static func boundary(_ raw: String) -> Boundary? {
        let s = TerminalText.unboxed(raw)
        for marker in ["> ", "› ", "❯ ", "✨ "] where s.hasPrefix(marker) {
            let text = s.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            // Option rows ("❯ 1. Yes") and the empty input box are not prompts.
            if text.isEmpty || text.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil { return nil }
            if raw.hasPrefix("    ") { return nil }   // quoted / tool output
            return .prompt(text)
        }
        if s.range(of: stepPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            let title = s.replacingOccurrences(of: #"^(?:#+\s*)?(?:\*\*)?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "**", with: "")
            return .step(title)
        }
        return nil
    }

    /// Split a transcript into chapter drafts. Text before the first boundary becomes "Start" if it has content.
    public static func drafts(_ text: String) -> [Draft] {
        let lines = TerminalText.lines(text)
        var starts: [(Int, String)] = []
        for (i, l) in lines.enumerated() {
            switch boundary(l) {
            case .prompt(let t)?: starts.append((i, t))
            case .step(let t)?: starts.append((i, t))
            case nil: break
            }
        }
        if starts.first?.0 != 0 {
            let head = lines[..<(starts.first?.0 ?? lines.count)]
            if head.contains(where: { !TerminalText.unboxed($0).isEmpty && !TerminalText.isChrome(TerminalText.unboxed($0)) }) {
                starts.insert((0, "Start"), at: 0)
            } else if let f = starts.first, f.0 > 0 {
                starts[0] = (0, f.1)   // fold leading blank lines into the first chapter
            }
        }
        return starts.enumerated().map { k, s in
            let end = k + 1 < starts.count ? starts[k + 1].0 : lines.count
            let body = Array(lines[s.0..<end])
            return Draft(title: CaptionEngine.clip(s.1, 60), summary: summary(body), toolCalls: CaptionEngine.toolCalls(in: body).filter { $0.kind != .todo }.count,
                         range: s.0..<end)
        }
    }

    /// The first line the agent said (or did) in the chapter, ≤ 90.
    static func summary(_ body: [String]) -> String {
        if let m = CaptionEngine.assistantMessages(in: Array(body.dropFirst())).first {
            return CaptionEngine.clip(CaptionEngine.sentences(m).first ?? m, 90)
        }
        if let c = CaptionEngine.toolCalls(in: body).first { return CaptionEngine.clip(CaptionEngine.describe(c).long, 90) }
        return ""
    }

    /// Chapters with times: known chapters keep their start; new ones start `now`; all but the last are ended
    /// (the last too when the session is finished).
    public static func chapters(_ text: String, previous: [Chapter] = [], sessionStarted: Date, now: Date = Date(), finished: Bool = false) -> [Chapter] {
        let ds = drafts(text)
        return ds.enumerated().map { i, d in
            let prev = previous.first { $0.index == i }
            let started = prev?.started ?? (i == 0 ? sessionStarted : now)
            let isLast = i == ds.count - 1
            let ended: Date? = isLast && !finished ? nil : (prev?.ended ?? now)
            return Chapter(index: i, title: d.title, summary: d.summary, toolCalls: d.toolCalls, started: started, ended: ended, scrollbackRange: d.range)
        }
    }

    /// The chapter holding scrollback line `line` (feed click → scroll target).
    public static func chapter(containing line: Int, in chapters: [Chapter]) -> Chapter? {
        chapters.first { $0.scrollbackRange.contains(line) }
    }
}
