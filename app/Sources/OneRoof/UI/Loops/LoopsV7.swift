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
    case kind(String)                               // 7b A kind's page (LAB-2287)
    case needsYou(loop: String?, item: String?)     // 7d Needs you (LAB-2289)
    case runs                                       // 7j Runs and their rounds (LAB-2293)
    // LAB-2291 · LAB-2292 · LAB-2293 (lane B): a day from This week, Tonight, one run, a run's report.
    case day(Date, loop: String?)                   // 7f at that day (the loop's lane marked)
    case tonight                                    // 7g
    case run(String)                                // 7j with that run selected
    case report(LoopsRunRef)                        // 7k
    case loop(String)                               // 7c One loop · Now (LAB-2288)
    // LAB-2294 · LAB-2295 (lane C): a new loop (its draft is LoopsNav.draft) and editing one.
    case newLoop                                    // 7i
    case edit(id: String, name: String)             // 7m

    var title: String {
        switch self {
        case .kind(let f): return LoopKinds.family(f)?.title ?? f
        case .needsYou(let l, _): return l == nil ? "Needs you" : "Needs you · " + (l ?? "")
        case .runs, .run: return "Runs"
        case .day(let d, _): return LoopsV7.dayTitle(d)
        case .tonight: return "Tonight"
        case .report(let r): return r.name + " › Run " + r.id
        case .loop(let id): return id
        case .newLoop: return "New loop"
        case .edit(_, let name): return name + " › Edit"
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
    /// LAB-2295 · 7i: the new loop's starting draft (blank, from an example, or a duplicate).
    @Published var draft: LoopDraft?
    /// Bumped by every newLoop, so 7i starts again from the new draft.
    @Published var draftSerial = 0
    /// LAB-2294 · 7h: the Library's selected loop (7c's How it's set up opens it there).
    @Published var librarySelected: String?

    /// 7i with a draft.
    func newLoop(_ d: LoopDraft) { draft = d; draftSerial += 1; if stack.last != .newLoop { stack.append(.newLoop) } }

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
    /// LAB-2287 · + New <kind> loop: the editor with the kind set.
    var newLoopOfKind: (String) -> Void = { _ in }
    /// LAB-2288 · 2.0.5's pop-out (every field, setup, outcomes, rounds) until 7h/7m land, and the editor / the file.
    var popout: (String) -> Void = { _ in }
    var edit: (String) -> Void = { _ in }
    /// LAB-2295: the full 2.0.5 editor sheet for what 7i and 7m don't draw (a hosted agent's connection).
    var fullEditor: (LoopDraft) -> Void = { _ in }
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
            if !pageOwnsActions {
                pauseButton
                RoofButton("+ New loop", .primary) { actions.newLoop() }
                    .help("A new loop: describe it, or start from an example (⌘N in the palette)")
            }
        }
    }

    /// LAB-2287–2289: 7b, 7c and 7d draw their own actions (kind switch and + New <kind> loop · Run now, Pause, Edit).
    private var pageOwnsActions: Bool {
        // LAB-2295: 7i and 7m end with their own Save buttons (no Pause all / + New loop over a form).
        switch nav.stack.last { case .kind?, .loop?, .needsYou?, .newLoop?, .edit?: return true; default: return false }
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

    /// LAB-2294 · 7n: roofd down (its own status line), everything paused, kit unknown, a failed write (Try again ·
    /// Dismiss), and on the landing the loops that need a setting (LoopsStates.swift).
    @ViewBuilder private var banners: some View {
        LoopsStateBanners(model: model, board: board)
        if nav.stack.isEmpty, nav.root == .byKind, !board.setupItems.isEmpty, !board.loops.isEmpty, !forceEmpty {
            LoopsNeedsSetupCard(model: model, board: board)
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
                LoopsWeek(board: board, nav: nav, actions: actions)   // 7e (LAB-2291)
            case .today:
                LoopsToday(model: model, board: board, nav: nav, actions: actions, day: nil, focus: nil)   // 7f (LAB-2292)
            case .library:
                LoopsLibrary(model: model, board: board, nav: nav, actions: actions)   // 7h (LAB-2294)
            }
        case .kind(let f)?:
            LoopKindPage(model: model, board: board, nav: nav, familyId: f, actions: actions)   // LAB-2287 · 7b
        case .needsYou(let loop, let item)?:
            LoopsNeedsYou(model: model, win: win, board: board, nav: nav, loop: loop, open: item)   // LAB-2289 · 7d
        case .loop(let id)?:
            LoopPage(model: model, win: win, board: board, nav: nav, loopId: id, actions: actions)   // LAB-2288 · 7c
        case .runs?:
            LoopRunsPage(model: model, board: board, nav: nav, actions: actions, selected: nil)   // 7j (LAB-2293)
        case .run(let id)?:
            LoopRunsPage(model: model, board: board, nav: nav, actions: actions, selected: id)
        case .day(let d, let loop)?:
            LoopsToday(model: model, board: board, nav: nav, actions: actions, day: d, focus: loop)
        case .tonight?:
            LoopsTonight(model: model, board: board, nav: nav, actions: actions)   // 7g (LAB-2292)
        case .report(let r)?:
            LoopRunReport(model: model, board: board, nav: nav, actions: actions, run: r)   // 7k (LAB-2293)
        case .newLoop?:
            LoopNew(model: model, board: board, nav: nav, actions: actions, start: nav.draft ?? LoopDraft.new())   // 7i (LAB-2295)
                .id(nav.draftSerial)
        case .edit(let id, _)?:
            LoopEdit(model: model, board: board, nav: nav, actions: actions, loopId: id)   // 7m (LAB-2295)
                .id(id)
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
    /// LAB-2287 · 7b and 7d word the search for their list and draw their own chips instead of the state menu.
    var placeholder = "Search a loop, what it does or its kind"
    var stateMenu = true
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text3.color).accessibilityHidden(true)
                TextField(placeholder, text: $filter.query)
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
            if stateMenu { Menu {
                Button("Any state") { filter.state = nil }
                ForEach(LoopFilter.State.allCases, id: \.self) { s in Button(s.label) { filter.state = s } }
            } label: {
                Text((filter.state?.label ?? "Any state") + "  ▾").ui(12.5, .medium).foregroundStyle(t.text.color)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("State: " + (filter.state?.label ?? "any")) }
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
