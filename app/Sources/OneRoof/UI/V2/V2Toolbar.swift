import AppKit
import SwiftUI
import OneRoofCore

/// The v2 toolbar band (handover A1.1-A1.4): the places icon row over the session column (step 1), then — lined up with
/// the centre by a tracking separator — the title, Single · Grid · Wall, the Focus step button and + New.
final class V2ToolbarDelegate: NSObject, NSToolbarDelegate {
    private let model: AppModel
    private let win: WindowState
    private weak var controller: MainWindowController?
    private weak var splitView: NSSplitView?
    /// The divider between the session column (or rail) and the centre.
    private let centreDivider: Int

    static let places = NSToolbarItem.Identifier("oneroof.v2.places")
    static let centreEdge = NSToolbarItem.Identifier("oneroof.v2.centreEdge")
    static let title = NSToolbarItem.Identifier("oneroof.v2.title")
    static let extras = NSToolbarItem.Identifier("oneroof.v2.extras")
    static let layout = NSToolbarItem.Identifier("oneroof.v2.layout")
    static let step = NSToolbarItem.Identifier("oneroof.v2.step")
    static let new = NSToolbarItem.Identifier("oneroof.v2.new")

    init(model: AppModel, win: WindowState, controller: MainWindowController, splitView: NSSplitView, centreDivider: Int) {
        self.model = model; self.win = win; self.controller = controller; self.splitView = splitView; self.centreDivider = centreDivider
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.places, Self.centreEdge, Self.title, .flexibleSpace, Self.extras, Self.layout, Self.step, Self.new]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let controller else { return nil }
        if id == Self.centreEdge, let splitView {
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: splitView, dividerIndex: centreDivider)
        }
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
    var body: some View {
        if win.focusStep == .sessions && win.place == .sessions {
            V2PlacesIconRow(model: model, win: win, controller: controller).padding(.leading, 4)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }
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
        if controller.v2Bar.layoutControl { V2LayoutControl(win: win) } else { Color.clear.frame(width: 1, height: 1) }
    }
}

/// "⤢ Sessions ⌥⌘F": the Focus ladder button. Click steps on; press and hold lists the four steps. The shortcut label
/// goes when the toolbar is narrow (LAB-1237); the tooltip keeps it.
struct V2StepButton: View {
    @Environment(\.theme) private var t
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController

    var body: some View {
        let focus = win.focusStep == .focus
        let label = win.place == .sessions ? win.focusStep.title : "Focus"
        Menu {
            ForEach(FocusStep.allCases, id: \.self) { s in
                Button("\(s.rawValue) · \(s.title)") { controller.v2SetStep(s) }
            }
        } label: {
            Text((focus ? "" : "⤢ ") + label + (controller.v2Bar.shortcuts ? " ⌥⌘F" : "")).ui(11, focus ? .semibold : .regular).lineLimit(1)
        } primaryAction: {
            controller.v2StepOn()
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(focus ? t.onAccent.color : t.text.color)
        .padding(.horizontal, 9).frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(focus ? t.accent.color : t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(focus ? .clear : t.separator.color, lineWidth: 1))
        .barHelp(focus ? "Leave Focus (⌥⌘F). Press and hold for the four steps." : "Focus ladder: step on ⌥⌘F, step back ⇧⌥⌘F. Press and hold for the four steps.")
        .accessibilityLabel("Focus step: \(win.focusStep.title)")
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
