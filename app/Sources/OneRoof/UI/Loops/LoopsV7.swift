import AppKit
import SwiftUI
import OneRoofCore

// LAB-2286 · Loops v7.0 shell (Claude Design handover 7a–7n, 2026-11-06): the header (title, By kind · This week ·
// Today · Library · N, Pause all, + New loop), a route stack with a breadcrumb for drill-downs (⌘[ pops), the one filter
// bar, and the place's banners. Screens not built yet route to today's views so nothing in NO_REGRESSION.md is lost:
//   This week → Activity (outcomes table, runs, the list and Tonight) · Today → Tonight + last night + runs ·
//   Library → the kinds cards and the Gallery (behind the filter bar) · a kind → the family page · a loop → the
//   pop-out card · Needs you → today's loop items with their actions · Runs → the runs card.

/// The Segmented roots (7a, 7e, 7f, 7h).
enum LoopsRoot: String, CaseIterable {
    case byKind, thisWeek, today, library

    /// The saved `loops.view` (Prefs.viewState) in today's spelling or 2.0.5's ("kinds", "activity").
    init(saved: String) {
        switch saved {
        case "activity", LoopsRoot.thisWeek.rawValue: self = .thisWeek
        case LoopsRoot.today.rawValue: self = .today
        case LoopsRoot.library.rawValue: self = .library
        default: self = .byKind
        }
    }
}

/// Drill-downs that push on the root (shown with a breadcrumb).
enum LoopsRoute: Hashable {
    case kind(String)                               // 7b (today: the family page)
    case needsYou(loop: String?, item: String?)     // 7d (today: the loop items and their actions)
    case runs                                       // 7j (today: the runs card)

    var title: String {
        switch self {
        case .kind(let f): return LoopKinds.family(f)?.title ?? f
        case .needsYou(let l, _): return l == nil ? "Needs you" : "Needs you · " + (l ?? "")
        case .runs: return "Runs"
        }
    }
}

/// The place's navigation: the root (remembered), the stack of drill-downs, a filter per screen.
final class LoopsNav: ObservableObject {
    @Published var root: LoopsRoot { didSet { if persist { Prefs.viewState.set(root.rawValue, forKey: "loops.view") } } }
    @Published var stack: [LoopsRoute] = []
    /// One filter per screen ("7h", "7b:watch" …), kept while the window is open.
    @Published var filters: [String: LoopFilter] = [:]
    /// Self-tests set the view without saving it.
    var persist = true

    init() { root = LoopsRoot(saved: Prefs.viewState.string(forKey: "loops.view") ?? "") }

    func setRoot(_ r: LoopsRoot) { stack = []; root = r }
    func open(_ r: LoopsRoute) { if stack.last != r { stack.append(r) } }
    func back() { _ = stack.popLast() }
    func filter(_ screen: String) -> Binding<LoopFilter> {
        Binding(get: { self.filters[screen] ?? LoopFilter() }, set: { self.filters[screen] = $0 })
    }
}

/// What the shell asks its host (LoopsView keeps the editor, the pop-out, the delete alert and today's Activity).
struct LoopsV7Actions {
    var openLoop: (String) -> Void
    var newLoop: () -> Void
    var startFrom: (Loop) -> Void
}

struct LoopsV7Shell<Activity: View, Empty: View>: View {
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2
    @ObservedObject var model: AppModel
    var win: WindowState?
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    /// 2.0.5's Activity (outcomes table, runs, list, Tonight): This week until 7e lands.
    @ViewBuilder var activity: () -> Activity
    /// The no-loops card (7n until it lands).
    @ViewBuilder var empty: () -> Empty
    var forceEmpty = false
    @State private var width: CGFloat = 1100
    @State private var gallery = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            banners
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28).padding(.top, 22).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if let top = nav.stack.last {
                LoopsBreadcrumb(trail: nav.stack.map(\.title), current: top.title) { nav.back() } home: { nav.stack = [] }
            } else {
                Text("Loops").ui(TypeScale.display, .semibold).tracking(-0.5).foregroundStyle(t.text.color)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 12)
            if nav.stack.isEmpty {
                Segmented(options: [(LoopsRoot.byKind, "By kind"), (.thisWeek, "This week"), (.today, "Today"), (.library, "Library · \(board.loops.count)")],
                          selection: Binding(get: { nav.root }, set: { nav.setRoot($0) }))
                    .help("By kind: what each kind of loop is doing · This week · Today · Library: every loop's definition")
                    .accessibilityLabel("Loops view")
            }
            pauseButton
            RoofButton("+ New loop", .primary) { actions.newLoop() }
                .help("A new loop: describe it, or start from an example (⌘N in the palette)")
        }
    }

    /// Pause all / Resume all (One Roof's loops; the kit's loops keep their launchd schedule until turned off).
    @ViewBuilder private var pauseButton: some View {
        if board.loops.contains(where: { $0.state == .paused }) && !board.loops.contains(where: { $0.state.isActive }) {
            RoofButton("Resume all") { board.resumeAll() }
                .help("Resumes One Roof's paused loops")
        } else {
            RoofButton("⏸ Pause all") { board.pauseAll() }.disabled(board.loops.isEmpty)
                .help("Pauses One Roof's loops that are on. The kit's loops keep their schedule: pausing them from here is not connected yet (`ae loops off <name>` turns one off).")
        }
    }

    // MARK: Banners (7n until it lands)

    @ViewBuilder private var banners: some View {
        if let e = board.error {
            Text(e).ui(12.5).foregroundStyle(t.needsText.color).textSelection(.enabled)
                .accessibilityLabel("Error: " + e)
        }
        if !board.kitKnown {
            let p = LoopLook.tone(.needsYou, theme: t.name)
            Text("Kit state unknown: `ae loops list` could not be read, so the kit's loops show as unknown, never as off. One Roof's own loops are shown as they are.")
                .ui(12.5).foregroundStyle(p.text.color)
                .padding(.vertical, 7).padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(p.fill.color))
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch nav.stack.last {
        case nil:
            switch nav.root {
            case .byKind:
                if board.loops.isEmpty || forceEmpty { empty() } else {
                    ScrollView {
                        LoopsLanding(model: model, board: board, nav: nav, actions: actions).padding(.bottom, 8)
                    }
                    .defaultScrollAnchor(.top)
                    .accessibilityLabel("Loops by kind")
                }
            case .thisWeek:
                activity()   // 7e lands later: today's Activity keeps every outcome, run and list row
            case .today:
                ScrollView {
                    HStack(alignment: .top, spacing: 18) {
                        LoopRunsView(model: model, board: board).frame(maxWidth: .infinity, alignment: .top)
                        V2TonightPanel(model: model, board: board).frame(width: 280)
                    }
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.top)
            case .library:
                library
            }
        case .kind(let f)?:
            LoopFamilyPage(board: board, familyId: f, width: width, back: { nav.back() },
                           openLoop: actions.openLoop, startFrom: actions.startFrom)
        case .needsYou(let loop, let item)?:
            LoopsNeedsList(model: model, win: win, loop: loop, selected: item, openLoop: actions.openLoop)
        case .runs?:
            ScrollView { LoopRunsView(model: model, board: board).padding(.bottom, 8) }.defaultScrollAnchor(.top)
        }
    }

    /// Library (7h until it lands): the filter bar over every loop; with no filter, the kinds cards (or the Gallery).
    @ViewBuilder private var library: some View {
        let f = nav.filter("7h")
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LoopFilterBar(filter: f)
                RoofButton(gallery ? "‹ Kinds" : "Gallery") { gallery.toggle() }
                    .help("The kinds of loops, what each produces, and a real sample of each")
            }
            ScrollView {
                Group {
                    if !f.wrappedValue.isEmpty {
                        LoopsFilteredList(board: board, filter: f, openLoop: actions.openLoop)
                    } else if gallery {
                        LoopGalleryView(board: board, openLoop: actions.openLoop, startFrom: actions.startFrom)
                    } else {
                        LoopKindsView(board: board, width: width, openFamily: { nav.open(.kind($0)) }, openLoop: actions.openLoop)
                    }
                }
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.top)
        }
    }
}

// MARK: - Breadcrumb

/// "‹ Loops › Watch": every step is a link back; ⌘[ goes back one step.
struct LoopsBreadcrumb: View {
    @Environment(\.theme) private var t
    let trail: [String]
    let current: String
    var back: () -> Void
    var home: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: home) {
                Text("‹ Loops").ui(TypeScale.title, .semibold).foregroundStyle(t.accentText.color)
            }
            .buttonStyle(.plain).help("Back to Loops")
            .accessibilityLabel("Back to Loops")
            ForEach(Array(trail.dropLast().enumerated()), id: \.offset) { _, step in
                Text("›").ui(TypeScale.title).foregroundStyle(t.text3.color).accessibilityHidden(true)
                Text(step).ui(TypeScale.title, .semibold).foregroundStyle(t.text2.color)
            }
            Text("›").ui(TypeScale.title).foregroundStyle(t.text3.color).accessibilityHidden(true)
            Text(current).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Button("", action: back).keyboardShortcut("[", modifiers: .command).frame(width: 0, height: 0).opacity(0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - The one filter bar (search · kind · state)

struct LoopFilterBar: View {
    @Environment(\.theme) private var t
    @Binding var filter: LoopFilter
    var kinds = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text3.color).accessibilityHidden(true)
                TextField("Search a loop, what it does or its kind", text: $filter.query)
                    .textFieldStyle(.plain).ui(13).focused($focused)
                    .accessibilityLabel("Search loops")
                Button("", action: { focused = true }).keyboardShortcut("f", modifiers: .command).frame(width: 0, height: 0).opacity(0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separator.color))
            if kinds {
                ForEach(LoopsV7.laneOrder, id: \.self) { fid in
                    let on = filter.family == fid
                    let k = LoopLook.kind(fid, theme: t.name)
                    chip(LoopKinds.family(fid)?.title ?? fid, on: on, text: k.text, fill: k.fill) { filter.family = on ? nil : fid }
                }
            }
            Menu {
                Button("Any state") { filter.state = nil }
                ForEach(LoopFilter.State.allCases, id: \.self) { s in Button(s.label) { filter.state = s } }
            } label: {
                Text((filter.state?.label ?? "Any state") + "  ▾").ui(12.5, .medium).foregroundStyle(t.text.color)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("State: " + (filter.state?.label ?? "any"))
            if !filter.isEmpty {
                RoofButton("Clear", .plain) { filter = LoopFilter() }
            }
        }
    }

    private func chip(_ title: String, on: Bool, text: RGB, fill: RGB, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ui(12, .semibold).foregroundStyle((on ? text : t.text2).color)
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Capsule().fill(on ? fill.color : .clear))
                .overlay(Capsule().strokeBorder((on ? text : t.separatorStrong).color, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(radius: 12))
        .accessibilityLabel("Kind " + title + (on ? ", selected" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Rows that match a filter, one LoopLine each, with the empty line and Clear.
struct LoopsFilteredList: View {
    @Environment(\.theme) private var t
    @ObservedObject var board: LoopBoard
    @Binding var filter: LoopFilter
    var openLoop: (String) -> Void

    var body: some View {
        let rows = LoopsV7.filter(board.rows, filter).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        LoopCard(padding: 10) {
            if rows.isEmpty {
                HStack(spacing: 10) {
                    Text(LoopsV7.emptyLine(filter)).ui(13).foregroundStyle(t.text2.color)
                    RoofButton("Clear", .plain) { filter = LoopFilter() }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(6)
            } else {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows) { r in
                        LoopLine(row: r, kitKnown: board.kitKnown, showKind: true, open: { openLoop(r.id) })
                    }
                }
            }
        }
    }
}

// MARK: - Needs you (7d until it lands)

/// The loop items (one per decision) with today's actions; the title's count is the rail badge's.
struct LoopsNeedsList: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var win: WindowState?
    @ObservedObject private var inbox = LoopInboxState.shared
    let loop: String?
    @State var selected: String?
    var openLoop: (String) -> Void

    var body: some View {
        let items = inbox.items.filter { loop == nil || $0.loopId == loop }
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(LoopsV7.needsCount(items: items)) need\(items.count == 1 ? "s" : "") you" + (loop == nil ? "" : " from this loop")
                     + (LoopsV7.estimateSeconds(items) > 0 ? " · " + LoopsV7.estimateLabel(LoopsV7.estimateSeconds(items)) + " (estimate)" : ""))
                    .ui(13, .semibold).foregroundStyle(t.text2.color)
                    .help("Estimate: 5 min per PR, 1 min per proposal, 30 s per report or other item")
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { i in
                            Button { selected = i.id } label: { LoopNeedRow(item: i, selected: (selected ?? items.first?.id) == i.id) }
                                .buttonStyle(.plain)
                        }
                        if items.isEmpty { Text("Nothing needs you here.").ui(13).foregroundStyle(t.text2.color).padding(8) }
                    }
                }
            }
            .frame(width: 340)
            if let i = items.first(where: { $0.id == (selected ?? items.first?.id) }) {
                LoopCard(padding: 0) { LoopNeedDetail(model: model, item: i, win: win) }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}
