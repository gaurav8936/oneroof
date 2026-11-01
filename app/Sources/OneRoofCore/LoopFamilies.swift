import Foundation

/// LAB-2055 · the Loops page's first screen: the ten loop kinds (`LoopKinds.all`) in four families, one card each
/// (Watch · Check · Report · Improve), plus Other for loops with no kind. Pure: the view draws what this returns.
/// Agent decision 2026-11-01 (owner asked for full autonomy, can override): four families, each card naming its kinds.
extension LoopKinds {
    public struct Family: Identifiable, Equatable, Sendable {
        public var id: String
        public var title: String
        /// The kinds in this family, in the order the card names them.
        public var kinds: [String]
        /// One line, exact copy from the LAB-2055 spec.
        public var blurb: String
        public init(id: String, title: String, kinds: [String], blurb: String) {
            self.id = id; self.title = title; self.kinds = kinds; self.blurb = blurb
        }
        /// "Sentinel · Prober".
        public var kindTitles: String { kinds.compactMap { LoopKinds.kind($0)?.title }.joined(separator: " · ") }
    }

    public static let families: [Family] = [
        Family(id: "watch", title: "Watch", kinds: ["sentinel", "prober"],
               blurb: "Keeps an eye on a number or a live thing and speaks up when it goes wrong."),
        Family(id: "check", title: "Check", kinds: ["auditor", "judge"],
               blurb: "Measures work against a rule or a bar and reports the gaps."),
        Family(id: "report", title: "Report", kinds: ["reporter", "researcher", "writer"],
               blurb: "Sums up what happened, or what changed outside, for you to read."),
        Family(id: "improve", title: "Improve", kinds: ["fixer", "refresher", "learner"],
               blurb: "Changes something: fixes until a check passes, refreshes data, proposes rules."),
    ]

    /// Loops with no kind (yours, or library loops whose catalog names none): drawn only when it has loops.
    public static let otherFamily = Family(id: "other", title: "Other", kinds: [],
                                           blurb: "Loops with no kind set: yours made in One Roof or ae, and library loops whose catalog names none.")

    /// The family a kind belongs to (nil for an unknown or missing kind: Other).
    public static func family(ofKind id: String?) -> Family? {
        guard let id else { return nil }
        return families.first { $0.kinds.contains(id) }
    }

    public static func family(_ id: String) -> Family? { id == otherFamily.id ? otherFamily : families.first { $0.id == id } }
}

extension LoopKinds.Kind {
    /// LAB-2055: the family card this kind is drawn in.
    public var family: LoopKinds.Family? { LoopKinds.family(ofKind: id) }
}

/// LAB-2055 · the four family cards with their loops, ordered for the chips.
public enum LoopFamilies {
    public struct Group: Identifiable, Equatable, Sendable {
        public var family: LoopKinds.Family
        public var loops: [Loop]
        public var id: String { family.id }
        public var needsYou: Int { loops.filter { $0.state == .needsYou }.count }
        public var running: Int { loops.filter { $0.state == .running }.count }
        /// The card header's badge: "1 needs you", else "2 running", else nil.
        public var badge: String? {
            if needsYou > 0 { return "\(needsYou) needs you" }
            if running > 0 { return "\(running) running" }
            return nil
        }
        /// VoiceOver: "Watch, 9 loops, 1 needs you".
        public var accessibilityLabel: String {
            [family.title, "\(loops.count) loop\(loops.count == 1 ? "" : "s")", badge].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// The four families (always, even when empty) and Other when any loop has no known kind; loops in chip order.
    public static func groups(_ loops: [Loop]) -> [Group] {
        var out = LoopKinds.families.map { f in Group(family: f, loops: ordered(loops.filter { f.kinds.contains($0.kind ?? "") })) }
        let other = loops.filter { LoopKinds.family(ofKind: $0.kind) == nil }
        if !other.isEmpty { out.append(Group(family: LoopKinds.otherFamily, loops: ordered(other))) }
        return out
    }

    /// Chip order: needs you, running, pinned, mine, then built-in; A→Z by title inside each.
    public static func ordered(_ loops: [Loop]) -> [Loop] {
        func rank(_ l: Loop) -> Int {
            if l.state == .needsYou { return 0 }
            if l.state == .running { return 1 }
            if l.pinned { return 2 }
            return l.origin == .mine ? 3 : 4
        }
        return loops.sorted { a, b in
            let (ra, rb) = (rank(a), rank(b))
            if ra != rb { return ra < rb }
            return a.displayTitle.localizedCaseInsensitiveCompare(b.displayTitle) == .orderedAscending
        }
    }

    /// Split cards into two columns, each card going to the shorter column (by loop count plus a header's worth), so
    /// both columns end near the same height and every card fits one screen at 1280×800.
    public static func columns(_ groups: [Group], count: Int, chipsPerRow: Int = 4) -> [[Group]] {
        guard count > 1 else { return [groups] }
        var cols = Array(repeating: [Group](), count: count)
        var height = Array(repeating: 0, count: count)
        for g in groups {
            let i = height.indices.min { height[$0] < height[$1] } ?? 0
            cols[i].append(g)
            height[i] += 3 + max(1, (g.loops.count + chipsPerRow - 1) / chipsPerRow)
        }
        return cols
    }

    /// The kind page's last-result line, from the ledger's runs (newest first): "Never run", "done · Oct 30",
    /// "failed ×2" (the same result twice or more in a row).
    public static func lastResult(runs: [LoopLedger.Run], lastRunAt: Date? = nil) -> String {
        guard let r = runs.first else {
            if let d = lastRunAt { return "ran · " + day(d) }
            return "Never run"
        }
        let result = r.result.isEmpty ? "ran" : r.result
        let streak = runs.prefix { $0.result == r.result }.count
        if streak > 1 { return "\(result) ×\(streak)" }
        if let d = LoopInbox.iso(r.started) { return result + " · " + day(d) }
        return result
    }

    static func day(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

/// LAB-2056 · the Loops page's state chip and chip colours: no strikethrough, a plain Off chip, labels at 4.5:1 on
/// their fill and edges at 3:1. Session pills elsewhere are unchanged (this is for Loops only).
public enum LoopLook {
    /// The chip's words: "Off" for a loop that is stopped (not running, not armed to run); otherwise the state.
    public static func label(_ l: Loop) -> String {
        if l.state == .waiting, l.run == nil, l.trigger.isQuiet, !l.runRequested { return "Waiting for quiet" }
        return l.state.label
    }

    /// A neutral chip (Off, Paused): the control fill, text colour, a strong edge.
    public static func neutral(_ theme: ThemeName) -> PillStyle {
        let k = theme.tokens
        return PillStyle(fill: k.control.over(k.surface), text: k.text, edge: .solid(k.separatorStrong))
    }

    /// The pill for a loop's state on Loops: Off and Paused neutral; the others borrow the session pill (none strikes).
    public static func pill(_ s: LoopState, theme: ThemeName) -> PillStyle {
        switch s {
        case .stopped, .paused: return neutral(theme)
        default: return StatusPalette.pill(s.pillStatus, theme: theme)
        }
    }

    /// A loop chip on a family card: yours filled, built-in outlined; both with a strong edge and text colour.
    public static func chip(mine: Bool, theme: ThemeName) -> (fill: RGB?, text: RGB, edge: RGB) {
        let k = theme.tokens
        return (mine ? k.selection.over(k.surface) : nil, k.text, k.separatorStrong)
    }

    /// Card edges on Loops (3:1 against the page and the card).
    public static func cardEdge(_ theme: ThemeName) -> RGB { theme.tokens.separatorStrong }

    /// A disabled button's label (3:1 or more on the card; the button keeps no red when disabled).
    public static func disabledLabel(_ theme: ThemeName) -> RGB { theme.tokens.text3 }

    /// A check with no result in the health strip (a neutral bar, not faded red).
    public static func unknownBar(_ theme: ThemeName) -> RGB { theme.tokens.text3 }

    /// Why a loop's button is disabled (the tooltip and VoiceOver hint), or nil when it is enabled.
    public static func disabledReason(_ button: String, _ l: Loop) -> String? {
        switch button {
        case "Run now":
            if l.state == .needsYou { return "Waiting for you" }
            if l.state == .running || l.runRequested { return "Already running" }
            return nil
        case "Pause":
            return (l.state.isActive || (l.trigger.isArmed && l.state != .stopped)) ? nil : "Not running or scheduled"
        case "Stop":
            return (l.run == nil && !l.runRequested && l.state == .stopped) ? "Nothing is running" : nil
        default: return nil
        }
    }
}
