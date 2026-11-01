import Foundation

// LAB-2042 · LAB-2043 · the Inbox: the v2 window's live place (was Needs you's queue + detail). One dark,
// terminal-style block per session that needs you, newest at the top (owner 2026-11-01: descending everywhere), each
// showing only the current important thing and answered in place. The view draws what this builds; every rule the
// blocks follow (order, kind, options, what ↩ and a free-text option send, the copy) lives here so it can be tested.

/// What a block is about.
public enum InboxKind: String, Sendable, CaseIterable {
    case permission, menu, question, finished, waiting, plan, loop

    /// The tag in the block's header strip.
    public var tag: String {
        switch self {
        case .permission: return "Permission"
        case .menu: return "Question"
        case .question: return "Asked a question"
        case .finished: return "Finished · waiting for you"
        case .waiting: return "Waiting for you"
        case .plan: return "Plan"
        case .loop: return "Loop"
        }
    }

    public static func of(_ d: Decision) -> InboxKind {
        if d.isQuestion { return .question }
        if d.isFinished { return .finished }
        if d.isMenu { return .menu }
        return .permission
    }
}

/// One block of the Inbox.
public struct InboxBlock: Identifiable, Equatable, Sendable {
    /// Stable per session ("session-<id>"), plan ("plan-<id>") or loop item ("loop-<id>"): a session's next ask shows
    /// in the same block.
    public var id: String
    public var kind: InboxKind
    public var at: Date
    public var sessionId: String?
    /// The ask the block shows now: the session's oldest open one (asks are answered in the order they came).
    public var decision: Decision?
    public var planId: String?
    public var loopItemId: String?
    /// Other open asks of the same session, after this one ("1 more from this session").
    public var more: Int = 0

    public init(id: String, kind: InboxKind, at: Date, sessionId: String? = nil, decision: Decision? = nil,
                planId: String? = nil, loopItemId: String? = nil, more: Int = 0) {
        self.id = id; self.kind = kind; self.at = at; self.sessionId = sessionId; self.decision = decision
        self.planId = planId; self.loopItemId = loopItemId; self.more = more
    }
}

/// The page's blocks in their sections.
public struct InboxLayout: Equatable, Sendable {
    /// Sessions and plans, newest first.
    public var asks: [InboxBlock]
    /// Loop items (under "Loops · Today · N"), newest first. Loops never show as sessions (LAB-1866, LAB-1933).
    public var loops: [InboxBlock]
    /// Every block in page order (keyboard order: ↑ ↓ ⌘] ⌘[).
    public var all: [InboxBlock] { asks + loops }
}

/// A button in a block's options row.
public struct InboxButton: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case choice(DecisionChoice)
        case allowOnce, always, deny, cancel
        case reply, setAside, closeSession
        case approvePlan, editPlan, rejectPlan
    }
    public var action: Action
    public var title: String
    public var primary: Bool
    public var enabled: Bool
    public var help: String
    public var danger: Bool = false
}

/// What sending or pressing an option does.
public enum InboxSend: Equatable, Sendable {
    /// The text as the agent's next message (a question or finished turn), or Esc then the text (a permission).
    case reply(String)
    /// One of the prompt's own options; a free-text option carries what was typed.
    case choice(DecisionChoice, String?)
    /// A fixed answer (no options were read).
    case answer(Answer)
    /// Type the instructions first: the reply box takes the focus.
    case focusBox
    case nothing
}

public enum Inbox {
    // MARK: Blocks

    /// The blocks, newest first. `open` = the open asks (manual sessions only, as `SessionScope.openDecisions`).
    /// `waiting` = sessions that need you whose ask the engine has not filed yet (the badge counts them; their block
    /// says so and opens the session). Plans and loop items keep their own times.
    public static func layout(open: [Decision], plans: [(id: String, at: Date)], loops: [(id: String, at: Date)],
                              waiting: [String] = []) -> InboxLayout {
        var bySession: [String: [Decision]] = [:]
        for d in open { bySession[d.sessionId, default: []].append(d) }
        var asks: [InboxBlock] = bySession.map { sid, ds in
            let sorted = ds.sorted { $0.askedAt == $1.askedAt ? $0.id.uuidString < $1.id.uuidString : $0.askedAt < $1.askedAt }
            let d = sorted[0]
            return InboxBlock(id: "session-" + sid, kind: InboxKind.of(d), at: d.askedAt, sessionId: sid, decision: d, more: sorted.count - 1)
        }
        for sid in waiting where bySession[sid] == nil {
            asks.append(InboxBlock(id: "session-" + sid, kind: .waiting, at: .distantPast, sessionId: sid))
        }
        asks += plans.map { InboxBlock(id: "plan-" + $0.id, kind: .plan, at: $0.at, planId: $0.id) }
        let loopBlocks = loops.map { InboxBlock(id: "loop-" + $0.id, kind: .loop, at: $0.at, loopItemId: $0.id) }
        return InboxLayout(asks: InboxUrgency.sorted(newestFirst(asks)), loops: newestFirst(loopBlocks))   // LAB-2112: critical first
    }

    static func newestFirst(_ b: [InboxBlock]) -> [InboxBlock] {
        b.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at > $1.at }
    }

    /// Sessions running that have nothing for you: hidden, counted in the header ("5 other sessions working").
    public static func quietCount(liveSessions: [String], shown: [InboxBlock]) -> Int {
        let ids = Set(shown.compactMap(\.sessionId))
        return Set(liveSessions).subtracting(ids).count
    }

    /// The block `needspick` / a picked id points at: a decision id, a "plan-" / "loop-" id, or a block id.
    public static func block(for pick: String, in blocks: [InboxBlock]) -> InboxBlock? {
        blocks.first { $0.id == pick || $0.decision?.id.uuidString == pick || ($0.planId.map { "plan-" + $0 } == pick) || ($0.loopItemId.map { "loop-" + $0 } == pick) }
    }

    /// The block after (or before) `id` in page order, wrapping round; the first one when `id` is gone.
    public static func step(from id: String?, by delta: Int, in blocks: [InboxBlock]) -> String? {
        guard !blocks.isEmpty else { return nil }
        guard let id, let i = blocks.firstIndex(where: { $0.id == id }) else { return blocks[0].id }
        return blocks[(i + delta + blocks.count * 2) % blocks.count].id
    }

    // MARK: Header copy

    public static func waitingLine(_ n: Int) -> String {
        n == 0 ? "Nothing waiting" : n == 1 ? "1 thing waiting for your attention" : "\(n) things waiting for your attention"
    }

    public static func othersLine(_ n: Int) -> String? {
        n <= 0 ? nil : n == 1 ? "1 other session working ›" : "\(n) other sessions working ›"
    }

    public static func moreLine(_ n: Int) -> String? {
        n <= 0 ? nil : "\(n) more from this session"
    }

    public static func newAboveLine(_ n: Int) -> String {
        n == 1 ? "1 new above ↑" : "\(n) new above ↑"
    }

    /// "4 min", "2 h", "3 d"; "now" under a minute.
    public static func age(_ d: Date, now: Date = Date()) -> String {
        guard d > .distantPast else { return "" }
        let m = Int(now.timeIntervalSince(d) / 60)
        if m < 1 { return "now" }
        if m < 60 { return "\(m) min" }
        if m < 1440 { return "\(m / 60) h" }
        return "\(m / 1440) d"
    }

    /// VoiceOver: "<session>, <kind>, asked 4 min ago: <ask text>".
    public static func accessibilityLabel(session: String, kind: InboxKind, at: Date, ask: String, now: Date = Date()) -> String {
        let a = age(at, now: now)
        let when = a.isEmpty ? "" : a == "now" ? ", asked just now" : ", asked \(a) ago"
        return "\(session), \(kind.tag)\(when)" + (ask.isEmpty ? "" : ": " + ask)
    }

    // MARK: What a block says

    /// The ask as the terminal shows it: a headline, then the lines (monospaced), dimmed when the agent gave no words.
    public struct Body: Equatable, Sendable {
        public var headline: String?
        public var lines: [String]
        public var dim: Bool
        public var note: String?
    }

    public static func body(_ d: Decision, agentName: String) -> Body {
        switch InboxKind.of(d) {
        case .question:
            return Body(headline: nil, lines: [d.why], dim: d.whyMissing)
        case .finished:
            return Body(headline: nil, lines: [d.why], dim: d.whyMissing)
        case .menu:
            let q = d.headline.replacingOccurrences(of: "\(d.agent.displayName) is asking: ", with: "")
            let note = d.touches == DecisionMatcher.geminiSignInRefused ? d.touches : nil
            let screen = d.screen ?? []
            // The question once: as a headline, unless the screen as drawn already shows it.
            let drawn = screen.contains { $0.trimmingCharacters(in: .whitespaces) == q.trimmingCharacters(in: .whitespaces) }
            return Body(headline: drawn ? nil : q, lines: screen.isEmpty ? [q] : screen, dim: false, note: note)
        default:
            let head = d.headline.replacingOccurrences(of: d.agent.displayName, with: agentName)
            var lines: [String] = []
            if let s = d.screen, !s.isEmpty { lines = s }
            else if let c = d.command { lines = ["$ " + c] }
            else if let p = d.path { lines = ["$ " + p] }
            return Body(headline: head, lines: lines, dim: false)
        }
    }

    /// The risk line of a permission: "Low." / "High." / "Plan." and the history sentence.
    public static func riskSentence(_ d: Decision) -> String {
        var s = d.history.similarAllowed > 0 ? "Same command you allowed \(d.history.similarAllowed) time\(d.history.similarAllowed == 1 ? "" : "s") this week." : ""
        if let r = d.history.ruleSuggestion { s += (s.isEmpty ? "" : " ") + r + "." }
        return s
    }

    /// Finished turns show 12 lines, then "Show all ▾".
    public static let finishedLines = 12
    public static func isLong(_ text: String, lines: Int = finishedLines, width: Int = 110) -> Bool {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, ($1.count + width - 1) / width) }
        return rows > lines
    }

    // MARK: Options

    /// Every option the prompt shows, in its order and words (LAB-1839, LAB-1907), numbered, the first ↩; the fixed
    /// answers when none could be read; a menu's Cancel; a finished turn's Reply · Set aside · Close session.
    public static func buttons(_ d: Decision, repo: String? = nil) -> [InboxButton] {
        switch InboxKind.of(d) {
        case .question:
            return [InboxButton(action: .reply, title: "Reply ↩", primary: true, enabled: true, help: "Send what is in the reply box")]
        case .finished:
            return [InboxButton(action: .reply, title: "Reply ↩", primary: true, enabled: true, help: "Send what is in the reply box"),
                    InboxButton(action: .setAside, title: "Set aside", primary: false, enabled: true,
                                help: "Nothing more for now: it leaves the Inbox, the session stays open"),
                    InboxButton(action: .closeSession, title: "Close session", primary: false, enabled: true, help: "End this session", danger: true)]
        case .menu:
            return choiceButtons(d.choices ?? [])
                + [InboxButton(action: .cancel, title: "Cancel esc", primary: false, enabled: true, help: "Cancel the menu (Esc)")]
        default:
            if let c = d.choices, !c.isEmpty { return choiceButtons(c) }
            var out = [InboxButton(action: .allowOnce, title: "Allow once ↩", primary: true, enabled: d.agent != .opencode,
                                   help: d.agent == .opencode ? "Allow once: pick this one in the agent's own terminal" : "Allow once")]
            if !d.pattern.hasPrefix("ask:") && d.agent != .opencode {
                out.append(InboxButton(action: .always, title: "Always allow this", primary: false, enabled: true,
                                       help: "Always allow \(d.pattern) in \(repo ?? d.repo)"))
            }
            out.append(InboxButton(action: .deny, title: "Deny esc", primary: false, enabled: true, help: "Deny (Esc)"))
            return out
        }
    }

    static func choiceButtons(_ choices: [DecisionChoice]) -> [InboxButton] {
        choices.enumerated().map { i, c in
            InboxButton(action: .choice(c), title: "\(i + 1). \(c.label)" + (i == 0 ? "  ↩" : ""), primary: i == 0, enabled: c.pressable,
                        help: c.pressable ? c.label : "\(c.label): pick this one in the agent's own terminal")
        }
    }

    public static func planButtons() -> [InboxButton] {
        [InboxButton(action: .approvePlan, title: "Approve plan", primary: true, enabled: true, help: "Start the plan's steps"),
         InboxButton(action: .editPlan, title: "Edit plan", primary: false, enabled: true, help: "Open the plan to change it"),
         InboxButton(action: .rejectPlan, title: "Reject", primary: false, enabled: true, help: "Nothing runs; the planner waits for your edits")]
    }

    /// ↩ on a focused block with an empty box: the first option (or Allow once). Nil when nothing can be pressed.
    public static func defaultButton(_ buttons: [InboxButton]) -> InboxButton? {
        buttons.first { $0.enabled }
    }

    /// Esc on a focused block with an empty box: Deny, or a menu's Cancel; the last option of a prompt whose own
    /// options start with No (Claude's "3. No") is not guessed: Esc then means the prompt's own Esc (deny).
    public static func cancelButton(_ buttons: [InboxButton]) -> InboxButton? {
        buttons.first { $0.action == .deny || $0.action == .cancel }
    }

    /// 1–9 on a focused block: option n.
    public static func numbered(_ n: Int, in buttons: [InboxButton]) -> InboxButton? {
        let options = buttons.filter { if case .choice = $0.action { return true }; return false }
        let list = options.isEmpty ? buttons : options
        guard n >= 1, n <= list.count, list[n - 1].enabled else { return nil }
        return list[n - 1]
    }

    // MARK: Reply box

    /// The reply box's placeholder, or nil when the block has no box (a menu without its own answer, plans, loops).
    public static func placeholder(_ d: Decision, agentName: String) -> String? {
        switch InboxKind.of(d) {
        case .question: return "Your answer"
        case .finished: return "Next message for \(agentName): continue, or ask it something"
        case .menu: return d.choices?.contains(where: \.freeText) == true ? "Your own answer" : nil
        default:
            return d.whyMissing ? "Ask it: why do you want to do this?" : "Or reply with instructions: \u{201C}Run them, but skip the snapshot tests\u{201D}"
        }
    }

    /// The hint under the block, today's copy per kind.
    public static func footer(_ d: Decision, agentName: String) -> String {
        switch InboxKind.of(d) {
        case .question: return "Your answer goes to \(agentName) as its next message. You can also answer in the terminal."
        case .finished: return "Your reply goes to \(agentName) as its next message. Typing in the terminal works too."
        case .menu: return "Each button presses that option in \(agentName)'s terminal. You can also answer there."
        default:
            return d.choices?.isEmpty == false
                ? "This waits until you choose. ↩ the first option · esc cancel · ⌘] next · ⌘[ previous · or answer in the terminal"
                : "This waits until you choose. ↩ allow once · esc deny · ⌘] next · ⌘[ previous"
        }
    }

    /// The hosted agents' note (OpenCode, Goose): their own terminal answers; the reply box is off.
    public static func hostedNote(_ d: Decision) -> String? {
        guard d.agent.isHosted else { return nil }
        return d.agent == .opencode
            ? "Approve in OpenCode's terminal; its selected option is shown by color. Deny here safely sends Escape."
            : "This is Goose's native approval menu. Unknown or changed menus must be answered in the terminal."
    }

    /// What ↩ in the reply box sends (today's semantics): a question or finished turn → the text as its next message;
    /// a prompt with a free-text option ("No, and tell Claude what to do") → that option with the text; any other
    /// permission → Esc then the text. Nothing typed (and no image) → nothing.
    public static func send(_ d: Decision, text: String) -> InboxSend {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .nothing }
        switch InboxKind.of(d) {
        case .question, .finished: return .reply(t)
        case .menu:
            if let free = d.choices?.first(where: \.freeText) { return .choice(free, t) }
            return .nothing
        default:
            if d.agent.isHosted { return .nothing }
            if let free = d.choices?.first(where: \.freeText) { return .choice(free, t) }
            return .reply(t)
        }
    }

    /// What pressing an option does (LAB-1607 / LAB-1839): a free-text option with an empty box moves to the box first
    /// (menus excepted, as today: their "Type something." opens the agent's own field).
    public static func choose(_ d: Decision, _ c: DecisionChoice, text: String) -> InboxSend {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.freeText && t.isEmpty && !d.isMenu { return .focusBox }
        return .choice(c, c.freeText && !t.isEmpty ? t : nil)
    }

    /// The words "You: …" an answered block shows before it folds.
    public static func answeredLine(_ d: Decision) -> String {
        "You: " + (ScrollFeed.answerText(d) ?? "Answered") + (d.answeredAt.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? "")
    }

    /// The red line when the session cannot be reached.
    public static func unreachable(_ session: String) -> String {
        "Couldn't reach \(session): it isn't running. Open session to see why."
    }

    // MARK: Images

    public static let maxImages = 6
    public static let maxImageBytes = 20 * 1024 * 1024

    /// Which new images the reply box takes (images only, no duplicates, at most 6, 20 MB each), and the note for
    /// the ones it refused.
    public static func accept(_ new: [String], existing: [String], size: (String) -> Int) -> (images: [String], note: String?) {
        var out = existing
        var note: String?
        for p in new where ImageAttachments.isImagePath(p) && !out.contains(p) {
            if size(p) > maxImageBytes { note = "That image is too big (max 20 MB)"; continue }
            if out.count >= maxImages { note = "Up to \(maxImages) images per reply"; break }
            out.append(p)
        }
        return (out, note)
    }

    /// The message the reply sends: the text with the images named at the end, on one line.
    public static func message(_ text: String, images: [String]) -> String {
        ImageAttachments.openingMessage(text, images: images)
    }
}
