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
        case Self.title: view = AnyView(V2Band(model: m, win: w, centre: true) { V2TitleView(model: m, win: w, controller: controller) }); label = "Title"
        case Self.extras: view = AnyView(V2Band(model: m, win: w, centre: true) { V2ToolbarExtras(model: m, win: w) }); label = "Player"
        case Self.layout: view = AnyView(V2Band(model: m, win: w, centre: true) { V2LayoutControl(win: w) }); label = "Layout"
        case Self.step: view = AnyView(V2Band(model: m, win: w, centre: true) { V2StepButton(win: w, controller: controller) }); label = "Focus"
        case Self.new: view = AnyView(V2Band(model: m, win: w, centre: true) { V2NewButton(controller: controller) }); label = "New"
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: id)
        let host = NSHostingView(rootView: view)
        // The extras (Learn player, Run · Debug) appear and disappear: min/max constraints track the content so the
        // toolbar re-lays the item out instead of drawing it over Single · Grid · Wall.
        host.sizingOptions = id == Self.extras ? [.intrinsicContentSize, .minSize, .maxSize] : [.intrinsicContentSize]
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
    @ViewBuilder var content: () -> Content
    var body: some View { content().themed(centre ? model.themes.centre : model.themes.sidebar, scale: 1).fixedSize() }
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
    let controller: MainWindowController

    var body: some View {
        let (title, sub) = Self.text(model: model, win: win, page: controller.v2Page)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).ui(14, .bold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail).frame(maxWidth: 360, alignment: .leading)
            if let sub { Text(sub).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1).frame(maxWidth: 260, alignment: .leading) }
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .combine)
    }

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
                .help(l == .single ? "Single (⌃⌥⌘1)" : (l == .grid ? "Grid: up to four live sessions side by side (⌃⌥⌘2)" : "Wall: every window's live sessions (⌃⌥⌘3)"))
                .accessibilityLabel(l.title + (ready ? "" : ", not available yet"))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.control.color))
    }
}

/// "⤢ Sessions ⌥⌘F": the Focus ladder button. Click steps on; press and hold lists the four steps.
struct V2StepButton: View {
    @Environment(\.theme) private var t
    @ObservedObject var win: WindowState
    let controller: MainWindowController

    var body: some View {
        let focus = win.focusStep == .focus
        let label = win.place == .sessions ? win.focusStep.title : "Focus"
        Menu {
            ForEach(FocusStep.allCases, id: \.self) { s in
                Button("\(s.rawValue) · \(s.title)") { controller.v2SetStep(s) }
            }
        } label: {
            Text((focus ? "" : "⤢ ") + label + " ⌥⌘F").ui(11, focus ? .semibold : .regular)
        } primaryAction: {
            controller.v2StepOn()
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(focus ? t.onAccent.color : t.text.color)
        .padding(.horizontal, 9).frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(focus ? t.accent.color : t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(focus ? .clear : t.separator.color, lineWidth: 1))
        .help("Focus ladder: step on ⌥⌘F, step back ⇧⌥⌘F, Esc leaves Focus. Press and hold for the four steps.")
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
        .help("New session (⌘N); hold for terminal, window, objective, work item")
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
