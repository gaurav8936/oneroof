import AppKit
import SwiftUI
import OneRoofCore

// LAB-2055 · LAB-2056 (2.0.0, M7): the Loops page's first screen (four family cards with every loop's name as a chip),
// a family's own page (one compact row per loop, two columns when wide) and the pop-out card that shows a loop's
// details over the dimmed page. Colours are tokens; contrast per LAB-2056 (LoopLook in OneRoofCore, tested).

/// A card with a strong edge (LAB-2056: 3:1 against the page and the card in every theme).
struct LoopCard<Content: View>: View {
    @Environment(\.theme) private var t
    var padding: CGFloat = 14
    var shadow = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
            .shadow(color: Color.black.opacity(shadow ? (t.isDark ? 0.3 : 0.08) : 0), radius: 15, y: 10)
    }
}

/// A field label on Loops (ORIGIN, KIND …): the micro label's shape in text2 (LAB-2056: the grey labels were hard to read).
struct LoopLabel: View {
    @Environment(\.theme) private var t
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).ui(TypeScale.micro, .semibold).tracking(0.66).foregroundStyle(t.text2.color)
    }
}

/// A loop's state chip on Loops: a plain Off chip (never struck through), the other states by name.
struct LoopStateChip: View {
    @Environment(\.theme) private var t
    let loop: Loop
    var body: some View {
        let p = LoopLook.pill(loop.state, theme: t.name)
        let label = LoopLook.label(loop)
        Text(label)
            .ui(10.5, .semibold)
            .foregroundStyle(p.text.color)
            .padding(.vertical, 1).padding(.horizontal, 7)
            .background(Capsule().fill(p.fill?.color ?? .clear))
            .overlay {
                switch p.edge {
                case .solid(let c): Capsule().strokeBorder(c.color, lineWidth: 1)
                case .dashed(let c): Capsule().strokeBorder(c.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                default: EmptyView()
                }
            }
            .lineLimit(1).fixedSize()
            .accessibilityLabel("Status: " + label)
    }
}

/// A loop action: today's RoofButton when it can be pressed; when it cannot, a legible label (3:1 or more, no red)
/// with the reason as its tooltip and VoiceOver hint (LAB-2056).
struct LoopButton: View {
    @Environment(\.theme) private var t
    let title: String
    var kind: RoofButton.Kind = .secondary
    var reason: String?
    var action: () -> Void
    init(_ title: String, _ kind: RoofButton.Kind = .secondary, reason: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kind = kind; self.reason = reason; self.action = action
    }
    var body: some View {
        if let reason {
            Button {} label: {
                Text(title).ui(TypeScale.small, .semibold).lineLimit(1)
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .foregroundStyle(LoopLook.disabledLabel(t.name).color)
                    .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                        .strokeBorder(t.separator.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            }
            .buttonStyle(PressStyle())
            .disabled(true)
            .help(reason)
            .accessibilityLabel(title)
            .accessibilityHint(reason)
        } else {
            RoofButton(title, kind, action: action)
        }
    }
}

/// One loop as a compact chip: state dot and name; yours filled, built-in outlined.
struct LoopNameChip: View {
    @Environment(\.theme) private var t
    let loop: Loop
    var open: () -> Void
    var body: some View {
        let c = LoopLook.chip(mine: loop.origin == .mine, theme: t.name)
        Button(action: open) {
            HStack(spacing: 5) {
                StatusDot(status: loop.state.pillStatus, size: 7)
                Text(loop.displayTitle).ui(12, .medium).foregroundStyle(c.text.color).lineLimit(1)
            }
            .padding(.vertical, 3.5).padding(.horizontal, 9)
            .background(Capsule().fill(c.fill?.color ?? .clear))
            .overlay(Capsule().strokeBorder(c.edge.color, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(radius: 12))   // a chip's capsule (a 999 radius draws odd continuous corners)
        .hoverHighlight(radius: 12)
        .help(loop.goal.isEmpty ? loop.displayTitle : loop.goal)
        .accessibilityLabel("\(loop.displayTitle), \(loop.origin.label.lowercased()), \(LoopLook.label(loop).lowercased())")
    }
}

/// LAB-2055 · Kinds: the pinned strip, the family cards (two columns when the page is 960 pt or wider) and the legend.
struct LoopKindsView: View {
    @Environment(\.theme) private var t
    @ObservedObject var board: LoopBoard
    var width: CGFloat
    var openFamily: (String) -> Void
    var openLoop: (String) -> Void

    var body: some View {
        let groups = LoopFamilies.groups(board.loops)
        let columns = LoopFamilies.columns(groups, count: width >= 960 ? 2 : 1)
        let pinned = LoopFamilies.ordered(board.loops.filter(\.pinned))
        VStack(alignment: .leading, spacing: 12) {
            if !pinned.isEmpty {
                HStack(alignment: .center, spacing: 8) {
                    LoopLabel("Pinned")
                    FlowLayout(spacing: 6) { ForEach(pinned) { l in LoopNameChip(loop: l) { openLoop(l.id) } } }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Pinned loops")
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                    VStack(alignment: .leading, spacing: 14) { ForEach(col) { familyCard($0) } }
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            Text("Filled = yours · outlined = built-in · click a loop for its details, a kind's name for its page")
                .ui(11.5).foregroundStyle(t.text2.color)
        }
    }

    private func familyCard(_ g: LoopFamilies.Group) -> some View {
        LoopCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button { openFamily(g.family.id) } label: {
                        Text(g.family.title).ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open \(g.family.title)")
                    Text("\(g.loops.count) loop\(g.loops.count == 1 ? "" : "s")").ui(12).foregroundStyle(t.text2.color)
                    if !g.family.kindTitles.isEmpty {
                        Text(g.family.kindTitles).ui(12).foregroundStyle(t.text2.color).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if let b = g.badge {
                        Text(b).ui(11.5, .semibold).foregroundStyle((g.needsYou > 0 ? t.needsText : t.accentText).color)
                    }
                    Button { openFamily(g.family.id) } label: {
                        Text("Open ›").ui(12, .semibold).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain)
                    .help("Every \(g.family.title) loop with its goal and last result")
                    .accessibilityLabel("Open \(g.family.title) page")
                }
                Text(g.family.blurb).ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if g.loops.isEmpty {
                    Text("No loops of this kind yet. + New loop starts one.").ui(12).foregroundStyle(t.text2.color)
                } else {
                    FlowLayout(spacing: 6) { ForEach(g.loops) { l in LoopNameChip(loop: l) { openLoop(l.id) } } }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(g.accessibilityLabel)
    }
}

/// LAB-2055 · a family's page: what its kinds do and produce, then one compact row per loop (two columns when wide).
struct LoopFamilyPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var board: LoopBoard
    let familyId: String
    var width: CGFloat
    var back: () -> Void
    var openLoop: (String) -> Void
    var startFrom: (Loop) -> Void

    var body: some View {
        let group = LoopFamilies.groups(board.loops).first { $0.id == familyId }
        let family = group?.family ?? LoopKinds.family(familyId) ?? LoopKinds.otherFamily
        let loops = group?.loops ?? []
        let two = width >= 960
        VStack(alignment: .leading, spacing: 12) {
            Button { back() } label: { Text("‹ Loops").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain).keyboardShortcut("[", modifiers: .command).help("Back to the kinds of loops (⌘[)")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(family.title).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                        Text("\(loops.count) loop\(loops.count == 1 ? "" : "s")").ui(12.5).foregroundStyle(t.text2.color)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Text(family.blurb).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    let kinds = family.kinds.compactMap { LoopKinds.kind($0) }
                    if !kinds.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading), count: two ? min(kinds.count, 3) : 1),
                                  alignment: .leading, spacing: 10) {
                            ForEach(kinds) { k in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(k.title).ui(12.5, .semibold).foregroundStyle(t.text.color)
                                    Text(k.purpose).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                                    Text("Produces: " + k.produces).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: two ? 2 : 1),
                              alignment: .leading, spacing: 12) {
                        ForEach(loops) { row($0) }
                    }
                    if loops.isEmpty {
                        Text("No loops of this kind yet. + New loop starts one.").ui(12.5).foregroundStyle(t.text2.color)
                    }
                }
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.top)
        }
    }

    private func row(_ l: Loop) -> some View {
        let last = LoopFamilies.lastResult(runs: board.runsByLoop[l.id] ?? [], lastRunAt: l.lastRunAt)
        let bad = ["fail", "failed", "capped"].contains { last.hasPrefix($0) }
        return LoopCard(padding: 12, shadow: false) {
            VStack(alignment: .leading, spacing: 5) {
                Button { openLoop(l.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            StatusDot(status: l.state.pillStatus)
                            Text(l.displayTitle).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                            Text(l.origin.label).ui(11, .medium).foregroundStyle(t.text2.color)
                            Text(l.externalSchedule ?? l.trigger.label).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                            Spacer(minLength: 6)
                            LoopStateChip(loop: l)
                        }
                        Text(l.goal.isEmpty ? "No goal written" : l.goal).ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(radius: Radius.row))
                .help(l.goal)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(l.displayTitle), \(l.origin.label.lowercased()), \(LoopLook.label(l)), last result \(last). \(l.goal)")
                .accessibilityAddTraits(.isButton)
                HStack(spacing: 8) {
                    Text(last).ui(12, bad ? .semibold : .regular).foregroundStyle((bad ? t.needsText : t.text2).color)
                    Spacer(minLength: 6)
                    if l.origin == .builtIn {
                        RoofButton("Start from this", .plain) { startFrom(l) }
                            .help("A copy of this loop that is yours, opened in the editor")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// LAB-2055 · a loop's details in a card over the dimmed page: width min(760, 90 %), height up to 85 %, scrolling
/// inside. ✕, Esc or a click outside closes it. Everything today's detail page shows and does is in it (LoopDetail).
struct LoopPopout: View {
    @Environment(\.theme) private var t
    let loop: Loop
    let rounds: [LoopRound]
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    var win: WindowState?
    var edit: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
    var close: () -> Void
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.black.opacity(t.isDark ? 0.45 : 0.25)
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .accessibilityHidden(true)
                LoopDetail(loop: loop, rounds: rounds, model: model, board: board, win: win,
                           edit: edit, duplicate: duplicate, delete: delete, close: close,
                           maxHeight: g.size.height * 0.85)
                    .frame(width: min(760, g.size.width * 0.9))
                    .shadow(color: .black.opacity(t.isDark ? 0.5 : 0.22), radius: 28, y: 14)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityLabel("Loop \(loop.displayTitle)")
                    .accessibilityFocused($focused)
                // Esc closes the card.
                Button("Close") { close() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .onAppear { focused = true }
    }
}

/// A neutral tag in the loop header (Mine, Built-in, Pinned): text colour on no fill with a strong edge (LAB-2056).
struct LoopTagChip: View {
    @Environment(\.theme) private var t
    let text: String
    var body: some View {
        Text(text).ui(10.5, .semibold).foregroundStyle(t.text2.color)
            .padding(.vertical, 1).padding(.horizontal, 7)
            .overlay(Capsule().strokeBorder(t.separatorStrong.color, lineWidth: 1))
            .lineLimit(1).fixedSize()
    }
}
