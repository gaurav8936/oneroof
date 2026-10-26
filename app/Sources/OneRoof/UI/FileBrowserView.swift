import AppKit
import SwiftUI
import OneRoofCore

/// Files panel (S06 §1.3): the selected session's repo (or ~/Projects) as a lazy tree with git badges, a header with
/// the branch, and a Changes footer with Review changes ⌥⌘R. Files theme (default Daylight).
struct FileBrowserView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    var body: some View {
        Content(model: model, win: win).themed(model.themes.files, scale: win.textScale)
    }

    private struct Content: View {
        @Environment(\.theme) private var t
        @ObservedObject var model: AppModel
        @ObservedObject var win: WindowState
        @State private var showHidden = false
        @State private var badges: [String: GitBadge] = [:]
        @State private var gitRoot: String?

        var root: String {
            // In the Editor the tree follows the open file's repo; otherwise the selected session's.
            if win.centre == .editor, let p = win.viewerPath, let top = GitDiff.repoRoot(for: p) { return top }
            let r = model.item(win.selectedId ?? "").map { model.workRepo($0) } ?? Workspace.projectsRoot
            return Workspace.isInsideProjects(r) ? r : Workspace.projectsRoot
        }

        var body: some View {
            let stat = model.repoStats[root]
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(Workspace.repoLabel(for: root)).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Spacer()
                    if let b = stat?.branch { Text(b).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1) }
                    PanelCloseButton(title: "Files", action: #selector(AppDelegate.toggleFiles(_:)))
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
                .contextMenu {
                    Button(showHidden ? "Hide Hidden Files" : "Show Hidden Files") { showHidden.toggle() }
                    Button("Open in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: root)) }
                    Button("Refresh") { refresh() }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        FileNodeView(path: root, depth: 0, model: model, win: win, showHidden: showHidden, expandedByDefault: true,
                                     badges: badges, gitRoot: gitRoot)
                            .id(root + (showHidden ? "1" : "0"))
                    }
                    .padding(.vertical, 2)
                }
                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Changes \(stat?.files ?? badges.count)").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                        Spacer()
                        if let s = stat, s.added + s.removed > 0 {
                            Text("+\(s.added)").ui(12, .medium, mono: true).foregroundStyle(t.diffAddText.color)
                            Text("−\(s.removed)").ui(12, .medium, mono: true).foregroundStyle(t.diffDelText.color)
                        }
                    }
                    Button { model.openDiff(root) } label: {
                        Text("Review changes ⌥⌘R").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(t.surface2.color))
                            .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separator.color))
                    }
                    .buttonStyle(.plain)
                    .disabled(gitRoot == nil)
                }
                .padding(12)
            }
            .background(t.window.color)
            .onAppear(perform: refresh)
            .onChange(of: root) { _, _ in refresh() }
            .onReceive(model.$repoStats) { _ in refresh() }
        }

        private func refresh() {
            let r = root
            DispatchQueue.global(qos: .utility).async {
                let top = GitDiff.repoRoot(for: r)
                let b = top.flatMap { GitStatus.badges(repo: $0) } ?? [:]
                DispatchQueue.main.async { if gitRoot != top { gitRoot = top }; if badges != b { badges = b } }
            }
        }
    }
}

/// A file tree row (COMPONENTS FileTreeRow): 24 pt, indent 14 per level, caret, type glyph, name, git badge.
struct FileNodeView: View {
    @Environment(\.theme) private var t
    let path: String
    let depth: Int
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    let showHidden: Bool
    var expandedByDefault = false
    var badges: [String: GitBadge] = [:]
    var gitRoot: String?
    @State private var expanded = false
    @State private var children: [String]?

    static let skip: Set<String> = [".git", "node_modules", ".build", "build", "dist", ".svelte-kit", "__pycache__", ".venv", ".DS_Store", ".worktrees"]
    var name: String { (path as NSString).lastPathComponent }
    var isDir: Bool { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue }

    private var badge: GitBadge? {
        guard let gitRoot, path.hasPrefix(gitRoot) else { return nil }
        let rel = String(path.dropFirst(gitRoot.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return isDir ? GitStatus.folderBadge(rel, in: badges) : badges[rel]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if depth > 0 { row }
            if expanded || depth == 0, let children {
                ForEach(children, id: \.self) { c in
                    FileNodeView(path: c, depth: depth + 1, model: model, win: win, showHidden: showHidden, badges: badges, gitRoot: gitRoot)
                }
            }
        }
        .onAppear { if depth == 0 || expandedByDefault { load(); expanded = true } }
    }

    private var selected: Bool { win.centre == .editor && win.viewerPath == path }

    private var row: some View {
        HStack(spacing: 5) {
            Text(isDir ? (expanded ? "▾" : "▸") : " ").ui(10).foregroundStyle(t.text3.color).frame(width: 10)
            // LAB-478: Finder's icons (a Markdown file looks like one), not a coloured block that read as a folder.
            Image(nsImage: FileIcons.icon(for: path, isDirectory: isDir, size: 16)).resizable().interpolation(.high)
                .frame(width: 16, height: 16).accessibilityHidden(true)
            Text(name).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1)
            Spacer(minLength: 0)
            if let b = badge {
                Text(b.rawValue).ui(11, .semibold, mono: true).foregroundStyle(badgeColor(b).color)
                    .accessibilityLabel(b == .modified ? "modified" : b == .added ? "added" : b == .deleted ? "deleted" : "untracked")
            }
        }
        .padding(.leading, CGFloat(depth - 1) * 14 + 8).padding(.trailing, 8)
        .frame(height: 24)
        .contentShape(Rectangle())
        .hoverHighlight(radius: 6, selected: selected)
        .padding(.horizontal, 6)
        .onTapGesture(count: 2) { if !isDir { model.openInViewer(path) } }
        .onTapGesture { if isDir { if children == nil { load() }; expanded.toggle() } else { model.openInViewer(path) } }
        .contextMenu {
            if !isDir {
                Button("Open") { model.openInViewer(path) }
                Button("Open in Default App") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(path, forType: .string)
            }
            if let pane = model.item(win.selectedId ?? "")?.paneId {
                Button("Type Path into Terminal") { send(pane, path) }
                Button("Attach to Agent Message") { send(pane, "@" + path) }
            }
            if isDir { Button("New Terminal Here") { model.newTerminal(in: path) }.disabled(!Workspace.isInsideProjects(path)) }
        }
        .onDrag { NSItemProvider(object: URL(fileURLWithPath: path) as NSURL) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name + (isDir ? ", folder" : ""))
    }

    private func send(_ pane: String, _ text: String) {
        let r = model.runtime
        let quoted = text.contains(" ") ? "'\(text)'" : text
        DispatchQueue.global().async { try? r.type(pane: pane, text: quoted + " ") }
    }

    private func badgeColor(_ b: GitBadge) -> RGB {
        switch b {
        case .modified: return t.accentText
        case .added: return t.diffAddText
        case .deleted: return t.diffDelText
        case .untracked: return t.text3
        }
    }

    private func load() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: path)) ?? []
        let visible = names.filter { !Self.skip.contains($0) && (showHidden || !$0.hasPrefix(".")) }
        let full = visible.map { path + "/" + $0 }
        children = full.sorted { a, b in
            var da: ObjCBool = false, db: ObjCBool = false
            fm.fileExists(atPath: a, isDirectory: &da); fm.fileExists(atPath: b, isDirectory: &db)
            if da.boolValue != db.boolValue { return da.boolValue }
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}
