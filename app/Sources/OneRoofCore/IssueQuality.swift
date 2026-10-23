import Foundation

// The issue quality bar (LAB-533). Every issue type has a few things it must say (non-negotiable) and a few that
// make it better (bonus). An issue missing any must-have is "not ready", with the list of what is missing.
// Pure and UI-free: the Pick issues panel and the plan panel's Ticket tab show it; the defect loop reuses it.
// The rubric in words: docs/help/13_issue-quality-bar.md (keep the two in step).

public enum IssueQuality {
    /// The rubric's five types (Linear Type labels: Bug · Deliverable · Task · Spike · Decision).
    public enum Kind: String, CaseIterable, Sendable {
        case bug, deliverable, task, spike, decision

        public var label: String {
            switch self {
            case .bug: return "Bug"
            case .deliverable: return "Deliverable"
            case .task: return "Task"
            case .spike: return "Spike"
            case .decision: return "Decision"
            }
        }

        /// From LinearIssue.type (WorkKind raw values: defect, chore, …) or a label name ("Bug", "type:defect").
        public init?(type: String?) {
            guard let t = type?.lowercased().replacingOccurrences(of: "type:", with: "") else { return nil }
            switch t {
            case "bug", "defect": self = .bug
            case "deliverable", "feature": self = .deliverable
            case "task", "chore": self = .task
            case "spike": self = .spike
            case "decision": self = .decision
            default: return nil
            }
        }
    }

    /// One line of the rubric.
    public struct Criterion: Equatable, Sendable {
        public var id: String
        /// What the "Missing: …" list says ("steps to reproduce").
        public var label: String
        public var required: Bool
    }

    public struct Report: Equatable, Sendable {
        public var kind: Kind?
        /// Must-haves the issue does not have (empty = ready).
        public var missing: [String]
        /// Bonus points it has, and the ones it could add.
        public var bonus: [String]
        public var missingBonus: [String]
        /// 0–100: must-haves are 80 points, bonus 20.
        public var score: Int

        public var ready: Bool { missing.isEmpty }
        /// "Missing: steps to reproduce, expected vs actual" — or "" when ready.
        public var missingLine: String { ready ? "" : "Missing: " + missing.joined(separator: ", ") }
        /// The badge's tooltip: what is missing, then what would add points.
        public var tooltip: String {
            var lines: [String] = []
            lines.append(ready ? "Meets the \(kind?.label ?? "issue") quality bar (\(score)/100)."
                               : "Not ready (\(score)/100). " + missingLine + ".")
            if !missingBonus.isEmpty { lines.append("Bonus if added: " + missingBonus.joined(separator: ", ") + ".") }
            return lines.joined(separator: "\n")
        }
    }

    /// The Pick issues panel's "Not ready" chip (a pseudo-state, like IssuePick.pickedFilter).
    public static let notReadyFilter = " not ready"

    // MARK: Rubric

    public static func rubric(_ kind: Kind) -> [Criterion] {
        func must(_ id: String, _ label: String) -> Criterion { Criterion(id: id, label: label, required: true) }
        func bonus(_ id: String, _ label: String) -> Criterion { Criterion(id: id, label: label, required: false) }
        switch kind {
        case .bug:
            return [must("steps", "steps to reproduce"), must("expectedActual", "expected vs actual"),
                    must("where", "where seen (version, build or screen)"),
                    bonus("screenshot", "screenshot"), bonus("fileLine", "file:line")]
        case .deliverable:
            return [must("outcome", "outcome"), must("doneWhen", "done when"), must("scope", "scope"),
                    bonus("screenshot", "mockup or screenshot"), bonus("fileLine", "file:line")]
        case .task:
            return [must("what", "what to do"), must("doneWhen", "done when"),
                    bonus("fileLine", "file:line"), bonus("link", "link to context")]
        case .spike:
            return [must("question", "question"), must("spikeOutcome", "outcome (what the answer will be)"),
                    bonus("timebox", "timebox"), bonus("link", "link to context")]
        case .decision:
            return [must("options", "options"), must("recommendation", "recommendation"),
                    bonus("context", "context (why now)"), bonus("tradeoffs", "trade-offs")]
        }
    }

    // MARK: Assess

    public static func assess(_ issue: LinearIssue) -> Report {
        assess(type: issue.type, title: issue.title, description: issue.description)
    }

    public static func assess(type: String?, title: String, description: String) -> Report {
        let doc = Doc(title: title, body: description)
        guard let kind = Kind(type: type) else {
            // No Type label: the bar cannot be applied, and that itself is the gap.
            var missing = ["a Type (Bug, Deliverable, Task, Spike or Decision)"]
            if doc.text.trimmingCharacters(in: .whitespacesAndNewlines).count < 20 { missing.append("a description") }
            return Report(kind: nil, missing: missing, bonus: [], missingBonus: [], score: missing.count == 1 ? 40 : 0)
        }
        let rubric = rubric(kind)
        var missing: [String] = [], bonus: [String] = [], missingBonus: [String] = []
        for c in rubric {
            let met = doc.meets(c.id, kind: kind)
            switch (c.required, met) {
            case (true, false): missing.append(c.label)
            case (false, true): bonus.append(c.label)
            case (false, false): missingBonus.append(c.label)
            default: break
            }
        }
        let req = rubric.filter(\.required).count, bon = rubric.count - req
        let score = Int((80 * Double(req - missing.count) / Double(max(req, 1))
                         + 20 * Double(bonus.count) / Double(max(bon, 1))).rounded())
        return Report(kind: kind, missing: missing, bonus: bonus, missingBonus: missingBonus, score: score)
    }

    // MARK: Detection

    /// The description, read for sections (Markdown headings, "**Label:**" or "Label:" lines) and phrases.
    struct Doc {
        let title: String
        let body: String
        /// Lower-cased body.
        let text: String
        /// Lower-cased heading-like lines, without their marks.
        let headings: [String]
        /// Lower-cased title + body, for phrases that can sit in either.
        let all: String

        init(title: String, body: String) {
            self.title = title
            self.body = body
            text = body.lowercased()
            all = (title + "\n" + body).lowercased()
            headings = body.components(separatedBy: .newlines).compactMap { raw in
                let l = raw.trimmingCharacters(in: .whitespaces)
                if l.hasPrefix("#") { return l.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces).lowercased() }
                let unbold = l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
                if let c = unbold.firstIndex(of: ":"), unbold.distance(from: unbold.startIndex, to: c) <= 40 {
                    return String(unbold[..<c]).trimmingCharacters(in: .whitespaces).lowercased()
                }
                return nil
            }
        }

        /// A heading starting with one of `names`, or one of `phrases` anywhere in the body.
        func section(_ names: [String], phrases: [String] = []) -> Bool {
            headings.contains { h in names.contains { h.hasPrefix($0) } } || phrases.contains { text.contains($0) }
        }

        func matches(_ pattern: String, in s: String? = nil) -> Bool {
            (s ?? body).range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }

        /// Two or more numbered or bulleted list items.
        var listItems: Int {
            body.components(separatedBy: .newlines).filter { matches(#"^\s*(\d+[.)]|[-*•])\s+\S"#, in: $0) }.count
        }
        var numberedItems: Int {
            body.components(separatedBy: .newlines).filter { matches(#"^\s*\d+[.)]\s+\S"#, in: $0) }.count
        }

        func meets(_ id: String, kind: Kind) -> Bool {
            switch id {
            case "steps":
                return section(["steps", "repro", "how to reproduce", "to reproduce"],
                               phrases: ["steps to reproduce", "to reproduce:", "repro steps", "reproduce:"]) || numberedItems >= 2
            case "expectedActual":
                let expected = section(["expected"], phrases: ["expected", "should "])
                let actual = section(["actual", "observed", "what happens", "result"],
                                     phrases: ["actual", "instead", "but got", "but it ", "observed", "what happens"])
                return expected && actual
            case "where":
                return section(["where", "version", "build", "environment", "seen in", "seen on", "env"],
                               phrases: ["version", "seen in", "seen on", "build ", "macos", " screen", " panel", " sheet", " window", "settings ›", " › "])
                    || matches(#"\b\d+\.\d+(\.\d+)+\b"#)
            case "screenshot":
                return matches(#"!\[[^\]]*\]\([^)]+\)"#) || text.contains("uploads.linear.app")
                    || matches(#"\.(png|jpe?g|gif|heic|mov|mp4)\b"#)
            case "fileLine":
                return matches(#"[A-Za-z0-9_\-./]+\.[A-Za-z]{1,6}:\d+"#)
            case "outcome":
                return section(["outcome", "goal", "why", "problem", "objective", "result", "what"],
                               phrases: ["so that", "outcome", "the goal", "owner can", "user can", "you can now"])
            case "doneWhen":
                return section(["done when", "done-when", "acceptance", "definition of done", "done"],
                               phrases: ["done when", "done-when", "acceptance criteria", "definition of done", "- [ ]", "* [ ]"])
            case "scope":
                return section(["scope", "in scope", "out of scope", "non-goals", "includes", "deliverables"],
                               phrases: ["scope", "non-goal", "not included", "out of scope"])
            case "what":
                let words = body.split { $0.isWhitespace || $0.isNewline }.count
                return words >= 8 || listItems >= 2
            case "question":
                return section(["question", "questions", "open question"],
                               phrases: ["question", "find out", "can we", "should we", "how do", "whether"])
                    || all.contains("?")
            case "spikeOutcome":
                return section(["outcome", "deliverable", "output", "answer", "result", "done when", "done"],
                               phrases: ["outcome", "write-up", "writeup", "recommendation", "report back", "deliver", "done when", "answer"])
            case "timebox":
                return section(["timebox", "time-box", "time box", "budget"],
                               phrases: ["timebox", "time-box", "time box"])
                    || matches(#"\b\d+\s*(h|hrs?|hours?|days?|d)\b"#)
            case "link":
                return matches(#"https?://"#) || matches(#"\b[A-Z]{2,6}-\d+\b"#) || matches(#"[A-Za-z0-9_\-./]+\.[A-Za-z]{1,6}:\d+"#)
            case "options":
                return section(["options", "option", "alternatives", "choices"],
                               phrases: ["option a", "option 1", "option b", "option 2", "alternatives", " vs ", " vs. ", " versus "])
            case "recommendation":
                return section(["recommendation", "recommended", "proposal", "proposed", "decision"],
                               phrases: ["recommend", "propose", "suggest", "we should", "go with"])
            case "context":
                return section(["context", "background", "why now", "why", "problem"],
                               phrases: ["context", "background", "because", "why now"])
            case "tradeoffs":
                return section(["trade-offs", "tradeoffs", "trade offs", "pros", "cons", "consequences", "risks"],
                               phrases: ["trade-off", "tradeoff", "pros", "cons", "downside", "consequence", "risk"])
            default:
                return false
            }
        }
    }
}
