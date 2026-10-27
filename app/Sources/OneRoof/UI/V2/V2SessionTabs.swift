import AppKit
import SwiftUI
import OneRoofCore

/// The session tabs above the centre (handover A2.0): Terminal · Files · Changes n · Subagents n · + Terminal, and on
/// the right Split · Raw · Table (buttons; their keys are in the tooltips and the menus, LAB-1271). Each tab is a view of the selected session: the terminal area, today's file tree
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
    /// Whether the focused pane of this window shows its Table view (LAB-1286; the terminal area says when it changes).
    @State private var tableOn = false
    private var current: Tab {
        switch win.centre {
        case .editor: return .files
        case .review: return .changes
        case .subagents: return .subagents
        default: return .terminal
        }
    }

    /// Shown wherever the centre is one of the session's views (an Editor or Review reached from another place too);
    /// Find in Workspace is its own page. The centre sizes the strip from this (LAB-1317), so keep the two in step.
    static func shows(centre: CentreView, viewerPath: String?) -> Bool {
        [.workspace, .editor, .review, .subagents].contains(centre) && !(centre == .editor && viewerPath == FileKind.searchPath)
    }
    static let height: CGFloat = 34

    var body: some View {
        if Self.shows(centre: win.centre, viewerPath: win.viewerPath) {
            let item = win.selectedId.flatMap { model.item($0) }
            let changes = item.flatMap { model.repoStats[model.workRepo($0)]?.files } ?? 0
            let subs = item.map { model.subagentCount($0) } ?? 0
            // A narrow window (LAB-831) shortens + Terminal, then drops the Split · Raw · Table labels to icons, then
            // the buttons (the menus and ⌘D / ⌘R keep them), then tightens the tabs; nothing wraps or overlaps.
            ViewThatFits(in: .horizontal) {
                ForEach(0..<5) { level in strip(item: item, changes: changes, subs: subs, level: level) }
            }
            .padding(.horizontal, 10).frame(height: Self.height)
            .background(model.themes.centre.tokens.window.color)
            .onReceive(NotificationCenter.default.publisher(for: .tableViewChanged)) { n in
                if n.object as? String == win.id { tableOn = n.userInfo?["on"] as? Bool ?? false }
            }
        }
    }

    /// The tab row at a narrowness level: 0 everything, 1 "+" for + Terminal, 2 icon-only buttons, 3 no buttons,
    /// 4 tighter tabs.
    private func strip(item: BoardItem?, changes: Int, subs: Int, level: Int) -> some View {
        let pad: CGFloat = level >= 4 ? 6 : 10
        return HStack(spacing: 2) {
            tab("Terminal", .terminal, pad: pad) { model.show(.workspace, in: win) }
            tab("Files", .files, pad: pad) { openFiles(item) }
            tab(changes > 0 ? "Changes \(changes)" : "Changes", .changes, pad: pad) { openChanges(item) }
            tab(subs > 0 ? "Subagents \(subs)" : "Subagents", .subagents, pad: pad) { openSubagents(item) }
            Button { NSApp.sendAction(#selector(AppDelegate.newTerminal(_:)), to: nil, from: nil) } label: {
                Text(level >= 1 ? "+" : "+ Terminal").ui(11.5).foregroundStyle(t.text2.color).lineLimit(1).padding(.horizontal, 8).frame(height: 24)
            }
            .buttonStyle(.plain).help("New terminal (⌘T)").accessibilityLabel("New terminal")
            Spacer(minLength: level >= 3 ? 0 : 8)
            if level < 3 {
                HStack(spacing: 6) {
                    // LAB-1271: buttons, not loose shortcut text; the keys are in the tooltips and the View menu.
                    button("Split", "rectangle.split.2x1", icon: level >= 2, #selector(AppDelegate.splitRight(_:)),
                           "Split this pane: right ⌘D, down ⇧⌘D")
                    button("Raw", "text.alignleft", icon: level >= 2, #selector(AppDelegate.toggleRawStream(_:)),
                           "Raw stream: the session's plain output, steps folded open (⌘R)")
                    button(tableOn ? "Table ✓" : "Table", "tablecells", icon: level >= 2, #selector(AppDelegate.toggleTableView(_:)),
                           tableOn ? "Back to the live terminal (Esc while the formatted view has the keyboard)" : FormattedPaneView.tooltip,
                           on: tableOn)
                }
                .opacity(current == .terminal ? 1 : 0.4)
                .disabled(current != .terminal)
            }
        }
    }


    private func button(_ title: String, _ symbol: String, icon: Bool, _ sel: Selector, _ help: String, on: Bool = false) -> some View {
        Button { NSApp.sendAction(sel, to: nil, from: nil) } label: {
            Group {
                if icon { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                else { Text(title).ui(11, .medium) }
            }
            .foregroundStyle(on ? t.text.color : t.text2.color).lineLimit(1)
            .padding(.horizontal, 8).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(on ? t.surface.color : .clear))
            .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separator.color))
            .contentShape(Rectangle())
            .fixedSize()
        }
        .buttonStyle(.plain).help(help).accessibilityLabel(title.replacingOccurrences(of: " ✓", with: ", on"))
    }

    private func tab(_ title: String, _ k: Tab, pad: CGFloat = 10, action: @escaping () -> Void) -> some View {
        let on = current == k
        return Button(action: action) {
            Text(title).ui(11.5, on ? .semibold : .regular).foregroundStyle(on ? t.text.color : t.text2.color).lineLimit(1)
                .padding(.horizontal, pad).frame(height: 24)
                .background(Capsule().fill(on ? t.surface.color : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (on ? ", selected" : ""))
    }

    private func openFiles(_ item: BoardItem?) {
        // Back to the file you were on, else the last tab; with none open, the tree and "Pick a file".
        if let p = win.viewerPath, state.tabs.contains(p) { win.show(path: p) }
        else if let last = state.tabs.last { win.show(path: last) }
        else { win.viewerPath = nil; model.show(.editor, in: win) }
        _ = item
    }

    private func openChanges(_ item: BoardItem?) {
        if let item { win.reviewRepo = model.workRepo(item) }
        model.show(.review, in: win)
    }

    private func openSubagents(_ item: BoardItem?) {
        win.traceFocus = item?.id
        win.v2Trace = false   // the tab always opens on the cards
        model.show(.subagents, in: win)
    }
}
