import AppKit
import SwiftUI
import OneRoofCore

/// The session tabs above the centre (handover A2.0): Terminal · Files · Changes n · Subagents n · + Terminal, and on
/// the right Split ⌘D · Raw ⌘R · Wrap. Each tab is a view of the selected session: the terminal area, today's file tree
/// with the editor and its file tabs (LAB-799 tabs live inside Files now), Review changes for the session's repo, and the
/// subagent cards of the session. Shown whenever the centre is one of those views.
struct V2SessionTabs: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState

    init(model: AppModel, win: WindowState) {
        self.model = model; self.win = win; self.state = EditorState.of(win.id)
    }

    enum Tab { case terminal, files, changes, subagents }
    /// Wrap for reading on the focused pane (LAB-657), for this window (object = window id).
    static let wrap = Notification.Name("oneroof.v2.wrap")

    private var current: Tab {
        switch win.centre {
        case .editor: return .files
        case .review: return .changes
        case .subagents: return .subagents
        default: return .terminal
        }
    }

    var body: some View {
        // Shown wherever the centre is one of the session's views (an Editor or Review reached from another place too).
        if [.workspace, .editor, .review, .subagents].contains(win.centre) {
            let item = win.selectedId.flatMap { model.item($0) }
            let changes = item.flatMap { model.repoStats[$0.session.repoPath]?.files } ?? 0
            let subs = item.map { model.subagentCount($0) } ?? 0
            HStack(spacing: 2) {
                tab("Terminal", .terminal) { model.show(.workspace, in: win) }
                tab("Files", .files) { openFiles(item) }
                tab(changes > 0 ? "Changes \(changes)" : "Changes", .changes) { openChanges(item) }
                tab(subs > 0 ? "Subagents \(subs)" : "Subagents", .subagents) { openSubagents(item) }
                Button { NSApp.sendAction(#selector(AppDelegate.newTerminal(_:)), to: nil, from: nil) } label: {
                    Text("+ Terminal").ui(11.5).foregroundStyle(t.text2.color).padding(.horizontal, 8).frame(height: 24)
                }
                .buttonStyle(.plain).help("New terminal (⌘T)")
                Spacer(minLength: 8)
                HStack(spacing: 10) {
                    hint("Split ⌘D", #selector(AppDelegate.splitRight(_:)), "Split right (⌘D) · down ⇧⌘D")
                    hint("Raw ⌘R", #selector(AppDelegate.toggleRawStream(_:)), "Raw stream (⌘R)")
                    Button { NotificationCenter.default.post(name: V2SessionTabs.wrap, object: win.id) } label: {
                        Text("Wrap").ui(11).foregroundStyle(t.text2.color)
                    }
                    .buttonStyle(.plain).help("Read-only re-wrapped text of the terminal")
                }
                .opacity(current == .terminal ? 1 : 0.4)
                .disabled(current != .terminal)
            }
            .padding(.horizontal, 10).frame(height: 34)
            .background(model.themes.centre.tokens.window.color)
        }
    }

    private func tab(_ title: String, _ k: Tab, action: @escaping () -> Void) -> some View {
        let on = current == k
        return Button(action: action) {
            Text(title).ui(11.5, on ? .semibold : .regular).foregroundStyle(on ? t.text.color : t.text2.color)
                .padding(.horizontal, 10).frame(height: 24)
                .background(Capsule().fill(on ? t.surface.color : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (on ? ", selected" : ""))
    }

    private func hint(_ title: String, _ sel: Selector, _ help: String) -> some View {
        Button { NSApp.sendAction(sel, to: nil, from: nil) } label: { Text(title).ui(11).foregroundStyle(t.text2.color) }
            .buttonStyle(.plain).help(help)
    }

    private func openFiles(_ item: BoardItem?) {
        // Back to the file you were on, else the last tab; with none open, the tree and "Pick a file".
        if let p = win.viewerPath, state.tabs.contains(p) { win.show(path: p) }
        else if let last = state.tabs.last { win.show(path: last) }
        else { win.viewerPath = nil; model.show(.editor, in: win) }
        _ = item
    }

    private func openChanges(_ item: BoardItem?) {
        if let item { win.reviewRepo = item.session.repoPath }
        model.show(.review, in: win)
    }

    private func openSubagents(_ item: BoardItem?) {
        win.traceFocus = item?.id
        win.v2Trace = false   // the tab always opens on the cards
        model.show(.subagents, in: win)
    }
}
