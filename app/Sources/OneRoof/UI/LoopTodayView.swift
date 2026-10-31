import AppKit
import SwiftUI
import OneRoofCore

/// LAB-1866 · LAB-1919: a loop item in the Needs you list (a loop that stopped, a round that asks, or what loops
/// staged overnight: Today). Never a session row (LAB-1933).
struct LoopNeedRow: View {
    @Environment(\.theme) private var t
    let item: LoopInbox.Item
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text("↻").ui(13, .semibold).foregroundStyle(t.accentText.color).frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: Radius.squircle20, style: .continuous).fill(t.surface.color))
                    .accessibilityHidden(true)
                Text(item.loopTitle).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Spacer()
                Text(age(item.when)).ui(11.5).foregroundStyle(t.text3.color)
            }
            Text(item.headline).ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
            Text(Self.tag(item)).ui(11, .semibold).foregroundStyle((item.kind == .failed ? t.needsText : t.accentText).color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(selected ? t.surface.color : .clear))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? t.separatorStrong.color : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loop \(item.loopTitle): \(item.headline). \(Self.tag(item))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    static func tag(_ i: LoopInbox.Item) -> String {
        switch i.kind {
        case .failed: return "Loop stopped · needs a look"
        case .asks: return "Loop round asks"
        case .staged: return "Today · waiting for your approval"
        }
    }

    private func age(_ d: Date) -> String {
        guard d > .distantPast else { return "" }
        let m = Int(Date().timeIntervalSince(d) / 60)
        if m < 1 { return "now" }
        if m < 60 { return "\(m)m" }
        if m < 1440 { return "\(m / 60)h" }
        return "\(m / 1440)d"
    }
}

/// The detail of a loop item, with its actions right there (LAB-1919: approve, apply, merge, open, dismiss).
struct LoopNeedDetail: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var inbox = LoopInboxState.shared
    let item: LoopInbox.Item
    var win: WindowState?
    @State private var reason = ""
    @State private var dismissing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    MicroLabel(LoopNeedRow.tag(item))
                    Text(item.headline).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    Text("Loop " + item.loopTitle).ui(13).foregroundStyle(t.text2.color)
                }
                switch item.kind {
                case .failed, .asks: loopPart
                case .staged: stagedPart
                }
                if let r = inbox.lastResult[item.id] {
                    Text(r).ui(12.5).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
                        .accessibilityLabel("Result: " + r)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var busy: Bool { inbox.busy.contains(item.id) || inbox.busy.contains(item.loopId) }

    private var loopPart: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.detail).ui(13.5).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if item.kind == .asks, let sid = item.sessionId, let it = model.item(sid) {
                    RoofButton("Open the round ↗", .primary) { model.reveal(it) }
                } else if item.kind == .failed {
                    RoofButton("Run again", .primary) { inbox.runAgain(item.loopId) { model.refreshLoopInbox() } }.disabled(busy)
                }
                RoofButton("Open loop") { model.openLoop(item.loopId, in: win) }
                if item.kind == .failed {
                    RoofButton("Mark seen") { inbox.markSeen(item.loopId) { model.refreshLoopInbox() } }.disabled(busy)
                }
            }
            Text(item.kind == .failed
                 ? "Run again starts a new run (the check first). Mark seen takes it out of Needs you until the loop fails again."
                 : "A loop round's terminal is not in your session list: it opens here and from its loop's Runs.")
                .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stagedPart: some View {
        let actions = LoopInbox.actions(for: item)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.outcomes) { o in LoopOutcomeLine(outcome: o, model: model, win: win) }
            }
            if let gate = item.outcomes.compactMap({ $0.detailValue("gate") }).first {
                Text("Last gate: " + gate + (item.outcomes.compactMap { $0.detailValue("harvest") }.first.map { " · " + $0 } ?? ""))
                    .ui(12).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { a in
                    switch a {
                    case .approvePR:
                        RoofButton(busy ? "Checking…" : a.label, .primary) { inbox.approveAndOpenPR(item) { model.refreshLoopInbox() } }.disabled(busy)
                            .help("Records your approval, runs the loop's check and the judge on its branch, then pushes it and opens the PR. Nothing is merged.")
                    case .approve:
                        RoofButton(a.label, .primary) { inbox.decide(item, "approved") { model.refreshLoopInbox() } }.disabled(busy)
                    case .apply:
                        RoofButton(a.label, .primary) { inbox.decide(item, "applied") { model.refreshLoopInbox() } }.disabled(busy)
                    case .open:
                        RoofButton(a.label) { open() }
                    case .dismiss:
                        RoofButton(a.label, .danger) { dismissing.toggle() }.disabled(busy)
                    }
                }
                Spacer()
                RoofButton("Open loop", .plain) { model.openLoop(item.loopId, in: win) }
            }
            if dismissing {
                HStack(spacing: 8) {
                    TextField("Why (optional, kept in the ledger)", text: $reason).textFieldStyle(.roundedBorder)
                    RoofButton("Dismiss", .danger) {
                        inbox.decide(item, "rejected", reason: reason.isEmpty ? nil : reason) { model.refreshLoopInbox() }
                        dismissing = false; reason = ""
                    }
                }
            }
            Text(help).ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var help: String {
        switch item.outcomeKind {
        case "commit", "pr": return "A loop never pushes. Approve runs the gate (the loop's check + an LLM judge on the diff); only if both pass is the branch pushed and a PR opened. A failed gate keeps it here with the reason."
        case "file": return "Apply records that the update is in use; the loop never changes your data on its own."
        default: return "Your decision is written to the outcome ledger (the same row `ae loops ledger --decide` writes)."
        }
    }

    private func open() {
        guard let o = item.outcomes.first else { return }
        LoopOutcomeLine.open(o, loopId: item.loopId, model: model, win: win)
    }
}

/// One ledger outcome: kind, title, status and where it points, opened from the row.
struct LoopOutcomeLine: View {
    @Environment(\.theme) private var t
    let outcome: LoopLedger.Outcome
    @ObservedObject var model: AppModel
    var win: WindowState?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(outcome.kind).ui(11, .semibold, mono: true).foregroundStyle(t.text3.color).frame(width: 64, alignment: .leading)
            Text(outcome.title.isEmpty ? "(no title)" : outcome.title).ui(13).foregroundStyle(t.text.color).lineLimit(2)
            Spacer(minLength: 6)
            if outcome.status != "staged" {
                Text(outcome.status + (outcome.decidedBy.map { " · " + $0 } ?? "")).ui(11.5).foregroundStyle(t.text2.color)
            }
            if Self.linkLabel(outcome) != nil {
                Button { Self.open(outcome, loopId: outcome.loop, model: model, win: win) } label: {
                    Text(Self.linkLabel(outcome)! + " ↗").ui(11.5, mono: true).foregroundStyle(t.accentText.color).lineLimit(1)
                }
                .buttonStyle(.plain).help(outcome.link)
                .accessibilityLabel("Open " + (Self.linkLabel(outcome) ?? "link"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    static func linkLabel(_ o: LoopLedger.Outcome) -> String? {
        switch o.target {
        case .commit(let sha, _): return sha
        case .branch(let b): return b
        case .url(let u): return u.contains("/pull/") ? "PR " + (u.split(separator: "/").last.map(String.init) ?? "") : "link"
        case .file(let f): return (f as NSString).lastPathComponent
        case .key(let k): return k
        case .none: return nil
        }
    }

    /// Open what an outcome points at: a commit or branch in Review changes (the loop's worktree), a URL in the
    /// browser, a file in the viewer, otherwise the loop.
    static func open(_ o: LoopLedger.Outcome, loopId: String, model: AppModel, win: WindowState?) {
        switch o.target {
        case .commit, .branch:
            if let l = LoopStore().load(loopId), FileManager.default.fileExists(atPath: l.worktreePath) {
                let w = win ?? model.active
                w.reviewRepo = l.worktreePath
                model.show(.review, in: w)
            } else { model.openLoop(loopId, in: win) }
        case .url(let u): if let url = URL(string: u) { NSWorkspace.shared.open(url) }
        case .file(let f): model.openInViewer((f as NSString).expandingTildeInPath)
        case .key, .none: model.openLoop(loopId, in: win)
        }
    }
}

/// LAB-1920: a multi-line field that grows with its text and that you can make taller by dragging its bottom edge;
/// the height is remembered per field.
struct GrowingTextArea: View {
    @Environment(\.theme) private var t
    @Binding var text: String
    var placeholder: String
    var mono = false
    var storageKey: String
    var minHeight: Double = 64
    var label: String
    @AppStorage private var height: Double
    @State private var dragFrom: Double?

    init(text: Binding<String>, placeholder: String, mono: Bool = false, storageKey: String, minHeight: Double = 64, label: String) {
        _text = text; self.placeholder = placeholder; self.mono = mono; self.storageKey = storageKey; self.minHeight = minHeight; self.label = label
        _height = AppStorage(wrappedValue: minHeight, "loops.editor." + storageKey, store: Prefs.defaults)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(mono ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4).padding(.vertical, 5)
                    .accessibilityLabel(label)
                if text.isEmpty {
                    Text(placeholder).ui(13, mono: mono).foregroundStyle(t.text3.color).padding(.horizontal, 9).padding(.vertical, 6)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .frame(height: CGFloat(max(minHeight, height)))
            Rectangle().fill(Color.clear).frame(height: 7)
                .overlay(Capsule().fill(t.separatorStrong.color).frame(width: 28, height: 3))
                .contentShape(Rectangle())
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
                .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                    let from = dragFrom ?? max(minHeight, height)
                    if dragFrom == nil { dragFrom = from }
                    height = min(600, max(minHeight, from + Double(v.translation.height)))
                }.onEnded { _ in dragFrom = nil })
                .accessibilityElement()
                .accessibilityLabel(label + " height")
                .accessibilityValue("\(Int(max(minHeight, height))) points")
                .accessibilityAdjustableAction { dir in height = min(600, max(minHeight, height + (dir == .increment ? 40 : -40))) }
                .help("Drag to make the field taller")
        }
        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separatorStrong.color))
    }
}

/// LAB-1922 · the loop gallery: every kind of loop, what it produces and where it goes, each loop of that kind in the
/// library and yours, and a real sample from its runs (from the outcome ledger; "no run yet" until there is one).
struct LoopGalleryView: View {
    @Environment(\.theme) private var t
    @ObservedObject var board: LoopBoard
    var openLoop: (String) -> Void
    var startFrom: (Loop) -> Void

    var body: some View {
        let kinds = LoopKinds.all.filter { k in board.loops.contains { $0.kind == k.id } }
        let unkinded = board.loops.filter { ($0.kind == nil || LoopKinds.kind($0.kind) == nil) && $0.origin == .mine }
        let unkindedBuiltIn = board.loops.filter { ($0.kind == nil || LoopKinds.kind($0.kind) == nil) && $0.origin == .builtIn }
        VStack(alignment: .leading, spacing: 14) {
            Text("Every kind of loop this workspace has, what each produces and where its output goes. Samples come from real runs in the outcome ledger.")
                .ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            ForEach(kinds) { k in kindCard(k, board.loops.filter { $0.kind == k.id }) }
            if !unkinded.isEmpty {
                kindCard(LoopKinds.Kind(id: "other", title: "Your own", purpose: "Loops you made in One Roof (no kind set).",
                                        produces: "Whatever its rounds commit, staged for your approval"), unkinded)
            }
            if !unkindedBuiltIn.isEmpty {
                kindCard(LoopKinds.Kind(id: "library", title: "Library (kind not given)", purpose: "Built-in loops from the Agentic Engineering kit whose catalog does not name a kind yet.",
                                        produces: "See each loop's output line"), unkindedBuiltIn)
            }
        }
    }

    private func kindCard(_ k: LoopKinds.Kind, _ loops: [Loop]) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(k.title).ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Text("\(loops.count) loop\(loops.count == 1 ? "" : "s")").ui(11.5, mono: true).foregroundStyle(t.text3.color)
                    Spacer()
                }
                Text(k.purpose).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                Text("Produces: " + k.produces).ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                ForEach(loops) { l in loopLine(l) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kind \(k.title), \(loops.count) loops")
    }

    private func loopLine(_ l: Loop) -> some View {
        let sample = board.outcomesByLoop[l.id]?.first
        let run = board.runsByLoop[l.id]?.first
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Button { openLoop(l.id) } label: { Text(l.displayTitle).ui(13, .semibold).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).accessibilityLabel("Open loop \(l.displayTitle)")
                Text(l.origin.label).ui(10.5, .medium).foregroundStyle(t.text3.color)
                Text(l.externalSchedule ?? l.trigger.label).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1)
                Spacer()
                if l.origin == .builtIn { RoofButton("Start from this", .plain) { startFrom(l) } }
            }
            Text(l.goal).ui(12.5).foregroundStyle(t.text2.color).lineLimit(2)
            Text("Output: " + LoopKinds.destination(act: l.act)).ui(11.5).foregroundStyle(t.text2.color).lineLimit(2)
            Group {
                if let s = sample {
                    Text("Sample (\(s.kind), \(String(s.created.prefix(10)))): " + (s.title.isEmpty ? s.link : s.title))
                } else if let r = run {
                    Text("Last run (\(r.result), \(String(r.started.prefix(10)))): " + (r.summary.isEmpty ? "no summary" : r.summary))
                } else {
                    Text("No run yet: a sample shows here after its first run.")
                }
            }
            .ui(11.5, mono: true).foregroundStyle(t.text2.color).lineLimit(2).textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
