import AppKit
import SwiftUI
import OneRoofCore

/// Files tab (handover A2.1, A2.4, C6.1): the session's repo as today's file tree (220 pt, git marks, Changes · Review
/// footer, its menus and drag-out) beside today's editor and viewer: file tabs, Split editor, claim banner + Take over,
/// Outline · Problems · Git with Quick fix and Ask agent ⌘I, breakpoints, the Run dock (⌃` hides), Markdown and HTML
/// preview with Preview / Source. Nothing of 0.5.2.9's editor is dropped; the file tabs from 0.5.2.6 live here now.
struct V2FilesTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState

    init(model: AppModel, win: WindowState) {
        self.model = model; self.win = win; self.state = EditorState.of(win.id)
    }

    /// Find in Workspace and a diff link fill the centre on their own (A10.6): no tree, no file tabs.
    private var standalone: Bool {
        guard let p = win.viewerPath else { return false }
        return p == FileKind.searchPath || p.hasPrefix(FileKind.diffPrefix)
    }

    var body: some View {
        if standalone { EditorView(model: model, win: win) } else { filesBody }
    }

    private var filesBody: some View {
        HStack(spacing: 0) {
            FileBrowserView(model: model, win: win).frame(width: 220)
            Rectangle().fill(model.themes.centre.tokens.separator.color).frame(width: 1)
            VStack(spacing: 0) {
                if !state.tabs.isEmpty || win.viewerPath != nil { V2FileTabs(model: model, win: win, state: state) }   // the 0.5.2.6 file tabs, now inside Files
                if win.viewerPath == nil {
                    V2FilesEmpty().themed(model.themes.centre, scale: win.textScale)
                } else {
                    EditorView(model: model, win: win)
                }
            }
        }
    }
}

private struct V2FilesEmpty: View {
    @Environment(\.theme) private var t
    var body: some View {
        VStack(spacing: 6) {
            Text("Pick a file").ui(15, .semibold).foregroundStyle(t.text.color)
            Text("Click a file in the tree to open it in a tab. ⌘O opens any file.").ui(12).foregroundStyle(t.text2.color)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.window.color)
    }
}

/// The open files as tabs (LAB-799's tabs, inside the Files tab since 1.2.0).
struct V2FileTabs: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState

    /// The open tabs, plus the file on screen if it came from a search hit or a link (those don't open a tab).
    private var shown: [String] {
        guard let p = win.viewerPath, !state.tabs.contains(p), p != FileKind.searchPath, !p.hasPrefix(FileKind.diffPrefix) else { return state.tabs }
        return state.tabs + [p]
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(shown, id: \.self) { p in
                    let on = win.viewerPath == p
                    HStack(spacing: 6) {
                        Image(systemName: FileKind.of(p).symbol).ui(11).foregroundStyle(on ? t.text.color : t.text3.color)
                        Text((p as NSString).lastPathComponent).ui(12, on ? .semibold : .regular).foregroundStyle(on ? t.text.color : t.text2.color).lineLimit(1)
                        if state.isDirty(p) { Circle().fill(t.text.color).frame(width: 6, height: 6).accessibilityLabel("unsaved") }
                        Button { close(p) } label: { Image(systemName: "xmark").ui(9).foregroundStyle(t.text3.color) }
                            .buttonStyle(.plain).help("Close this tab")
                    }
                    .padding(.horizontal, 12).frame(height: 30)
                    .background(on ? t.surface.color : .clear)
                    .overlay(alignment: .top) { if on { Rectangle().fill(t.accent.color).frame(height: 2) } }
                    .contentShape(Rectangle())
                    .onTapGesture { win.show(path: p) }
                    .help(p.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: 30)
        .background(t.toolbar.color)
        .overlay(alignment: .bottom) { Hairline() }
        .themed(model.themes.centre, scale: win.textScale)
    }

    /// Closing the last tab leaves the Files tab on its empty state (the 0.5 strip went back to the terminals).
    private func close(_ p: String) {
        win.closeTab(p)
        if state.tabs.isEmpty { win.viewerPath = nil; win.centre = .editor }
    }
}

/// Subagents tab (handover A2.3): one card per subagent of the selected session — status dot, name, model · tokens ·
/// age, Asked:, Done: / Doing: — and FILES TOUCHED beside them. Trace ▸ opens every call (C6.2, today's trace view).
struct V2SubagentsTab: View {
    /// LAB-1338: captions, feed, chapters and subagents redraw this view (they left AppModel).
    @ObservedObject var engineState = EngineState.shared
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    var body: some View {
        let item = win.selectedId.flatMap { model.item($0) }
        let subs = item.flatMap { model.subagents[$0.id] } ?? []
        HStack(alignment: .top, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if subs.isEmpty {
                        Text(item == nil ? "Select a session to see its subagents." : "No subagents in this session yet.")
                            .ui(12.5).foregroundStyle(t.text2.color).padding(14)
                    }
                    ForEach(subs.sorted { ($0.ended == nil ? 0 : 1, $0.started) < ($1.ended == nil ? 0 : 1, $1.started) }) { s in card(s) }
                }
                .padding(12)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("FILES TOUCHED").ui(10.5, .bold).tracking(0.4).foregroundStyle(t.text3.color)
                let touched = Self.touched(subs)
                if touched.isEmpty { Text("None yet").ui(12).foregroundStyle(t.text3.color) }
                ForEach(touched, id: \.path) { f in
                    HStack {
                        Button { win.show(path: f.path) } label: {
                            Text((f.path as NSString).lastPathComponent).ui(11.5, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                        }
                        .buttonStyle(.plain).help(f.path)
                        Spacer()
                        Text(f.read && f.added + f.removed == 0 ? "read" : "+\(f.added) −\(f.removed)").ui(11).foregroundStyle(t.text3.color)
                    }
                }
                Spacer().frame(height: 6)
                Text("Trace ▸ opens every call each subagent made.").ui(11.5).foregroundStyle(t.text2.color)
                if let item {
                    Button { win.traceFocus = item.id; win.v2Trace = true } label: {
                        Text("Whole trace ▸").ui(11.5, .semibold).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain).help("Every subagent of this session in one trace")
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 240)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
            .padding(.vertical, 12).padding(.trailing, 12)
        }
        .background(t.window.color)
        .themed(model.themes.centre, scale: win.textScale)
    }

    private func card(_ s: Subagent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle().fill(t.statusColor(s.isRunning ? .running : .done).color).frame(width: 8, height: 8)
                Text(s.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                if s.inferred { Text("inferred").ui(10.5).foregroundStyle(t.text3.color) }
                Spacer()
                Text([s.model, Self.tokens(s.tokens), Self.age(s)].filter { !$0.isEmpty }.joined(separator: " · ")).ui(11).foregroundStyle(t.text3.color)
                Button { win.traceFocus = s.sessionId + "/" + s.id; win.v2Trace = true; model.show(.subagents, in: win) } label: {
                    Text("Trace ▸").ui(11).foregroundStyle(t.accentText.color)
                }
                .buttonStyle(.plain).help("Every call this subagent made")
            }
            if !s.asked.isEmpty {
                (Text("Asked: ").bold() + Text(s.asked)).ui(12).foregroundStyle(t.text2.color).lineLimit(2)
            }
            let line = s.lastText ?? s.caption
            if !line.isEmpty {
                (Text(s.isRunning ? "Doing: " : "Done: ").bold() + Text(line)).ui(12).foregroundStyle(t.text2.color).lineLimit(2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
        .contextMenu { Button("Ask the parent to stop \(s.name)") { if let parent = model.item(s.sessionId) { model.askToStop(s, in: parent) } } }
    }

    static func touched(_ subs: [Subagent]) -> [FileTouch] {
        var seen: [String: FileTouch] = [:]
        for s in subs { for f in s.touched {
            var m = seen[f.path] ?? FileTouch(path: f.path)
            m.added += f.added; m.removed += f.removed; m.read = m.read || f.read
            seen[f.path] = m
        } }
        return seen.values.sorted { $0.path < $1.path }
    }

    static func tokens(_ n: Int) -> String { n <= 0 ? "" : (n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)") }
    static func age(_ s: Subagent) -> String {
        let secs = Int((s.ended ?? Date()).timeIntervalSince(s.started))
        return secs < 60 ? "\(secs)s" : (secs < 3600 ? "\(secs / 60)m" : "\(secs / 3600)h")
    }
}

/// The Subagents tab: the cards, or today's trace once Trace ▸ / Whole trace ▸ was clicked, with a way back. Outside
/// Sessions (Overview, the Window menu) it is today's trace view as before.
struct V2SubagentsHost: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var body: some View {
        Group {
            if win.place != .sessions { SubagentTraceView(model: model, win: win) }
            else if win.v2Trace {
                VStack(spacing: 0) {
                    HStack {
                        Button { win.v2Trace = false } label: { Text("‹ Subagents").ui(12, .semibold).foregroundStyle(t.accentText.color) }
                            .buttonStyle(.plain).help("Back to this session's subagent cards")
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 30)
                    Hairline()
                    SubagentTraceView(model: model, win: win)
                }
            } else { V2SubagentsTab(model: model, win: win) }
        }
        .onChange(of: win.selectedId) { _, _ in win.v2Trace = false }
    }
}
