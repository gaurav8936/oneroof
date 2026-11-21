import AppKit
import SwiftUI
import OneRoofCore

// LAB-2341 · Inbox v4.0 loop panels (handover 4e–4i): each loop item in the console panel in its own words, with what
// a decision does, answered in place. Folded copies are decided together (LoopInboxState.decide writes every outcome).

/// What ↩ and esc do on a loop item (the panel's first and cancel buttons), so the page's keys and the buttons agree.
@MainActor enum InboxLoopActions {
    static func primary(_ i: LoopInbox.Item, model: AppModel, win: WindowState?) {
        let inbox = LoopInboxState.shared
        guard !inbox.busy.contains(i.id) else { return }
        switch i.kind {
        case .failed: inbox.runAgain(i.loopId) { model.refreshLoopInbox() }
        case .missed: inbox.runNow(i.loopId) { model.refreshLoopInbox() }
        case .asks: if let sid = i.sessionId, let it = model.item(sid) { model.reveal(it) }
        case .staged:
            switch i.outcomeKind {
            case "commit", "pr": inbox.approveAndOpenPR(i) { model.refreshLoopInbox() }
            case "file": inbox.decide(i, "applied") { model.refreshLoopInbox() }
            case "report", "slack": inbox.decide(i, "approved", reason: "seen") { model.refreshLoopInbox() }
            default: inbox.decide(i, "approved") { model.refreshLoopInbox() }
            }
        }
    }

    static func cancel(_ i: LoopInbox.Item, model: AppModel) {
        let inbox = LoopInboxState.shared
        guard !inbox.busy.contains(i.id) else { return }
        switch i.kind {
        case .failed: inbox.markSeen(i.loopId) { model.refreshLoopInbox() }
        case .staged: inbox.decide(i, "rejected") { model.refreshLoopInbox() }
        case .asks, .missed: break
        }
    }

    /// The file or page an item opens ("Open proposal", "Open report", "Open file").
    static func open(_ i: LoopInbox.Item, model: AppModel, win: WindowState?) {
        if let p = i.doc?.path { model.openInViewer(p); return }
        if let o = i.outcomes.last { LoopOutcomeLine.open(o, loopId: i.loopId, model: model, win: win) } else { model.openLoop(i.loopId, in: win) }
    }
}

struct InboxLoopPanel: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var inbox = LoopInboxState.shared
    let item: LoopInbox.Item
    var win: WindowState?
    /// Select another item (Related ›).
    var select: (String) -> Void = { _ in }

    @State private var effect: InboxEffect?
    @State private var loop: Loop?

    private var k: ConsoleTokens { t.console }
    private var busy: Bool { inbox.busy.contains(item.id) || inbox.busy.contains(item.loopId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch item.kind {
            case .asks: LoopQuestionCard(model: model, win: win, item: item)
            case .failed: failed
            case .missed: missed
            case .staged:
                switch item.outcomeKind {
                case "commit", "pr": commits
                case "report", "slack": report
                case "file": file
                default: proposal
                }
            }
            if let r = inbox.lastResult[item.id] ?? inbox.lastResult[item.loopId] {
                Text(r).ui(12.5).foregroundStyle(k.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(k.strip.color))
                    .accessibilityLabel("Result: " + r)
            }
            Text(foot).ui(11.5).foregroundStyle(k.dim.color).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }
        .task(id: item.id) { await load() }
    }

    // MARK: Kinds

    /// 4e · a proposal (also an issue or a promotion), repeats folded.
    private var proposal: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline(item.doc?.title ?? InboxRowText.loopTitle(item))
            heading("Evidence")
            if let e = item.doc?.evidence, !e.isEmpty { mono(e) } else { notAvailable("Open proposal") }
            heading("If you approve")
            if let d = item.doc, d.change != nil || d.target != nil {
                mono([[d.change.map { "change  " + $0 }, d.target.map { "target  " + $0 }].compactMap { $0 }.joined(separator: "\n")])
            }
            Text(item.outcomeKind == "proposal"
                 ? "Approving records your yes. Applying it is a separate change that names \(item.doc?.id ?? "this proposal"); the loop never applies it."
                 : "Approving records your yes in the loop's record.")
                .ui(12.5).foregroundStyle(k.text.color).fixedSize(horizontal: false, vertical: true)
            if let why = item.doc?.why { Text("Rule: " + why).ui(12).foregroundStyle(k.dim.color).fixedSize(horizontal: false, vertical: true) }
            heading("About this item")
            rows(aboutRows(related: LoopInbox.relatedReports(item, in: inbox.items)))
            buttons {
                RoofButton("Approve ↩", .primary) { InboxLoopActions.primary(item, model: model, win: win) }.disabled(busy)
                RoofButton("Dismiss esc") { InboxLoopActions.cancel(item, model: model) }.disabled(busy)
                if item.outcomeKind == "proposal", LoopInbox.muteKey(item) != nil {
                    RoofButton("Dismiss and stop re-filing") { inbox.dismissAndMute(item) { model.refreshLoopInbox() } }.disabled(busy)
                        .help("Dismisses every copy and keeps later filings of this proposal out of the Inbox (the loop still writes them to its journal).")
                }
                RoofButton(item.outcomeKind == "issue" ? "Open issue" : "Open proposal") { InboxLoopActions.open(item, model: model, win: win) }
            }
        }
    }

    /// 4g · a report (or a slack note): to read, never red, expires after 7 days.
    private var report: some View {
        let related = LoopInbox.relatedProposal(item, in: inbox.items)
        return VStack(alignment: .leading, spacing: 12) {
            headline(item.outcomes.last?.title ?? InboxRowText.loopTitle(item))
            heading("Finding")
            if let e = item.doc?.evidence, !e.isEmpty { mono(e) } else { mono([item.doc?.title ?? ""]) }
            rows([("Copies", item.copies == 1 ? "1 report" : "\(item.copies) reports with this finding, folded"),
                  ("Expires", "\(LoopInbox.expiryDays) days after it was filed" + (expiry.map { " (" + $0 + ")" } ?? ""))]
                 , link: related.map { r in ("Related", "Proposal · \(InboxRowText.loopTitle(r))" + (r.copies > 1 ? " (×\(r.copies))" : "") + " ›", r.id) })
            buttons {
                RoofButton("Seen ↩", .primary) { InboxLoopActions.primary(item, model: model, win: win) }.disabled(busy)
                RoofButton("Open report") { InboxLoopActions.open(item, model: model, win: win) }
                if let r = related { RoofButton("Open related proposal") { select("loop-" + r.id) } }
            }
        }
    }

    /// 4f · commits on the loop branch → a PR: the commands Approve runs and the change it carries.
    private var commits: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("If you approve, this runs:", big: true)
            if let e = effect, !e.commands.isEmpty {
                mono(e.commands.map { $0.hasPrefix("#") ? $0 : "$ " + $0 })
            } else if effect == nil { Text("Reading the loop branch…").ui(12.5).foregroundStyle(k.dim.color) }
            heading("The change")
            if let e = effect {
                if let m = e.missing { Text(m).ui(12.5).foregroundStyle(k.dim.color).fixedSize(horizontal: false, vertical: true) }
                if !e.commits.isEmpty {
                    mono(Array(e.commits.prefix(5)) + (e.commits.count > 5 ? ["… \(e.commits.count - 5) more"] : []), tint: k.hunk, first: 8)
                }
                if !e.diffstat.isEmpty { Text(e.diffstat).ui(12, mono: true).foregroundStyle(k.dim.color) }
                if !e.diff.isEmpty { diffView(e.diff) }
            } else {
                mono(item.outcomes.map { ($0.link.split(separator: ":").dropFirst().first.map { String($0.prefix(7)) + " " } ?? "") + $0.title })
            }
            if let gate = item.outcomes.compactMap({ $0.detailValue("gate") }).first {
                Text("Last gate: " + gate).ui(12).foregroundStyle(k.needs.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text("Reversible").ui(11, .semibold).foregroundStyle(t.diffAddText.color)
                    .padding(.horizontal, 6).frame(height: 18).background(RoundedRectangle(cornerRadius: 4).fill(t.diffAddFill.color))
                Text("Approve runs the gate first; a PR is only opened, nothing merges until you merge it.").ui(12).foregroundStyle(k.text.color)
            }
            buttons {
                RoofButton(busy ? "Checking…" : "Approve → open PR ↩", .primary) { InboxLoopActions.primary(item, model: model, win: win) }.disabled(busy)
                RoofButton("Open the change") { InboxLoopActions.open(item, model: model, win: win) }
                RoofButton("Dismiss esc") { InboxLoopActions.cancel(item, model: model) }.disabled(busy)
            }
        }
    }

    /// 4i · a data or file update.
    private var file: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline("A data or file update: " + InboxRowText.loopTitle(item))
            heading("If you apply, this changes")
            mono(item.outcomes.map { $0.link.isEmpty ? $0.title : $0.link.replacingOccurrences(of: "file:", with: "") })
            Text("Apply records that the update is in use; the loop never changes your data on its own.")
                .ui(12.5).foregroundStyle(k.text.color).fixedSize(horizontal: false, vertical: true)
            buttons {
                RoofButton("Apply ↩", .primary) { InboxLoopActions.primary(item, model: model, win: win) }.disabled(busy)
                RoofButton("Dismiss esc") { InboxLoopActions.cancel(item, model: model) }.disabled(busy)
                RoofButton("Open file") { InboxLoopActions.open(item, model: model, win: win) }
            }
        }
    }

    /// 4h · a loop stopped at a limit: P0, it cannot continue without you.
    private var failed: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline(InboxRowText.loopTitle(item))
            heading("Why it stopped")
            mono(item.detail.split(separator: "\n").map(String.init))
            if let l = loop { rows([("Stopped by", l.stopReason ?? "a limit"), ("Last run", l.lastRunAt.map { Inbox.age($0) + " ago" } ?? "—")]) }
            buttons {
                RoofButton("Run again ↩", .primary) { InboxLoopActions.primary(item, model: model, win: win) }.disabled(busy)
                RoofButton("Open loop") { model.openLoop(item.loopId, in: win) }
                RoofButton("Pause loop") {
                    inbox.pause(item.loopId) { model.refreshLoopInbox() }
                }.disabled(busy || loop == nil)
                RoofButton("Dismiss esc") { InboxLoopActions.cancel(item, model: model) }.disabled(busy)
                    .help("Takes it out of the Inbox until the loop stops again (was Mark seen).")
            }
        }
    }

    /// 4g (G8) · a loop that missed its scheduled runs.
    private var missed: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline(InboxRowText.loopTitle(item))
            mono([item.detail])
            buttons {
                RoofButton("Run now ↩", .primary) { InboxLoopActions.primary(item, model: model, win: win) }.disabled(busy)
                RoofButton("Open loop") { model.openLoop(item.loopId, in: win) }
            }
            Text("It leaves the Inbox once a run is recorded. If runs keep being missed, check the scheduler (the kit: `ae doctor`).")
                .ui(12).foregroundStyle(k.dim.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Parts

    private var foot: String {
        switch item.kind {
        case .failed: return "A loop that has stopped is P0: it cannot continue without you."
        case .asks: return "Never asked: push, merge, deploy (the loop cannot)."
        case .missed: return "Missed runs wait for a decision; they are never red."
        case .staged:
            switch item.outcomeKind {
            case "commit", "pr": return "Every loop item shows its effect this way: the command it runs and the change it applies."
            case "report", "slack": return "Reports never ask for approval and are never red. Seen keeps it in Decided."
            case "file": return "Apply records the update. It shows in Decided with the change."
            default: return "Loop output is never red unless the loop has stopped. Your decision is kept in Decided" + (item.copies > 1 ? ", for every copy." : ".")
            }
        }
    }

    private var expiry: String? {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: item.when.addingTimeInterval(Double(LoopInbox.expiryDays) * 86_400))
    }

    private func aboutRows(related: [LoopInbox.Item]) -> [(String, String)] {
        var out: [(String, String)] = []
        let f = DateFormatter(); f.dateFormat = "MM-dd"
        if item.copies > 1 {
            out.append(("Copies", "\(item.copies) filings of the same \(item.outcomeKind), \(f.string(from: item.when)) → \(f.string(from: item.lastWhen ?? item.when)). Deciding once closes all \(item.copies)."))
        } else { out.append(("Filed", Inbox.age(item.when) + " ago")) }
        if !related.isEmpty {
            let n = related.reduce(0) { $0 + $1.copies }
            out.append(("Related", "\(n) \(item.loopId) report\(n == 1 ? "" : "s") with the same finding (P2, in the list)"))
        }
        if let p = item.doc?.path { out.append(("File", (p as NSString).abbreviatingWithTildeInPath)) }
        return out
    }

    private func headline(_ s: String) -> some View {
        Text(s).ui(15, .semibold).foregroundStyle(k.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            .accessibilityAddTraits(.isHeader)
    }

    private func heading(_ s: String, big: Bool = false) -> some View {
        Text(s).ui(big ? 15 : 13, .semibold).foregroundStyle(k.text.color).padding(.top, big ? 0 : 4)
    }

    private func mono(_ lines: [String], tint: RGB? = nil, first: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                if let tint, first > 0, l.count > first, !l.hasPrefix("…") {
                    (Text(String(l.prefix(first))).foregroundStyle(tint.color) + Text(String(l.dropFirst(first))).foregroundStyle(k.text.color))
                        .ui(12, mono: true)
                } else {
                    Text(l).ui(12, mono: true).foregroundStyle((l.hasPrefix("#") || l.hasPrefix("…") ? k.dim : k.text).color)
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func diffView(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                Text(l.isEmpty ? " " : l).ui(12, mono: true).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle((l.hasPrefix("@@") || l.hasPrefix("+++") || l.hasPrefix("---") ? k.hunk
                                      : l.hasPrefix("+") ? k.add : l.hasPrefix("-") ? k.del : k.dim).color)
            }
        }
        .textSelection(.enabled)
    }

    private func notAvailable(_ open: String) -> some View {
        Text("Not available · \(open) ↗").ui(12, mono: true).foregroundStyle(k.dim.color)
    }

    private func rows(_ r: [(String, String)], link: (String, String, String)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(r.enumerated()), id: \.offset) { _, x in row(x.0) { Text(x.1).ui(12.5).foregroundStyle(k.text.color) } }
            if let link {
                row(link.0) {
                    Button { select("loop-" + link.2) } label: { Text(link.1).ui(12.5).foregroundStyle(k.link.color) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func row<V: View>(_ key: String, @ViewBuilder _ value: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).ui(12.5).foregroundStyle(k.dim.color).frame(width: 110, alignment: .leading)
            value().fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private func buttons<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        FlowLayout(spacing: 8) { c() }.padding(.top, 4)
    }

    // MARK: Load (off the main thread)

    private func load() async {
        let i = item
        let (l, e): (Loop?, InboxEffect?) = await Task.detached {
            let l = LoopStore().load(i.loopId) ?? LoopInboxState.store().load(i.loopId)
            guard i.kind == .staged, ["commit", "pr"].contains(i.outcomeKind), let l else { return (l, nil) }
            return (l, LoopHarvest.preview(loop: l, title: LoopHarvest.title(l, i.outcomes), tools: .live()))
        }.value
        loop = l
        if ["commit", "pr"].contains(i.outcomeKind) { effect = e ?? InboxEffect(missing: "The loop could not be read.") }
    }
}
