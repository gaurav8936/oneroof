import AppKit
import SwiftUI
import OneRoofCore

/// The v2 toolbar band (handover A1.1-A1.4): the places icon row over the session column (step 1), then — lined up with
/// the centre by the title's own shift (LAB-1783) — the title, Single · Grid · Wall, the Focus step button and + New.
final class V2ToolbarDelegate: NSObject, NSToolbarDelegate {
    private let model: AppModel
    private let win: WindowState
    private weak var controller: MainWindowController?

    static let places = NSToolbarItem.Identifier("oneroof.v2.places")
    static let title = NSToolbarItem.Identifier("oneroof.v2.title")
    static let extras = NSToolbarItem.Identifier("oneroof.v2.extras")
    static let layout = NSToolbarItem.Identifier("oneroof.v2.layout")
    static let step = NSToolbarItem.Identifier("oneroof.v2.step")
    static let new = NSToolbarItem.Identifier("oneroof.v2.new")

    init(model: AppModel, win: WindowState, controller: MainWindowController) {
        self.model = model; self.win = win; self.controller = controller
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        // LAB-1783: no tracking separator (it drew a short line in the band over the column's edge, in some layouts
        // and not others): every column line ends at the band's bottom edge. The title places itself (titleShift).
        [Self.places, Self.title, .flexibleSpace, Self.extras, Self.layout, Self.step, Self.new]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let controller else { return nil }
        let m = model, w = win
        let view: AnyView
        let label: String
        switch id {
        case Self.places: view = AnyView(V2Band(model: m, win: w) { V2PlacesSlot(model: m, win: w, controller: controller) }); label = "Places"
        case Self.title: view = AnyView(V2Band(model: m, win: w, centre: true, fixed: false) { V2TitleView(model: m, win: w, controller: controller) }); label = "Title"
        case Self.extras: view = AnyView(V2Band(model: m, win: w, centre: true) { V2ToolbarExtras(model: m, win: w) }); label = "Player"
        case Self.layout: view = AnyView(V2Band(model: m, win: w, centre: true) { V2LayoutSlot(win: w, controller: controller) }); label = "Layout"
        case Self.step: view = AnyView(V2Band(model: m, win: w, centre: true) { V2StepButton(win: w, controller: controller) }); label = "Focus"
        case Self.new: view = AnyView(V2Band(model: m, win: w, centre: true) { V2NewButton(controller: controller) }); label = "New"
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: id)
        let host = NSHostingView(rootView: view)
        // Every item's width follows its content: the extras (Learn player, Run · Debug) and Single · Grid · Wall
        // appear and disappear, and the title is sized to the room left (LAB-1237), so min/max constraints track the
        // content and the toolbar re-lays the items out instead of drawing one over another or past the window edge.
        host.sizingOptions = [.intrinsicContentSize, .minSize, .maxSize]
        if id == Self.title {
            // The toolbar may squeeze the title to its minimum (it truncates) instead of moving items into ».
            host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        item.view = host
        item.isBordered = false
        item.label = label
        item.visibilityPriority = id == Self.new || id == Self.step ? .high : .standard
        return item
    }
}

/// Toolbar content in the theme of the column under it (the session column's for the places row, the centre's for the rest).
private struct V2Band<Content: View>: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var centre = false
    /// The title is not fixed: the toolbar may squeeze it (it truncates) before it moves anything into » (LAB-1237).
    var fixed = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        let v = content().themed(centre ? model.themes.centre : model.themes.sidebar, scale: 1)
        if fixed { v.fixedSize() } else { v.fixedSize(horizontal: false, vertical: true) }
    }
}

/// The icon row only at step 1 in the Sessions place (elsewhere the rail carries the places).
private struct V2PlacesSlot: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController
    @ObservedObject private var step: WindowStep   // LAB-1736
    init(model: AppModel, win: WindowState, controller: MainWindowController) {
        self.model = model; self.win = win; self.controller = controller; _step = ObservedObject(wrappedValue: win.step)
    }
    var body: some View {
        if (win.focusStep == .sessions && win.place == .sessions) || win.railFolded {   // LAB-1829: or the rail is folded
            V2PlacesIconRow(model: model, win: win, controller: controller).padding(.leading, 4)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

/// LAB-1783 · where the title draws, apart from the controller so a column drag redraws only the title's offset.
final class V2TitleShift: ObservableObject {
    @Published var x: CGFloat = 0
}

private struct V2TitleShiftModifier: ViewModifier {
    @ObservedObject var shift: V2TitleShift
    func body(content: Content) -> some View { content.offset(x: shift.x) }
}

/// "Agentic engineering repo  Claude1 · LAB-AGENTIC", or the place's name ("Home", "Needs you  oldest first").
struct V2TitleView: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController

    var body: some View {
        let (title, sub) = Self.text(model: model, win: win, page: controller.v2Page)
        let room = controller.v2Bar.titleWidth
        // LAB-1237: the title takes only the room the right group leaves; it truncates first, the subtitle goes next.
        if room > 0 {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).ui(14, .bold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail).frame(maxWidth: 360, alignment: .leading)
                if let sub, controller.v2Bar.subtitle { Text(sub).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1).frame(maxWidth: 260, alignment: .leading) }
            }
            .frame(minWidth: 40, maxWidth: CGFloat(room) - 8, alignment: .leading)
            .padding(.leading, 8)
            .modifier(V2TitleShiftModifier(shift: controller.v2TitleShift))   // LAB-1783: text on the centre's content edge
            .barHelp(sub.map { title + "  " + $0 } ?? title)
            .accessibilityElement(children: .combine)
            .onChange(of: title) { kick() }
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    /// A new title may fit where an item went into » before (LAB-1237).
    private func kick() { DispatchQueue.main.async { [weak controller] in controller?.v2KickToolbar() } }

    @MainActor static func text(model: AppModel, win: WindowState, page: String?) -> (String, String?) {
        if let page { return (page, nil) }
        switch win.place {
        case .sessions:
            guard let id = win.selectedId, let item = model.item(id) else { return (win.name, nil) }
            let who = item.account ?? item.session.agent.rawValue.capitalized
            let ticket = item.session.ticket
            return (item.session.name, [who, ticket].compactMap { $0 }.joined(separator: " · "))
        case .needsYou: return ("Needs you", "oldest first")
        default: return (win.place.title, nil)
        }
    }
}

/// Single · Grid · Wall (⌃⌥⌘1-3). Grid arrives in 1.7.0 and Wall in 1.8.0; until then they show and say so.
struct V2LayoutControl: View {
    @Environment(\.theme) private var t
    @ObservedObject var win: WindowState

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SessionLayout.allCases, id: \.self) { l in
                let on = win.layout == l
                let ready = true   // Grid since 1.7.0, Wall since 1.8.0
                Button { if ready { win.layout = l; if l == .grid, win.focusStep < .wide { win.focusStep = l.defaultStep } } } label: {
                    Text(l.title).ui(11, on ? .semibold : .regular)
                        .foregroundStyle(ready ? (on ? t.text.color : t.text2.color) : t.text3.color)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? t.surface.color : .clear))
                }
                .buttonStyle(.plain)
                .barHelp(l == .single ? "Single (⌃⌥⌘1)" : (l == .grid ? "Grid: every live session, two across (scrolls) (⌃⌥⌘2)" : "Wall: every window's live sessions (⌃⌥⌘3)"))
                .accessibilityLabel(l.title + (ready ? "" : ", not available yet"))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.control.color))
    }
}

/// Single · Grid · Wall while the toolbar has room for it (LAB-1237); narrower, the View menu (⌃⌥⌘1-3) has them.
private struct V2LayoutSlot: View {
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController
    var body: some View {
        // LAB-1828: Single · Grid · Wall arrange the Sessions place (and stay while the Wall is open, to go back).
        if controller.v2Bar.layoutControl, V2Layout.showsLayoutControl(inSessions: win.place == .sessions, page: controller.v2Page) {
            V2LayoutControl(win: win)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
}

/// "⤢ Sessions ⌥⌘F": the Focus ladder button. Click steps on; press and hold lists the four steps. The shortcut label
/// goes when the toolbar is narrow (LAB-1237); the tooltip keeps it.
struct V2StepButton: View {
    @Environment(\.theme) private var t
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController
    @ObservedObject private var step: WindowStep   // LAB-1736
    init(win: WindowState, controller: MainWindowController) {
        self.win = win; self.controller = controller; _step = ObservedObject(wrappedValue: win.step)
    }

    var body: some View {
        // LAB-1828: the Focus steps arrange the Sessions place; elsewhere they only folded the dock.
        if V2Layout.showsStepButton(inSessions: win.place == .sessions, page: controller.v2Page) { button } else { Color.clear.frame(width: 1, height: 1) }
    }

    @ViewBuilder private var button: some View {
        let focus = win.focusStep == .focus
        let label = win.focusStep.title
        Menu {
            ForEach(FocusStep.allCases, id: \.self) { s in
                Button("\(s.rawValue) · \(s.title)") { controller.v2SetStep(s) }
            }
        } label: {
            Text((focus ? "" : "⤢ ") + label + (controller.v2Bar.shortcuts ? " ⌥⌘F" : "")).ui(11, focus ? .semibold : .regular).lineLimit(1)
        } primaryAction: {
            controller.v2StepClick()   // LAB-1235: clicks cycle the steps, Focus → Full
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(focus ? t.onAccent.color : t.text.color)
        .padding(.horizontal, 9).frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(focus ? t.accent.color : t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(focus ? .clear : t.separator.color, lineWidth: 1))
        // LAB-1274 (owner): a click cycling the steps and a hold listing them was not discoverable from a one-line tooltip.
        // Hovering shows a hint popover with the whole ladder instead (`StepHintAnchor`); `.help` stays for VoiceOver.
        .help("Click: next step (\(win.focusStep.clicked.title)). ⌥⌘F steps on, ⇧⌥⌘F back\(focus ? ", Esc or ⌥⌘F leave Focus" : ""). Press and hold for the four steps.")
        .overlay(StepHintAnchor(dark: scheme == .dark) {
            AnyView(V2StepHint(step: win.focusStep).environment(\.theme, t).environment(\.colorScheme, scheme))
        })
        .accessibilityLabel("Focus step: \(win.focusStep.title)")
        .accessibilityHint("Click for the next step, press and hold to choose one")
    }
    @Environment(\.colorScheme) private var scheme
}

/// LAB-1274 · the step button's hover hint: what a click and a hold do, and the four steps with the current one marked.
struct V2StepHint: View {
    let step: FocusStep
    @Environment(\.theme) private var t

    static func what(_ s: FocusStep) -> String {
        switch s {
        case .full: return "Rail, sessions, the Plan and the dock"
        case .sessions: return "Sessions and the centre; the Plan on its edge tab"
        case .wide: return "Rail and sessions; more room for the centre"
        case .focus: return "The centre alone; sessions as avatars"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus steps").font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
            VStack(alignment: .leading, spacing: 3) {
                row("Click", "Next step: \(step.clicked.title)")
                row("Hold", "Choose a step from the list")
                row("⌥⌘F", step == .focus ? "Leave Focus · ⇧⌥⌘F back · Esc leaves too" : "Next step · ⇧⌥⌘F back · Esc leaves Focus")
            }
            Rectangle().fill(t.separator.color).frame(height: 1)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(FocusStep.allCases, id: \.self) { s in
                    let on = s == step
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(s.rawValue)").font(.system(size: 11, design: .monospaced)).foregroundStyle(on ? t.accentText.color : t.text3.color)
                            .frame(width: 12, alignment: .trailing)
                        Text(s.title).font(.system(size: 12, weight: on ? .semibold : .regular)).foregroundStyle(t.text.color)
                            .frame(width: 62, alignment: .leading)
                        Text(Self.what(s)).font(.system(size: 11.5)).foregroundStyle(t.text2.color)
                        Spacer(minLength: 0)
                        if on { Text("now").font(.system(size: 10, weight: .semibold)).foregroundStyle(t.accentText.color) }
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? t.selection.color : .clear))
                }
            }
        }
        .padding(12)
        .frame(width: 360, alignment: .leading)
        .background(t.surface.color)
    }

    private func row(_ key: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(key).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(t.accentText.color)
                .frame(width: 44, alignment: .leading)
            Text(text).font(.system(size: 12)).foregroundStyle(t.text.color)
        }
    }
}

/// LAB-1274 · shows `content` in a popover under the view after a short hover. Click-through (never takes a click), the
/// popover ignores the mouse, and any click or key closes it and goes on to where it was going (keys are never kept).
/// An AppKit tracking area, because SwiftUI's hover does not reach views inside an NSToolbar item (LAB-1236).
struct StepHintAnchor: NSViewRepresentable {
    var dark: Bool
    let content: () -> AnyView
    func makeNSView(context: Context) -> HintAnchorView { let v = HintAnchorView(); v.content = content; v.dark = dark; return v }
    func updateNSView(_ v: HintAnchorView, context: Context) { v.content = content; v.dark = dark; v.refresh() }

    final class HintAnchorView: NSView {
        /// ONEROOF_SELFTEST_STEPHINT: a self-test shows the hint without a mouse.
        static let show = Notification.Name("oneroof.v2.stepHint.show")
        var content: (() -> AnyView)?
        var dark = false
        private var area: NSTrackingArea?
        private var popover: NSPopover?
        private var pending: DispatchWorkItem?
        private var monitor: Any?
        private var observer: NSObjectProtocol?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let area { removeTrackingArea(area) }
            let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
            addTrackingArea(a); area = a
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { hide(); if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil; return }
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(forName: Self.show, object: nil, queue: .main) { [weak self] _ in self?.present() }
        }

        override func mouseEntered(with event: NSEvent) {
            pending?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.present() }
            pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
        }
        override func mouseExited(with event: NSEvent) { hide() }

        /// The step changed while the hint shows: redraw it.
        func refresh() {
            guard let popover, let content else { return }
            (popover.contentViewController as? NSHostingController<AnyView>)?.rootView = content()
        }

        func present() {
            guard popover == nil, let content, let window, window.isVisible, !isHiddenOrHasHiddenAncestor else { return }
            let host = NSHostingController(rootView: content())
            host.sizingOptions = [.preferredContentSize]
            let p = NSPopover()
            p.behavior = .applicationDefined
            p.animates = !Motion.reduce
            p.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            p.contentViewController = host
            p.show(relativeTo: bounds, of: self, preferredEdge: .minY)
            host.view.window?.ignoresMouseEvents = true
            popover = p
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { [weak self] e in
                self?.hide(); return e
            }
        }

        func hide() {
            pending?.cancel(); pending = nil
            if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
            popover?.close(); popover = nil
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}

/// "+ New ▾": click = New session; the menu has the other "new" actions.
struct V2NewButton: View {
    @Environment(\.theme) private var t
    let controller: MainWindowController

    var body: some View {
        Menu {
            Button("New Session…  ⌘N") { controller.newSession() }
            Button("New Terminal  ⌘T") { NSApp.sendAction(#selector(AppDelegate.newTerminal(_:)), to: nil, from: nil) }
            Button("New Workspace Window…  ⇧⌘N") { controller.newWorkspace() }
            Button("New Objective…  ⇧⌘O") { controller.newObjective() }
            Button("New Work Item…  ⌃⌘N") { NSApp.sendAction(#selector(AppDelegate.newWorkItem(_:)), to: nil, from: nil) }
        } label: {
            Text("+ New ▾").ui(11.5, .semibold)
        } primaryAction: {
            controller.newSession()
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(t.onAccent.color)
        .padding(.horizontal, 10).frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.accent.color))
        .padding(.trailing, 6)
        .barHelp("New session (⌘N); hold for terminal, window, objective, work item")
        .accessibilityLabel("New session")
    }
}

/// Today's toolbar extras, kept: the Learn mini player while audio is loaded, and Run · Debug in the Editor.
struct V2ToolbarExtras: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var body: some View {
        HStack(spacing: 8) {
            MiniPlayer(player: model.player) {
                model.learnTarget = nil
                model.learnTarget = model.player.pageId
                model.show(.learn, in: win)
            }
            if win.centre == .editor { RunControls(model: model, win: win) }
        }
    }
}

// MARK: Tooltips in the toolbar

/// LAB-1236: SwiftUI's `.help` shows no tooltip inside an NSToolbar item (SwiftUI's tooltips follow mouse-moved events,
/// which the title bar does not pass to a hosted view), so toolbar content also carries an AppKit tooltip: a
/// click-through NSView whose `toolTip` AppKit shows from its own tracking rect. `.help` stays for VoiceOver.
struct BarToolTip: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> ClickThroughView { let v = ClickThroughView(); v.toolTip = text; return v }
    func updateNSView(_ v: ClickThroughView, context: Context) { if v.toolTip != text { v.toolTip = text } }

    final class ClickThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks and drags reach the control underneath
    }
}

extension View {
    /// `.help` plus an AppKit tooltip, for views shown in the toolbar (LAB-1236).
    func barHelp(_ text: String) -> some View { help(text).overlay(BarToolTip(text: text)) }
}
