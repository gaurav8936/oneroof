import AppKit
import SwiftUI
import OneRoofCore

// LAB-2289 · 7d Needs you (handover 05-7d.png, pages/7d-needs-you): "N things wait for you. About M minutes." (N is
// LoopsV7.needsCount, the rail badge's and the landing chip's number; M is an estimate and says so), type tabs with
// counts, the filter bar (search and kind chips), one row per item (dot, title, from line, kind tag, age, chevron; one
// open at a time, questions first) with today's actions in the open row, By kind, and Stale after 7 days (LP-5: staged
// items older than 7 days fold into Stale; "Expire stale" writes `expired` to the ledger only when you press it).

struct LoopsNeedsYou: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var win: WindowState?
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    @ObservedObject private var inbox = LoopInboxState.shared
    /// One loop's items (7c's Results tab), or nil for every loop.
    let loop: String?
    /// The row open on arrival.
    let open: String?
    @State private var type: LoopsV7.NeedsType = .all
    @State private var expanded: String?
    @State private var staleOpen = false
    @State private var confirmExpire = false
    @State private var arrived = false

    var body: some View {
        let all = inbox.items
        let f = nav.filter("7d")
        let scoped = all.filter { loop == nil || $0.loopId == loop }
        let counts = LoopsV7.needsCounts(scoped)
        let list = LoopsV7.needsList(scoped, type: type, family: f.wrappedValue.family, query: f.wrappedValue.query, rows: board.rows)
        HStack(alignment: .top, spacing: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    title(all, scoped: scoped)
                    typeTabs(counts)
                    LoopFilterBar(filter: f, kinds: true, placeholder: "Search items or loops…", stateMenu: false)
                    rows(list, filtered: !f.wrappedValue.isEmpty || type != .all, clear: { f.wrappedValue = LoopFilter(); type = .all })
                }
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.top)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            VStack(alignment: .leading, spacing: 14) {
                byKind(scoped)
                staleCard(stale: list.stale)
            }
            .frame(width: 290, alignment: .topLeading)
        }
        .onAppear { if !arrived { arrived = true; expanded = open ?? list.fresh.first { $0.kind == .asks }?.id } }
        .alert("Expire \(list.stale.count) stale item\(list.stale.count == 1 ? "" : "s")?", isPresented: $confirmExpire) {
            Button("Expire") { expire(list.stale) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each is written to the outcome ledger as expired (the same row `ae loops ledger --decide <id> expired` writes). The loop reads it next run and stops proposing the same thing. Nothing is pushed, merged or deleted.")
        }
    }

    // MARK: Title and tabs

    private func title(_ all: [LoopInbox.Item], scoped: [LoopInbox.Item]) -> some View {
        // N is the one Needs you count (rail badge, landing chip); with a loop chosen, that loop's share of it.
        let n = loop == nil ? LoopsV7.needsCount(items: all) : scoped.count
        let secs = LoopsV7.estimateSeconds(scoped)
        return VStack(alignment: .leading, spacing: 4) {
            Text(LoopsV7.needsHeadline(count: n, seconds: secs)).ui(24, .semibold).foregroundStyle(t.text.color)
                .accessibilityAddTraits(.isHeader)
                .help("The minutes are an estimate: 5 min per PR, 1 min per proposal, 30 s per report or other item")
            HStack(spacing: 8) {
                Text(n > 0 ? "The minutes are an estimate (5 min per PR, 1 per proposal, 30 s for anything else)." : "Every loop item is decided.")
                    .ui(12).foregroundStyle(t.text2.color)
                if let loop {
                    Text("From " + (board.row(loop)?.name ?? loop)).ui(12, .semibold).foregroundStyle(t.text.color)
                    Button { nav.back(); nav.open(.needsYou(loop: nil, item: nil)) } label: {
                        Text("Show every loop ›").ui(12, .medium).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func typeTabs(_ c: [LoopsV7.NeedsType: Int]) -> some View {
        HStack(spacing: 8) {
            ForEach(LoopsV7.NeedsType.allCases, id: \.self) { ty in
                let n = c[ty] ?? 0
                if ty == .all || n > 0 || [.questions, .commits, .proposals, .reports].contains(ty) {
                    let on = type == ty
                    Button { type = ty; expanded = nil } label: {
                        HStack(spacing: 4) {
                            Text(ty.label).ui(12.5, .semibold)
                            Text("\(n)").ui(12.5, on ? .semibold : .regular).opacity(on ? 1 : 0.75)
                        }
                        .foregroundStyle((on ? t.surface : t.text).color)
                        .padding(.vertical, 5).padding(.horizontal, 12)
                        .background(Capsule().fill(on ? t.text.color : .clear))
                        .overlay(Capsule().strokeBorder((on ? t.text : t.separatorStrong).color, lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle(radius: 12))
                    .accessibilityLabel("\(ty.label), \(n)" + (on ? ", selected" : ""))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Rows

    @ViewBuilder private func rows(_ list: (fresh: [LoopInbox.Item], stale: [LoopInbox.Item]), filtered: Bool, clear: @escaping () -> Void) -> some View {
        LoopCard(padding: 0, shadow: false) {
            VStack(alignment: .leading, spacing: 0) {
                if list.fresh.isEmpty && list.stale.isEmpty {
                    HStack(spacing: 10) {
                        Text(filtered ? "No item matches." : "Nothing waits for you.").ui(13).foregroundStyle(t.text2.color)
                        if filtered { RoofButton("Clear", .plain) { clear() } }
                    }
                    .padding(16)
                }
                ForEach(Array(list.fresh.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Rectangle().fill(t.separator.color).frame(height: 1) }
                    row(item)
                }
                if !list.stale.isEmpty {
                    Rectangle().fill(t.separator.color).frame(height: 1)
                    HStack(spacing: 10) {
                        Button { staleOpen.toggle() } label: {
                            HStack(spacing: 6) {
                                Text(staleOpen ? "▾" : "▸").ui(12).foregroundStyle(t.text2.color)
                                LoopLabel("Stale · \(list.stale.count) · staged more than 7 days ago")
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel((staleOpen ? "Hide" : "Show") + " \(list.stale.count) stale items")
                        Spacer()
                        RoofButton("Expire stale…", .danger) { confirmExpire = true }
                            .disabled(list.stale.contains { inbox.busy.contains($0.id) })
                            .help("Writes expired to the ledger for each stale item, after you confirm. Never automatic.")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if staleOpen {
                        ForEach(list.stale) { item in
                            Rectangle().fill(t.separator.color).frame(height: 1)
                            row(item)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: LoopInbox.Item) -> some View {
        let isOpen = expanded == item.id
        let fam = board.row(item.loopId)?.family ?? "other"
        let k = LoopLook.kind(fam, theme: t.name)
        let dot = LoopLook.tone(LoopsV7.needsDot(item), theme: t.name).text
        let q = item.kind == .asks ? question(item) : nil
        return VStack(alignment: .leading, spacing: 0) {
            Button { expanded = isOpen ? nil : item.id } label: {
                HStack(alignment: .center, spacing: 12) {
                    Circle().fill((item.kind == .missed ? t.text3 : dot).color).frame(width: 8, height: 8).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q?.rowTitle ?? LoopsV7.needsTitle(item)).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        Text(q.map { [$0.loopTitle, $0.command].compactMap { $0 }.joined(separator: " · ") } ?? LoopsV7.needsFrom(item))
                            .ui(12).foregroundStyle(t.text2.color).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(LoopKinds.family(fam)?.title ?? fam).ui(11, .semibold).foregroundStyle(k.text.color)
                        .padding(.horizontal, 7).padding(.vertical, 1.5).background(Capsule().fill(k.fill.color))
                        .frame(width: 90, alignment: .leading)
                    Text(LoopsV7.age(item.when)).ui(12.5).foregroundStyle(t.text2.color).frame(width: 70, alignment: .leading)
                    Text(isOpen ? "▾" : "›").ui(13).foregroundStyle(t.text2.color).frame(width: 14)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(radius: Radius.row))
            .hoverHighlight(radius: Radius.row)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(q?.rowTitle ?? LoopsV7.needsTitle(item)), \(LoopsV7.needsFrom(item)), \(LoopKinds.family(fam)?.title ?? fam), \(LoopsV7.age(item.when)) ago")
            .accessibilityHint(isOpen ? "Closes it" : "Opens it with its actions")
            if isOpen {
                Group {
                    if let q { LoopQuestionAnswers(model: model, win: win, question: q, compact: true) }
                    else { LoopNeedDetail(model: model, item: item, win: win, embedded: true) }
                }
                .padding(.leading, 36).padding(.trailing, 16).padding(.bottom, 14)
            }
        }
    }

    private func question(_ item: LoopInbox.Item) -> LoopQuestion {
        LoopQuestion.make(item: item, loop: board.loops.first { $0.id == item.loopId },
                          prompt: model.loopRoundPrompt(item.sessionId))
    }

    // MARK: Side cards

    private func byKind(_ items: [LoopInbox.Item]) -> some View {
        LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 0) {
                LoopLabel("By kind").padding(.bottom, 6)
                ForEach(LoopsV7.needsByKind(items, rows: board.rows), id: \.family) { r in
                    let k = LoopLook.kind(r.family, theme: t.name)
                    Button { nav.filters["7d", default: LoopFilter()].family = r.count == 0 ? nil : r.family } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(LoopKinds.family(r.family)?.title ?? r.family).ui(13, .semibold).foregroundStyle(k.text.color)
                            Spacer(minLength: 8)
                            Text(r.count == 0 ? "0" : "\(r.count) · \(r.words)").ui(12.5, .semibold).foregroundStyle(t.text.color)
                                .multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 7).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                    .help("Show only \(LoopKinds.family(r.family)?.title ?? r.family) items")
                    .accessibilityLabel("\(LoopKinds.family(r.family)?.title ?? r.family): \(r.count) \(r.words)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func staleCard(stale: [LoopInbox.Item]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LoopLabel("Stale after 7 days")
            Text("Undecided items staged more than 7 days ago fold into Stale so the list can empty. Expire stale writes expired to the ledger (only when you press it): the loop is told and stops proposing the same thing."
                 + (stale.isEmpty ? " None is stale now." : " \(stale.count) stale now."))
                .ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.control.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
    }

    private func expire(_ items: [LoopInbox.Item]) {
        for i in items { inbox.decide(i, "expired") { model.refreshLoopInbox() } }
    }
}
