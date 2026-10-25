import AppKit
import SwiftUI
import OneRoofCore

/// The centre file viewer (owner, 2026-10-17: a file clicked in the navigator, a plan or a doc shows in the middle,
/// never an external window). Markdown renders formatted and HTML renders like a browser page (LAB-479, LAB-480), each
/// with a Preview | Source switch to edit it; code and text show with line numbers, images as images, folders list
/// their files. Anything else offers to open in its default app.
struct FileViewer: View {
    @ObservedObject var model: AppModel
    /// The file to show; nil = the front window's viewer path. The editor passes it so a new file always redraws.
    var path: String? = nil
    /// Markdown and HTML: switch to Source (the editor). nil = no switch.
    var onSource: (() -> Void)? = nil
    /// The editor's unsaved text for this file: Markdown previews it; HTML says the page shows the saved file.
    var unsaved: String? = nil
    @State private var reload = 0
    var t: ThemeTokens { model.themes.terminal.tokens }

    var body: some View {
        let path = self.path ?? model.viewerPath ?? ""
        VStack(spacing: 0) {
            header(path)
            Divider().overlay(t.border.color)
            if unsaved != nil, FileKind.of(path) == .html {
                Text("Unsaved edits: the page shows the saved file. Save (⌘S) in Source to see them here.")
                    .font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 5)
                    .background(t.surface.color)
            }
            content(path).id(path + "#\(model.viewerLine ?? 0)")
        }
        .background(t.background.color)
        .environment(\.colorScheme, model.themes.terminal.colorScheme)
    }

    private func header(_ rawPath: String) -> some View {
        let isDiff = rawPath.hasPrefix(FileKind.diffPrefix)
        let path = isDiff ? String(rawPath.dropFirst(FileKind.diffPrefix.count)) : rawPath
        return HStack(spacing: 8) {
            Button { model.viewerBack() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless).disabled(model.viewerHistory.count < 2).help("Back")
            Image(systemName: FileKind.of(rawPath).symbol).foregroundStyle(t.secondaryText.color)
            Text(isDiff ? "Review changes · " + (path as NSString).lastPathComponent
                 : rawPath == FileKind.searchPath ? "Search in Workspace" : (path as NSString).lastPathComponent).font(.system(size: 13, weight: .bold)).foregroundStyle(t.text.color)
            Text(rawPath == FileKind.searchPath ? "" : path.replacingOccurrences(of: NSHomeDirectory(), with: "~")).font(.system(size: 11))
                .foregroundStyle(t.secondaryText.color).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let onSource, DocumentRoute.hasPreview(FileKind.of(rawPath).core) {
                Segmented(options: [(ViewerMode.preview, "Preview"), (.source, "Source")],
                          selection: Binding(get: { .preview }, set: { if $0 == .source { onSource() } }))
                    .environment(\.theme, t)
                    .help("Preview shows the page formatted; Source edits it")
                Button { reload += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help("Reload from disk")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless).help("Reveal in Finder")
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.borderless).help("Open in its default app")
            Button { model.active.closeTab(rawPath) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless).help("Close this file's tab (the terminals stay as they were)")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(t.surface.color)
    }

    @ViewBuilder private func content(_ path: String) -> some View {
        switch FileKind.of(path) {
        case .search: SearchView(model: model, t: t)
        case .diff: DiffView(model: model, repo: String(path.dropFirst(FileKind.diffPrefix.count)), t: t)
        case .folder: FolderListing(path: path, model: model, t: t)
        case .markdown: MarkdownPage(path: path, text: unsaved, tokens: t) { model.openInViewer($0) }.id(reload)
        case .html: WebPage(path: path, root: DocumentRoute.webReadRoot(page: path, repoRoot: DocumentRoute.enclosingRepo(of: path)), reload: reload)
        case .image:
            ScrollView([.horizontal, .vertical]) {
                if let img = NSImage(contentsOfFile: path) { Image(nsImage: img).resizable().scaledToFit().padding(20) }
            }
        case .text: CodeView(path: path, t: t, line: model.viewerLine)
        case .other:
            VStack(spacing: 10) {
                Image(systemName: "doc").font(.system(size: 30)).foregroundStyle(t.secondaryText.color)
                Text("One Roof can't show this kind of file.").foregroundStyle(t.secondaryText.color)
                Button("Open in its default app") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

enum FileKind {
    case folder, markdown, html, image, text, other, diff, search

    /// The viewer shows Search in Workspace for this path.
    static let searchPath = "search:"

    /// The viewer shows a repo's code review panel for "diff:<repo path>".
    static let diffPrefix = "diff:"

    static func of(_ path: String) -> FileKind {
        if path.hasPrefix(diffPrefix) { return .diff }
        if path == searchPath { return .search }
        var dir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &dir), dir.boolValue { return .folder }
        switch DocumentRoute.kind(path: path) {
        case .markdown: return .markdown
        case .html: return .html
        case .image: return .image
        case .text: return .text
        case .other: return .other
        }
    }

    /// The kind as OneRoofCore routes it (folders, diffs and search are not files: .other).
    var core: ViewerFileKind {
        switch self {
        case .markdown: return .markdown
        case .html: return .html
        case .image: return .image
        case .text: return .text
        default: return .other
        }
    }

    var symbol: String {
        switch self {
        case .folder: return "folder"
        case .markdown: return "doc.richtext"
        case .html: return "globe"
        case .image: return "photo"
        case .text: return "chevron.left.forwardslash.chevron.right"
        case .other: return "doc"
        case .diff: return "plusminus"
        case .search: return "magnifyingglass"
        }
    }
}

/// Text or code with line numbers (first 2 MB).
struct CodeView: View {
    let path: String
    let t: ThemeTokens
    /// 1-based line to scroll to and mark (from search results).
    var line: Int? = nil

    var body: some View {
        let lines = Self.read(path)
        ScrollViewReader { proxy in
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(.system(size: 11.5, design: .monospaced)).foregroundStyle(t.secondaryText.color.opacity(0.6))
                            .frame(width: 44, alignment: .trailing)
                        Text(line.isEmpty ? " " : line).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text.color)
                            .textSelection(.enabled).fixedSize(horizontal: true, vertical: false)
                    }
                    .id(i)
                    .background(self.line == i + 1 ? t.accent.color.opacity(0.18) : .clear)
                }
            }
            .padding(12)
            .frame(minWidth: 600, alignment: .topLeading)
        }
        .onAppear { if let l = line { DispatchQueue.main.async { proxy.scrollTo(max(l - 1, 0), anchor: .center) } } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static func read(_ path: String) -> [String] {
        guard let h = FileHandle(forReadingAtPath: path) else { return ["(cannot read \(path))"] }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: 2_000_000)) ?? Data()
        guard let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return ["(binary file)"] }
        return s.components(separatedBy: "\n")
    }
}

/// A folder's files; a README opens first if there is one.
struct FolderListing: View {
    let path: String
    @ObservedObject var model: AppModel
    let t: ThemeTokens

    var body: some View {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        List(names, id: \.self) { n in
            Button { model.openInViewer(path + "/" + n) } label: {
                Label(n, systemImage: FileKind.of(path + "/" + n).symbol).font(.system(size: 12.5))
            }.buttonStyle(.plain)
        }
        .overlay { if names.isEmpty { Text("This folder is empty.").foregroundStyle(t.secondaryText.color) } }
    }
}
