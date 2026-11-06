import AppKit
import SwiftUI
import OneRoofCore

// LAB-2287 · 7b A kind's page (handover 02-7b.png, 03-7b_check.png, pages/7b-kind): the kind (its colour), N of M on,
// its subtypes, blurb and how it is doing in real counts; For you · this week · gap cards; the filter bar (search and
// All · On · Off · Needs setup); the table ON · n over OFF · n with each loop's strip, last · next, who runs it and its
// state (or Set up / Turn on). Replaces LoopFamilyPage on the v7 route. Pure logic: LoopsV7.kindPage (OneRoofCore).

struct LoopKindPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    @ObservedObject private var inbox = LoopInboxState.shared
    let familyId: String
    let actions: LoopsV7Actions
    @State private var chip: LoopsV7.KindChip = .all
    @State private var confirm: LoopsV7.AskAction?
    /// LAB-2295 · LP-2: the Set kind sheet's loops.
    @State private var setKind: [String]?

    static let runsW: CGFloat = 110, lastW: CGFloat = 160, byW: CGFloat = 80, stateW: CGFloat = 104

    private var setupMissing: Set<String> { Set(board.setup.compactMap { k, v in v == .ready ? nil : k }) }

    var body: some View {
        let missing = setupMissing
        let page = LoopsV7.kindPage(family: familyId, rows: board.rows, items: inbox.items, weekRuns: board.weekRuns,
                                    pinned: Set(board.loops.filter(\.pinned).map(\.id)), setupMissing: missing, kitKnown: board.kitKnown)
        let f = nav.filter("7b:" + familyId)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                head(page)
                HStack(alignment: .top, spacing: 14) {
                    card(page.forYou, edge: .forYou)
                    card(page.week, edge: .plain)
                    card(page.gap, edge: .dashed)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    LoopFilterBar(filter: f, kinds: false, placeholder: "Find a \(page.family.title) loop…", stateMenu: false)
                        .frame(maxWidth: 260, alignment: .leading)
                    ForEach(LoopsV7.KindChip.allCases, id: \.self) { c in chipButton(c) }
                    Spacer(minLength: 0)
                }
                table(page, query: f)
            }
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.top)
        .accessibilityLabel("\(page.family.title) loops")
        .alert(LoopWriteConfirm.title(confirm, board: board), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
               presenting: confirm) { a in
            Button(LoopWriteConfirm.button(a)) { LoopWriteConfirm.run(a, board: board, model: model); confirm = nil }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { a in Text(LoopWriteConfirm.message(a, board: board)) }
        .sheet(item: Binding(get: { setKind.map { LoopSetKindRequest(ids: $0) } }, set: { setKind = $0?.ids })) { r in
            LoopSetKindSheet(board: board, ids: r.ids) { setKind = nil }.themed(t.name)
        }
    }

    // MARK: Head

    private func head(_ p: LoopsV7.KindPage) -> some View {
        let k = LoopLook.kind(familyId, theme: t.name)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(p.family.title).ui(28, .semibold).foregroundStyle(k.text.color).accessibilityAddTraits(.isHeader)
                    Text("\(p.on) of \(p.all) on").ui(28, .semibold).foregroundStyle(t.text.color)
                    if !p.subtypes.isEmpty { Text(p.subtypes).ui(13).foregroundStyle(t.text2.color) }
                }
                (Text(p.blurb + " ").foregroundColor(t.text.color) + Text(p.status).bold().foregroundColor(t.text.color))
                    .ui(14).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 860, alignment: .leading)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 10) {
                Segmented(options: LoopsV7.laneOrder.map { ($0, LoopKinds.family($0)?.title ?? $0) },
                          selection: Binding(get: { familyId }, set: { switchKind($0) }))
                    .accessibilityLabel("Kind")
                    .help("Switch kind (clears the search)")
                RoofButton("+ New \(p.family.title) loop", .primary) { actions.newLoopOfKind(familyId) }
                    .help("A new loop of this kind, opened in the editor")
            }
        }
    }

    private func switchKind(_ f: String) {
        guard f != familyId, !nav.stack.isEmpty else { return }
        nav.filters["7b:" + f] = LoopFilter()   // switching kind clears the search
        chip = .all
        nav.stack[nav.stack.count - 1] = .kind(f)
    }

    // MARK: Cards

    private enum Edge { case forYou, plain, dashed }

    private func card(_ c: LoopsV7.KindCard, edge: Edge) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let amber = LoopLook.tone(.needsYou, theme: t.name).text
        return VStack(alignment: .leading, spacing: 6) {
            LoopLabel(c.label)
            Text(c.title).ui(14, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            if !c.text.isEmpty {
                Text(c.text).ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            if !c.asks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(c.asks.enumerated()), id: \.element.id) { i, a in
                        LoopButton(a.button, (edge == .forYou && i == 0) ? .primary : .secondary) { perform(a.action) }
                            .help(a.text)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shape.fill(t.surface.color))
        .overlay {
            switch edge {
            case .dashed: shape.strokeBorder(LoopLook.cardEdge(t.name).color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            default: shape.strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1)
            }
        }
        .overlay(alignment: .leading) {
            if edge == .forYou && !c.asks.isEmpty {
                UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card, style: .continuous)
                    .fill(amber.color).frame(width: 4)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(c.label + ": " + c.title)
    }

    private func perform(_ a: LoopsV7.AskAction) {
        switch a {
        case .runNow, .turnOn: confirm = a
        case .setUp(let id): nav.librarySelected = id; nav.setRoot(.library)   // LAB-2294 · 7h: its setup and Set up
        case .open(let id): nav.open(.loop(id))
        case .review(let loop, let item): nav.open(.needsYou(loop: loop, item: item))
        case .kind(let f): switchKind(f)
        case .setKind(let ids): setKind = ids   // LAB-2295 · LP-2
        }
    }

    // MARK: Chips and table

    private func chipButton(_ c: LoopsV7.KindChip) -> some View {
        let on = chip == c
        return Button { chip = c } label: {
            Text(c.label).ui(12.5, .semibold).foregroundStyle((on ? t.surface : t.text).color)
                .padding(.vertical, 4).padding(.horizontal, 12)
                .background(Capsule().fill(on ? t.text.color : .clear))
                .overlay(Capsule().strokeBorder((on ? t.text : t.separatorStrong).color, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(radius: 12))
        .accessibilityLabel(c.label + (on ? ", selected" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func table(_ p: LoopsV7.KindPage, query: Binding<LoopFilter>) -> some View {
        let missing = setupMissing
        let q = query.wrappedValue.query
        let on = LoopsV7.kindChip(LoopsV7.kindSearch(p.onRows, q), chip, setupMissing: missing)
        let off = LoopsV7.kindChip(LoopsV7.kindSearch(p.offRows, q), chip, setupMissing: missing)
        LoopCard(padding: 0, shadow: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if on.isEmpty && off.isEmpty {
                    HStack(spacing: 10) {
                        Text("No \(p.family.title) loop matches" + (q.trimmingCharacters(in: .whitespaces).isEmpty ? " \(chip.label.lowercased())." : " “\(q)”."))
                            .ui(13).foregroundStyle(t.text2.color)
                        RoofButton("Clear", .plain) { query.wrappedValue = LoopFilter(); chip = .all }
                    }
                    .padding(16)
                }
                if !on.isEmpty {
                    groupLabel("On · \(on.count)")
                    ForEach(on) { r in onRow(r); Rectangle().fill(t.separator.color).frame(height: 1).padding(.leading, 16) }
                }
                if !off.isEmpty {
                    groupLabel("Off · \(off.count)")
                    ForEach(off) { r in offRow(r, needsSetup: missing.contains(r.id)); Rectangle().fill(t.separator.color).frame(height: 1).padding(.leading, 16) }
                }
            }
            .padding(.bottom, 6)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            MicroLabel("Loop").frame(maxWidth: .infinity, alignment: .leading)
            MicroLabel("Watches / does").frame(maxWidth: .infinity, alignment: .leading)
            MicroLabel("Runs").frame(width: Self.runsW, alignment: .leading)
            MicroLabel("Last · Next").frame(width: Self.lastW, alignment: .leading)
            MicroLabel("By").frame(width: Self.byW, alignment: .leading)
            MicroLabel("State").frame(width: Self.stateW, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1).padding(.horizontal, 16) }
    }

    private func groupLabel(_ s: String) -> some View {
        LoopLabel(s).padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
    }

    private func nameCell(_ r: LoopRow, dot: RGB, hollow: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if hollow { Circle().strokeBorder(dot.color, lineWidth: 1.2) } else { Circle().fill(dot.color) }
            }
            .frame(width: 8, height: 8).padding(.top, 5).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).ui(13.5, .semibold).foregroundStyle((r.on ? t.text : t.text2).color).lineLimit(1)
                Text(LoopsV7.kindSubLine(r)).ui(12).foregroundStyle(t.text2.color).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func onRow(_ r: LoopRow) -> some View {
        let lnb = LoopsV7.lastNextBy(r, kitKnown: board.kitKnown, withBy: false)
        return Button { nav.open(.loop(r.id)) } label: {
            HStack(spacing: 10) {
                nameCell(r, dot: r.engine == .kit && !board.kitKnown ? t.text3 : LoopLook.dot(r.state, theme: t.name), hollow: false)
                Text(LoopsV7.shortGoal(r.goal)).ui(12.5).foregroundStyle(t.text.color).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                LoopRunStrip(results: r.strip).frame(width: Self.runsW, alignment: .leading)
                Text(lnb.text).ui(12.5).foregroundStyle(tone(lnb.tone).color).lineLimit(1).frame(width: Self.lastW, alignment: .leading)
                Text(r.engine == .kit ? "kit" : "One Roof").ui(12.5).foregroundStyle(t.text2.color).frame(width: Self.byW, alignment: .leading)
                LoopStateWords(row: r, kitKnown: board.kitKnown).frame(width: Self.stateW, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .hoverHighlight(radius: Radius.row)
        .help(r.goal.isEmpty ? r.name : r.goal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.name), \(LoopLook.onLabel(r, kitKnown: board.kitKnown) ?? "on"), \(LoopsV7.kindSubLine(r)), \(lnb.text), by \(r.engine == .kit ? "kit" : "One Roof")")
        .accessibilityHint("Opens the loop")
    }

    private func offRow(_ r: LoopRow, needsSetup: Bool) -> some View {
        HStack(spacing: 10) {
            Button { nav.open(.loop(r.id)) } label: {
                nameCell(r, dot: t.text3, hollow: true).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Open the loop").accessibilityLabel("Open \(r.name), off")
            Text(LoopsV7.shortGoal(r.goal)).ui(12.5).foregroundStyle(t.text2.color).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(LoopsV7.offRuns(r)).ui(12.5).foregroundStyle(t.text2.color).frame(width: Self.runsW, alignment: .leading)
            Text(r.schedule).ui(12.5).foregroundStyle(t.text2.color).lineLimit(1).frame(width: Self.lastW, alignment: .leading)
            Text(r.engine == .kit ? "kit" : "One Roof").ui(12.5).foregroundStyle(t.text2.color).frame(width: Self.byW, alignment: .leading)
            Group {
                if r.engine == .kit && !board.kitKnown {
                    LoopStateWords(row: r, kitKnown: false)
                } else if needsSetup {
                    RoofButton("Set up") { nav.librarySelected = r.id; nav.setRoot(.library) }
                        .help("Needs a setting or a tool first: the Library says what and where (Set up opens the config at the key)")
                } else {
                    RoofButton("Turn on") { confirm = .turnOn(r.id) }
                        .help("Turns it on; it starts with trial runs that only say what they would do")
                }
            }
            .frame(width: Self.stateW, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private func tone(_ tn: LoopsV7.Tone) -> RGB {
        switch tn {
        case .failed: return t.needsText
        case .missed: return LoopLook.tone(.needsYou, theme: t.name).text
        case .normal: return t.text
        }
    }
}
