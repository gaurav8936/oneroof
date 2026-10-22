import AppKit
import SwiftUI
import OneRoofCore

/// Toolbar items (S00 §1.2): view switcher · workspace menu · flexible space · search · panel toggles · + New session.
/// Each item is a SwiftUI view in the Sessions panel theme; the unified NSToolbar keeps the traffic lights centred.
final class ToolbarDelegate: NSObject, NSToolbarDelegate {
    private let model: AppModel
    private let win: WindowState
    private weak var controller: MainWindowController?

    static let switcher = NSToolbarItem.Identifier("oneroof.switcher")
    static let workspace = NSToolbarItem.Identifier("oneroof.workspace")
    static let search = NSToolbarItem.Identifier("oneroof.search")
    static let panels = NSToolbarItem.Identifier("oneroof.panels")
    static let new = NSToolbarItem.Identifier("oneroof.new")

    init(model: AppModel, win: WindowState, controller: MainWindowController) {
        self.model = model; self.win = win; self.controller = controller
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.switcher, Self.workspace, .flexibleSpace, Self.search, Self.panels, Self.new]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let controller else { return nil }
        let m = model, w = win
        let view: AnyView
        switch id {
        case Self.switcher: view = AnyView(ToolbarThemed(model: m, win: w) { ViewSwitcher(model: m, win: w) })
        case Self.workspace: view = AnyView(ToolbarThemed(model: m, win: w) { WorkspaceMenu(model: m, win: w, controller: controller) })
        case Self.search: view = AnyView(ToolbarThemed(model: m, win: w) { SearchField() })
        case Self.panels: view = AnyView(ToolbarThemed(model: m, win: w) { PanelToggles(controller: controller) })
        case Self.new: view = AnyView(ToolbarThemed(model: m, win: w) { NewSessionButton(model: m, win: w, controller: controller) })
        default: return nil
        }
        let item = NSToolbarItem(itemIdentifier: id)
        let host = NSHostingView(rootView: view)
        host.frame.size = host.fittingSize
        item.view = host
        item.isBordered = false
        item.visibilityPriority = id == Self.switcher || id == Self.new ? .high : .standard
        return item
    }
}

/// Toolbar content in the Sessions panel theme.
private struct ToolbarThemed<Content: View>: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ViewBuilder var content: () -> Content
    var body: some View { content().themed(model.themes.sidebar, scale: 1).fixedSize() }
}

/// Segmented view switcher (control fill, 3 pt inset, 12.5/500; selected = surface + 1 pt shadow; Decisions shows
/// the open-decisions count in needs text).
struct ViewSwitcher: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CentreView.switcher, id: \.self) { v in
                let on = selected(v)
                Button { model.show(v, in: win) } label: {
                    HStack(spacing: 4) {
                        Text(v.title).ui(TypeScale.small, .medium).foregroundStyle(on ? t.text.color : t.text2.color)
                        if v == .decisions, model.openDecisionCount > 0 {
                            Text("\(model.openDecisionCount)").ui(TypeScale.small, .semibold).foregroundStyle(t.needsText.color)
                        }
                    }
                    .padding(.vertical, 5).padding(.horizontal, 11)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? t.surface.color : .clear)
                        .shadow(color: on ? .black.opacity(0.12) : .clear, radius: 1, y: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(v.title + (v == .decisions && model.openDecisionCount > 0 ? ", \(model.openDecisionCount) open" : ""))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.control.color))
    }

    /// Editor, Review, Objective and Subagents belong to Workspace / Overview in the switcher.
    private func selected(_ v: CentreView) -> Bool {
        switch win.centre {
        case .editor, .review, .objective: return v == .workspace
        case .subagents: return v == .overview
        default: return v == win.centre
        }
    }
}

/// "One Roof ▾" + "window 2 of 6": rename, colour, new workspace, the other workspaces.
struct WorkspaceMenu: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController

    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Button("Rename Workspace…") { renameWorkspace() }
                Menu("Colour") {
                    Button("None") { setColour(nil) }
                    ForEach(Sticker.rowColors, id: \.name) { p in Button(p.name.capitalized) { setColour(p.name) } }
                }
                Divider()
                Button("New Workspace Window…") { controller.newWorkspace() }
                if MainWindowController.all.count > 1 {
                    Divider()
                    ForEach(MainWindowController.all.filter { $0 !== controller }, id: \.win.id) { c in
                        Button(c.win.name) { c.window?.makeKeyAndOrderFront(nil) }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    if let c = Pastel.named(win.colour) { Circle().fill(c.lightInk.color).frame(width: 8, height: 8) }
                    Text(win.name).ui(13, .semibold).foregroundStyle(t.text.color)
                    Text("▾").ui(10).foregroundStyle(t.text2.color)
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Workspace \(win.name)")
            let (n, all) = controller.position
            Text("window \(n) of \(all)").ui(12).foregroundStyle(t.text3.color)
        }
        .padding(.leading, 8)
    }

    private func renameWorkspace() {
        let a = NSAlert()
        a.messageText = "Rename workspace"
        let f = NSTextField(string: win.name)
        f.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        a.accessoryView = f
        a.addButton(withTitle: "Rename"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let n = f.stringValue.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        win.name = n
        if var r = WorkspaceStore.shared.workspaces.first(where: { $0.id == win.id }) { r.name = n; WorkspaceStore.shared.update(r) }
    }

    private func setColour(_ c: String?) {
        win.colour = c
        if var r = WorkspaceStore.shared.workspaces.first(where: { $0.id == win.id }) { r.colour = c; WorkspaceStore.shared.update(r) }
    }
}

/// Search field (240×28, control fill): opens the command palette anchored under it (S00.T.3).
struct SearchField: View {
    @Environment(\.theme) private var t
    var body: some View {
        Button { NSApp.sendAction(#selector(AppDelegate.showPalette(_:)), to: nil, from: nil) } label: {
            HStack {
                Text("Search sessions, files, docs").ui(12.5).foregroundStyle(t.text3.color)
                Spacer()
                Text("⌘K").ui(11, mono: true).foregroundStyle(t.text3.color)
            }
            .padding(.horizontal, 10)
            .frame(width: 240, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.control.color))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search sessions, files, docs")
    }
}

/// Panel toggles, labelled (owner 10-18: four bare icons were unclear), in the order the panels sit, left to right:
/// Sessions · Files · Terminal · Plan (LAB-522: the centre had no toggle, so the row skipped the middle panel). The
/// last open panel cannot be hidden (the row shakes).
struct PanelToggles: View {
    @Environment(\.theme) private var t
    @ObservedObject var controller: MainWindowController
    @State private var offset: CGFloat = 0

    var body: some View {
        HStack(spacing: 2) {
            toggle("Sessions", "sidebar.left", controller.panels.sidebar, "Show or hide the Sessions panel ⌥⌘S") { controller.toggleSidebar() }
            toggle("Files", "folder", controller.panels.files, "Show or hide the Files panel ⌥⌘B") { controller.toggleFiles() }
            toggle("Terminal", "terminal", controller.panels.centre, "Show or hide the terminal (the middle panel: terminals and views) ⌥⌘C") { controller.toggleCentre() }
            toggle("Plan", "sidebar.right", controller.panels.plan, "Show or hide the Plan panel ⌥⌘P") { controller.togglePlanPanel() }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.control.color))
        .offset(x: offset)
        .onChange(of: controller.shakeToggle) { _, _ in
            guard !Motion.reduce else { return }
            withAnimation(.easeInOut(duration: 0.05).repeatCount(5, autoreverses: true)) { offset = 4 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { offset = 0 }
        }
        .padding(.horizontal, 6)
    }

    private func toggle(_ label: String, _ symbol: String, _ on: Bool, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: on ? "checkmark" : symbol).font(.system(size: 9.5, weight: .bold))
                Text(label).ui(TypeScale.small, .medium)
            }
            .foregroundStyle(on ? t.text.color : t.text3.color)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? t.surface.color : .clear)
                .shadow(color: on ? .black.opacity(0.12) : .clear, radius: 1, y: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(label + " panel").accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// "+ New session" (accent, ⌘N); in the Editor the right side becomes Run / Debug.
struct NewSessionButton: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let controller: MainWindowController

    var body: some View {
        HStack(spacing: 8) {
            MiniPlayer(player: model.player) {
                model.learnTarget = nil
                model.learnTarget = model.player.pageId
                model.show(.learn, in: win)
            }
            if win.centre == .editor {
                RunControls(model: model, win: win)
            }
            Button { controller.newSession() } label: {
                Text("+ New session").ui(TypeScale.small, .semibold).foregroundStyle(t.onAccent.color)
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.accent.color))
            }
            .buttonStyle(.plain).help("New session ⌘N").accessibilityLabel("New session")
        }
        .padding(.trailing, 4)
    }
}
