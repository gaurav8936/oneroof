import Foundation

// The caption engine (v2, ENGINES §1): one plain line per session saying what its agent is doing right now.
// The heuristic is always computed first and shown at once; the on-device model (D5) may replace it later, but only
// with valid JSON inside the limits. No caption is ever invented: nothing to say → nil → the UI says "no caption yet".

/// Where a caption came from; shown in the tooltip ("caption by on-device model" / "from the terminal").
public enum CaptionSource: String, Codable, CaseIterable, Sendable {
    case model, heuristic, agentTitle

    public var tooltip: String {
        switch self {
        case .model: return "caption by on-device model"
        case .heuristic: return "from the terminal"
        case .agentTitle: return "the agent's own title"
        }
    }
}

public struct Caption: Codable, Equatable, Sendable {
    public static let maxText = 72
    public static let maxNow = 90
    /// LAB-1385: a step count larger than this is not a plan (the on-device model once wrote 1,000,000,000,000,000
    /// steps; the Plan panel's step list asked for that many rows and the app aborted on launch, exit 6).
    public static let maxSteps = 50

    public var text: String
    public var step: Int?
    public var steps: Int?
    /// The single action in progress, e.g. "Running swift test --filter CaptionTests".
    public var now: String?
    public var updatedAt: Date
    public var source: CaptionSource

    public init(text: String, step: Int? = nil, steps: Int? = nil, now: String? = nil, updatedAt: Date = Date(), source: CaptionSource = .heuristic) {
        // LAB-1385: keep a step count only when it is a real plan (1…maxSteps) and a step only inside it. Every caption,
        // including one loaded from the store, comes through here, so a bad stored row heals on load.
        let n = steps.flatMap { (1...Caption.maxSteps).contains($0) ? $0 : nil }
        self.text = text; self.steps = n; self.now = now; self.updatedAt = updatedAt; self.source = source
        self.step = step.flatMap { s in s >= 1 && s <= (n ?? Caption.maxSteps) ? s : nil }
    }
}

/// One tool call read from an agent's terminal (Claude `● Edit(path)`, Codex `• Ran cmd`, Kimi `Used Shell (cmd)`,
/// Gemini `✔ ReadFile path`).
public struct ToolCall: Equatable, Sendable {
    public enum Kind: String, Sendable { case edit, bash, read, task, search, web, todo, other }
    public var kind: Kind
    /// The tool's own name as printed ("Update", "Ran", "Shell").
    public var tool: String
    public var argument: String
    /// Line index in the text it was read from.
    public var line: Int

    public init(kind: Kind, tool: String, argument: String, line: Int) {
        self.kind = kind; self.tool = tool; self.argument = argument; self.line = line
    }

    /// For file tools: the path argument without `file_path:` labels or quotes.
    public var path: String {
        var a = argument
        for label in ["file_path:", "path:", "notebook_path:"] where a.hasPrefix(label) { a = String(a.dropFirst(label.count)) }
        if let comma = a.range(of: ", ") { a = String(a[..<comma.lowerBound]) }
        return a.trimmingCharacters(in: CharacterSet(charactersIn: " \"'`"))
    }

    public var fileName: String { (path as NSString).lastPathComponent }
}

/// The plan a session is working through (objective step agents, or a plan the agent printed).
public struct CaptionPlan: Equatable, Sendable {
    public var titles: [String]
    /// 1-based current step.
    public var current: Int
    public init(titles: [String], current: Int) { self.titles = titles; self.current = current }
    public var currentTitle: String? { titles.indices.contains(current - 1) ? titles[current - 1] : nil }
}

/// Everything the engine reads for one session.
public struct CaptionInput: Sendable {
    /// Visible terminal text since the last caption (the engine keeps only the last 6,000 characters).
    public var text: String
    public var agent: AgentKind
    public var status: SessionStatus
    public var objective: String
    public var plan: CaptionPlan?
    /// Set when the session is scheduled rather than started (planned/next with a schedule).
    public var schedule: Schedule?
    public var lastScheduledResult: String?
    /// Last time anything happened in the session (for "Idle 12m").
    public var lastActivity: Date?
    public var now: Date

    public init(text: String, agent: AgentKind = .claude, status: SessionStatus, objective: String = "", plan: CaptionPlan? = nil,
                schedule: Schedule? = nil, lastScheduledResult: String? = nil, lastActivity: Date? = nil, now: Date = Date()) {
        self.text = String(text.suffix(CaptionEngine.maxInput))
        self.agent = agent; self.status = status; self.objective = objective; self.plan = plan; self.schedule = schedule
        self.lastScheduledResult = lastScheduledResult; self.lastActivity = lastActivity; self.now = now
    }
}

public enum CaptionEngine {
    public static let maxInput = 6_000

    // MARK: Heuristic

    /// The deterministic caption, or nil when there is nothing true to say yet.
    public static func heuristic(_ input: CaptionInput) -> Caption? {
        let lines = TerminalText.lines(input.text)
        let calls = toolCalls(in: lines)
        let action = calls.last(where: { $0.kind != .todo }).map(describe)
        let step = input.plan?.current
        let steps = input.plan?.titles.count
        func make(_ text: String, now: String? = nil) -> Caption {
            Caption(text: clip(text, Caption.maxText), step: step, steps: steps, now: now.map { clip($0, Caption.maxNow) },
                    updatedAt: input.now, source: .heuristic)
        }

        if let s = input.schedule, [.planned, .next].contains(input.status) {
            var t = s.captionPrefix
            if let r = input.lastScheduledResult, !r.isEmpty { t += " · last night " + r }
            return make(t)
        }

        switch input.status {
        case .needsYou:
            if let m = DecisionMatcher.match(input.text, agent: input.agent) {
                let what = m.command.map { "run " + firstLine($0) } ?? m.question
                return make("Needs you · " + what, now: m.question)
            }
            if let q = lines.last(where: { $0.hasSuffix("?") }) { return make("Needs you · " + q) }
            return make("Needs you")
        case .done:
            // LAB-241: the same word as the status everywhere else (Ready = finished a turn you haven't looked at).
            if let s = lastAssistantSentence(in: lines) { return make("Ready · " + clip(s, 60)) }
            return make("Ready")
        case .idle:
            let age = input.lastActivity.map { " " + ageText(input.now.timeIntervalSince($0)) } ?? ""
            if let last = calls.last(where: { $0.kind == .bash }) {
                return make("Idle\(age) · last: " + firstLine(last.argument))
            }
            return age.isEmpty && calls.isEmpty ? nil : make("Idle" + age)
        case .running:
            var text: String
            if let p = input.plan, let title = p.currentTitle {
                text = "Step \(p.current) of \(p.titles.count) · \(title)"
            } else if let a = action {
                text = a.short
            } else {
                return nil
            }
            if let t = testCounts(in: lines) {
                let suffix = " · tests \(t.passed)/\(t.total)"
                text = clip(text, Caption.maxText - suffix.count) + suffix
            }
            return make(text, now: action?.long)
        case .exited:
            return make("Exited")
        case .planned, .next, .doNotUse:
            return nil
        }
    }

    /// Caption words for a tool call: short form for the caption, long form for `now`.
    static func describe(_ c: ToolCall) -> (short: String, long: String) {
        switch c.kind {
        case .edit: return ("Editing " + c.fileName, "Editing " + c.path)
        case .read: return ("Reading " + c.fileName, "Reading " + c.path)
        case .bash:
            let cmd = mainCommand(c.argument)
            return ("Running " + (cmd.split(separator: " ").first.map(String.init) ?? cmd), "Running " + cmd)
        case .task: return ("Waiting on subagent " + c.argument, "Waiting on subagent " + c.argument)
        case .search: return ("Searching the code", "Searching " + c.argument)
        case .web: return ("Reading the web", "Fetching " + c.argument)
        case .todo, .other: return (c.tool, c.tool + " " + c.argument)
        }
    }

    /// The command that matters in `cd app && FOO=1 swift test`: the last `&&` part, without env assignments.
    public static func mainCommand(_ cmd: String) -> String {
        let first = firstLine(cmd)
        let parts = first.components(separatedBy: "&&").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let useful = parts.last(where: { !$0.hasPrefix("cd ") }) ?? parts.last ?? first
        let words = useful.split(separator: " ").drop { $0.contains("=") && !$0.hasPrefix("-") }
        return words.joined(separator: " ")
    }

    // MARK: Parsing the terminal

    static let claudeTools: [String: ToolCall.Kind] = [
        "Edit": .edit, "Update": .edit, "MultiEdit": .edit, "Write": .edit, "Create": .edit, "NotebookEdit": .edit,
        "Bash": .bash, "Read": .read, "Task": .task, "Agent": .task, "Grep": .search, "Glob": .search, "Search": .search,
        "List": .read, "WebFetch": .web, "Fetch": .web, "WebSearch": .web, "TodoWrite": .todo, "Update Todos": .todo,
    ]
    static let codexVerbs: [String: ToolCall.Kind] = [
        "Ran": .bash, "Running": .bash, "Edited": .edit, "Editing": .edit, "Added": .edit, "Deleted": .edit,
        "Read": .read, "Reading": .read, "Searched": .search, "Search": .search, "List": .read, "Listed": .read,
    ]
    static let kimiTools: [String: ToolCall.Kind] = [
        "Shell": .bash, "Bash": .bash, "ReadFile": .read, "WriteFile": .edit, "StrReplaceFile": .edit, "PatchFile": .edit,
        "Task": .task, "Glob": .search, "Grep": .search, "SearchWeb": .web, "FetchURL": .web, "SetTodoList": .todo,
    ]
    static let geminiTools: [String: ToolCall.Kind] = [
        "Shell": .bash, "ReadFile": .read, "ReadManyFiles": .read, "ReadFolder": .read, "WriteFile": .edit, "Edit": .edit,
        "Replace": .edit, "FindFiles": .search, "SearchText": .search, "GoogleSearch": .web, "WebFetch": .web,
    ]

    public static func toolCalls(in text: String) -> [ToolCall] { toolCalls(in: TerminalText.lines(text)) }

    public static func toolCalls(in lines: [String]) -> [ToolCall] {
        lines.enumerated().compactMap { toolCall($0.element, line: $0.offset) }
    }

    /// One line → a tool call, for any of the four CLI styles.
    public static func toolCall(_ raw: String, line: Int = 0) -> ToolCall? {
        let s = TerminalText.unboxed(raw)
        guard let first = s.unicodeScalars.first else { return nil }
        // Claude: ● Edit(path) / ⏺ Bash(swift test)
        if first == "●" || first == "⏺" {
            let body = s.dropFirst().trimmingCharacters(in: .whitespaces)
            if let paren = body.firstIndex(of: "(") {
                let name = String(body[..<paren]).trimmingCharacters(in: .whitespaces)
                if let kind = claudeTools[name] {
                    var arg = String(body[body.index(after: paren)...])
                    if arg.hasSuffix(")") { arg.removeLast() }
                    return ToolCall(kind: kind, tool: name, argument: arg.trimmingCharacters(in: .whitespaces), line: line)
                }
            }
        }
        // Kimi: • Used Shell (swift test)
        if let r = s.range(of: #"^(?:[•●]\s*)?Used\s+([A-Za-z]+)\s*\((.*)\)\s*$"#, options: .regularExpression) {
            let m = String(s[r]).replacingOccurrences(of: #"^(?:[•●]\s*)?Used\s+"#, with: "", options: .regularExpression)
            if let paren = m.firstIndex(of: "(") {
                let name = m[..<paren].trimmingCharacters(in: .whitespaces)
                var arg = String(m[m.index(after: paren)...]); if arg.hasSuffix(")") { arg.removeLast() }
                return ToolCall(kind: kimiTools[name] ?? .other, tool: name, argument: arg, line: line)
            }
        }
        // Codex: • Ran swift test / • Edited Sources/a.swift (+3 -1) / └ Read a.swift
        if first == "•" || first == "└" {
            let body = s.dropFirst().trimmingCharacters(in: .whitespaces)
            let verb = body.prefix { !$0.isWhitespace }
            if let kind = codexVerbs[String(verb)] {
                var arg = body.dropFirst(verb.count).trimmingCharacters(in: .whitespaces)
                arg = arg.replacingOccurrences(of: #"\s*\(\+\d+ -\d+\)$"#, with: "", options: .regularExpression)
                if !arg.isEmpty { return ToolCall(kind: kind, tool: String(verb), argument: arg, line: line) }
            }
        }
        // Gemini: ✔ Shell swift test (Run tests)
        if first == "✔" || first == "✓" || first == "⊷" {
            let body = s.dropFirst().trimmingCharacters(in: .whitespaces)
            let name = body.prefix { !$0.isWhitespace }
            if let kind = geminiTools[String(name)] {
                var arg = body.dropFirst(name.count).trimmingCharacters(in: .whitespaces)
                arg = arg.replacingOccurrences(of: #"\s+\([^()]*\)$"#, with: "", options: .regularExpression)
                return ToolCall(kind: kind, tool: String(name), argument: arg, line: line)
            }
        }
        return nil
    }

    /// The latest test summary in the text: (passed, total). XCTest, Swift Testing, pytest, jest/vitest, cargo.
    public static func testCounts(in text: String) -> (passed: Int, total: Int)? { testCounts(in: TerminalText.lines(text)) }

    public static func testCounts(in lines: [String]) -> (passed: Int, total: Int)? {
        for l in lines.reversed() {
            if let n = int(l, #"Executed (\d+) tests?, with (\d+) failures?"#, group: 1),
               let f = int(l, #"Executed \d+ tests?, with (\d+) failures?"#, group: 1) {
                return (n - f, n)
            }
            guard let passed = int(l, #"(\d+) (?:tests? )?(?:in \d+ suites? )?passed"#, group: 1)
                    ?? int(l, #"Tests? +(\d+) passed"#, group: 1) else { continue }
            let failed = int(l, #"(\d+) (?:tests? )?failed"#, group: 1) ?? 0
            let total = int(l, #"(\d+) total"#, group: 1) ?? int(l, #"passed \((\d+)\)"#, group: 1) ?? passed + failed
            return (passed, max(total, passed))
        }
        return nil
    }

    static func int(_ s: String, _ pattern: String, group: Int) -> Int? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > group,
              let r = Range(m.range(at: group), in: s) else { return nil }
        return Int(s[r])
    }

    /// Assistant prose (not tool calls, not tool output), one string per message, oldest first.
    /// Messages start with ● ⏺ (Claude), • (Codex, Kimi) or ✦ (Gemini); indented lines continue them.
    public static func assistantMessages(in lines: [String]) -> [String] {
        var out: [String] = []
        var cur: [String]? = nil
        func flush() { if let c = cur, !c.isEmpty { out.append(c.joined(separator: " ")) }; cur = nil }
        for raw in lines {
            let s = TerminalText.unboxed(raw)
            if s.isEmpty { flush(); continue }
            if let f = s.unicodeScalars.first, "●⏺•✦".unicodeScalars.contains(f) {
                flush()
                if toolCall(raw) != nil { continue }
                let body = s.dropFirst().trimmingCharacters(in: .whitespaces)
                if body.hasPrefix("Updated Plan") || body.hasPrefix("Explored") || body.isEmpty { continue }
                cur = [body]
            } else if cur != nil, raw.hasPrefix("  "), !s.hasPrefix("⎿"), !s.hasPrefix("└"), !TerminalText.isChrome(s) {
                cur?.append(s)
            } else {
                flush()
            }
        }
        flush()
        return out
    }

    public static func lastAssistantText(in text: String) -> String? { assistantMessages(in: TerminalText.lines(text)).last }

    static func lastAssistantSentence(in lines: [String]) -> String? {
        guard let m = assistantMessages(in: lines).last else { return nil }
        return sentences(m).last
    }

    /// Split prose into sentences on . ! ? followed by a space.
    public static func sentences(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            cur.append(ch)
            if ".!?".contains(ch), i + 1 == chars.count || chars[i + 1] == " " {
                let t = cur.trimmingCharacters(in: .whitespaces); if !t.isEmpty { out.append(t) }; cur = ""
            }
        }
        let t = cur.trimmingCharacters(in: .whitespaces); if !t.isEmpty { out.append(t) }
        return out
    }

    // MARK: Model path (optional, D5)

    public static let systemPrompt = "You summarise a coding agent's terminal for its owner. Reply JSON {caption, step, steps, now, events:[{kind,text}]}. caption: what it is doing, ≤ 72 chars, present tense, no filler. now: the single action in progress. events only for: a step finished, a finding, a choice the agent made, subagents started, done, rotated, error. Never invent numbers not in the text."

    /// The user message: status, objective, plan, the last 20 tool calls and the terminal tail.
    public static func userPrompt(_ input: CaptionInput) -> String {
        let lines = TerminalText.lines(input.text)
        var p = "Agent: \(input.agent.displayName)\nStatus: \(input.status.label)\n"
        if !input.objective.isEmpty { p += "Objective: \(input.objective)\n" }
        if let plan = input.plan {
            p += "Plan (current step \(plan.current) of \(plan.titles.count)):\n"
            for (i, t) in plan.titles.enumerated() { p += "\(i + 1). \(t)\n" }
        }
        let calls = toolCalls(in: lines).suffix(20)
        if !calls.isEmpty { p += "Recent tool calls:\n" + calls.map { "\($0.tool)(\($0.argument))" }.joined(separator: "\n") + "\n" }
        p += "Terminal (latest last):\n" + input.text
        return p
    }

    /// The reply's shape as a JSON schema (LAB-674): with plain `json_object`, Qwen3 sometimes sent `steps` as a list
    /// and Arch-Router an empty object; held to this schema both answer in the shape `ModelReply` decodes.
    public static let replySchema: [String: Any] = [
        "type": "object",
        "properties": [
            "caption": ["type": "string"], "step": ["type": "integer"], "steps": ["type": "integer"], "now": ["type": "string"],
            "events": ["type": "array", "items": ["type": "object", "properties": ["kind": ["type": "string"], "text": ["type": "string"]],
                                                  "required": ["kind", "text"]]],
        ],
        "required": ["caption"],
    ]

    /// A llama-server `/v1/chat/completions` body. Qwen3's thinking is off (else the reply is empty); other models
    /// ignore the field.
    public static func requestBody(_ input: CaptionInput, maxTokens: Int = 200) -> Data {
        let body: [String: Any] = [
            "messages": [["role": "system", "content": systemPrompt], ["role": "user", "content": userPrompt(input)]],
            "temperature": 0, "max_tokens": maxTokens,
            "response_format": ["type": "json_schema", "json_schema": ["name": "caption", "schema": replySchema]],
            "chat_template_kwargs": ["enable_thinking": false],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    public struct ModelReply: Codable, Equatable, Sendable {
        public struct Event: Codable, Equatable, Sendable { public var kind: String; public var text: String }
        public var caption: String
        public var step: Int?
        public var steps: Int?
        public var now: String?
        public var events: [Event]?
    }

    /// The model's JSON reply (fences and chatter around it allowed), or nil when it isn't a valid object.
    public static func parseModelReply(_ raw: String) -> ModelReply? {
        guard let open = raw.firstIndex(of: "{"), let close = raw.lastIndex(of: "}"), open < close else { return nil }
        return try? JSONDecoder().decode(ModelReply.self, from: Data(raw[open...close].utf8))
    }

    /// Why a reply is rejected, or nil when it may replace the heuristic.
    public static func validationError(_ r: ModelReply, input: CaptionInput) -> String? {
        let cap = r.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if cap.isEmpty { return "empty caption" }
        if cap.count > Caption.maxText { return "caption longer than \(Caption.maxText)" }
        if let n = r.now, n.count > Caption.maxNow { return "now longer than \(Caption.maxNow)" }
        if let s = r.step, s < 1 { return "step below 1" }
        if let t = r.steps, t < 1 || t > Caption.maxSteps { return "steps outside 1…\(Caption.maxSteps)" }   // LAB-1385
        if let s = r.step, let t = r.steps, s > t { return "step beyond steps" }
        if let plan = input.plan, let t = r.steps, t != plan.titles.count { return "steps differ from the plan" }
        var known = Set(numbers(in: input.text) + numbers(in: input.objective))
        if let plan = input.plan { known.formUnion(["\(plan.current)", "\(plan.titles.count)"]); plan.titles.forEach { known.formUnion(numbers(in: $0)) } }
        for n in numbers(in: cap) + numbers(in: r.now ?? "") where !known.contains(n) { return "invented number \(n)" }
        return nil
    }

    static func numbers(in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\d+"#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    /// The caption to show: the model's when its reply is valid, else the heuristic. Feed events only from a valid reply.
    public static func resolve(heuristic: Caption?, modelReply raw: String?, input: CaptionInput, sessionId: String) -> (caption: Caption?, events: [FeedEvent]) {
        guard let raw, let r = parseModelReply(raw), validationError(r, input: input) == nil else { return (heuristic, []) }
        let cap = Caption(text: r.caption.trimmingCharacters(in: .whitespacesAndNewlines), step: r.step ?? input.plan?.current,
                          steps: r.steps ?? input.plan?.titles.count, now: r.now?.trimmingCharacters(in: .whitespacesAndNewlines),
                          updatedAt: input.now, source: .model)
        let events = (r.events ?? []).compactMap { e -> FeedEvent? in
            guard let k = FeedKind(modelName: e.kind), !e.text.isEmpty else { return nil }
            return FeedEvent(at: input.now, sessionId: sessionId, kind: k, text: clip(e.text, 120))
        }
        return (cap, events)
    }

    // MARK: Helpers

    public static func clip(_ s: String, _ n: Int) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count <= n ? t : String(t.prefix(max(0, n - 1))).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func firstLine(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: true).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? s
    }

    /// "<1m", "12m", "3h", "2d".
    public static func ageText(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "<1m" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }
}

/// Terminal text helpers shared by the engines.
public enum TerminalText {
    /// Lines with ANSI escapes and trailing spaces removed.
    public static func lines(_ text: String) -> [String] {
        let clean = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return clean.components(separatedBy: "\n").map { l in
            var s = l; while s.last == " " { s.removeLast() }; return s
        }
    }

    /// A line without a TUI box around it ("│ text │" → "text"), trimmed.
    public static func unboxed(_ line: String) -> String {
        var s = line.trimmingCharacters(in: .whitespaces)
        while let f = s.first, "│┃▌".contains(f) { s.removeFirst(); s = s.trimmingCharacters(in: .whitespaces) }
        while let l = s.last, "│┃".contains(l) { s.removeLast(); s = s.trimmingCharacters(in: .whitespaces) }
        return s
    }

    /// Box borders, separators and the CLI's own status chrome.
    public static func isChrome(_ s: String) -> Bool {
        guard let f = s.unicodeScalars.first else { return true }
        if "╭╰─━┌└╮╯".unicodeScalars.contains(f), s.unicodeScalars.allSatisfy({ "╭╰─━┌└╮╯┐┘ ".unicodeScalars.contains($0) }) { return true }
        return s.contains("? for shortcuts") || s.hasPrefix("esc to interrupt") || s.contains("⏵⏵")
    }
}

// MARK: - Scheduling model calls

/// Fair, clock-injected throttle for caption updates: debounce 2 s after new output, at most once per 5 s per session,
/// immediately on a status change, at most 2 in flight, round-robin across sessions so a chatty one can't starve the rest.
public struct CaptionScheduler: Sendable {
    public var debounce: TimeInterval
    public var minInterval: TimeInterval
    public var maxConcurrent: Int

    struct Entry: Sendable {
        var lastOutput: Date?
        var urgent = false
        var lastRun: Date?
        var inFlight = false
        var pending: Bool { lastOutput != nil || urgent }
    }
    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private var cursor = 0

    public init(debounce: TimeInterval = 2, minInterval: TimeInterval = 5, maxConcurrent: Int = 2) {
        self.debounce = debounce; self.minInterval = minInterval; self.maxConcurrent = maxConcurrent
    }

    private mutating func touch(_ id: String) {
        if entries[id] == nil { entries[id] = Entry(); order.append(id) }
    }

    public mutating func noteOutput(_ id: String, at: Date) { touch(id); entries[id]?.lastOutput = at }
    public mutating func noteStatusChange(_ id: String, at: Date) { touch(id); entries[id]?.urgent = true; entries[id]?.lastOutput = at }

    public mutating func remove(_ id: String) {
        entries[id] = nil
        if let i = order.firstIndex(of: id) { order.remove(at: i); if cursor > i { cursor -= 1 } }
        if cursor >= order.count { cursor = 0 }
    }

    public var inFlightCount: Int { entries.values.filter(\.inFlight).count }

    public func isDue(_ id: String, now: Date) -> Bool {
        guard let e = entries[id], !e.inFlight, e.pending else { return false }
        if e.urgent { return true }
        let quiet = e.lastOutput.map { now.timeIntervalSince($0) >= debounce } ?? true
        let throttled = e.lastRun.map { now.timeIntervalSince($0) < minInterval } ?? false
        return quiet && !throttled
    }

    /// Sessions to caption now, in fair order; they count as in flight until `finish`.
    public mutating func take(now: Date) -> [String] {
        var slots = maxConcurrent - inFlightCount
        guard slots > 0, !order.isEmpty else { return [] }
        var picked: [String] = []
        let n = order.count
        var lastPicked: Int?
        for k in 0..<n where slots > 0 {
            let i = (cursor + k) % n
            let id = order[i]
            guard isDue(id, now: now) else { continue }
            entries[id]?.inFlight = true
            entries[id]?.urgent = false
            entries[id]?.lastOutput = nil
            entries[id]?.lastRun = now
            picked.append(id); slots -= 1; lastPicked = i
        }
        if let l = lastPicked { cursor = (l + 1) % n }
        return picked
    }

    public mutating func finish(_ id: String) { entries[id]?.inFlight = false }

    /// When the next session becomes due (for the timer), or nil when nothing is pending.
    public func nextWake(now: Date) -> Date? {
        entries.values.filter { !$0.inFlight && $0.pending }.map { e -> Date in
            if e.urgent { return now }
            let a = e.lastOutput.map { $0.addingTimeInterval(debounce) } ?? now
            let b = e.lastRun.map { $0.addingTimeInterval(minInterval) } ?? now
            return max(a, b, now)
        }.min()
    }
}

// MARK: - Optional HTTP call

/// Asks the on-device caption model (llama-server, OpenAI-style API). Never required: returns nil when nothing answers,
/// and the heuristic stays. Call off the main thread.
public final class CaptionModelClient: @unchecked Sendable {
    public let port: Int
    public init(port: Int = LocalModel.port) { self.port = port }

    public func reply(for input: CaptionInput, timeout: TimeInterval = 8) -> String? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = CaptionEngine.requestBody(input)
        let sem = DispatchSemaphore(value: 0)
        let box = ReplyBox()
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d, let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let c = (j["choices"] as? [[String: Any]])?.first, let m = c["message"] as? [String: Any] {
                box.set(m["content"] as? String)
            }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + timeout + 1)
        return box.get()
    }

    private final class ReplyBox: @unchecked Sendable {
        private var v: String?; private let l = NSLock()
        func set(_ s: String?) { l.lock(); v = s; l.unlock() }
        func get() -> String? { l.lock(); defer { l.unlock() }; return v }
    }
}
