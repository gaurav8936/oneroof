import AppKit
import SwiftUI
import OneRoofCore

/// LAB-1286 (1.9.3): what one pane's Table view shows, kept up to date by the terminal area every 2 s.
final class FormattedFeed: ObservableObject {
    enum Source { case transcript, terminal }
    @Published private(set) var items: [FormattedItem] = []
    @Published private(set) var source: Source = .terminal
    /// Bumped on every change, so the view can follow the end.
    @Published private(set) var version = 0
    /// What the last read was made from (file size + date, or the terminal text), to skip work when nothing changed.
    var lastKey = ""
    /// A read is under way (one at a time per pane).
    var busy = false

    func set(_ items: [FormattedItem], source: Source) {
        guard items != self.items || source != self.source else { return }
        self.items = items
        self.source = source
        version += 1
    }
}

/// The pane's Table view (replaces Wrap, LAB-657): the session's output formatted. Prose wraps to the pane, every table
/// is a real table (columns line up at any width, it scrolls sideways when wider than the pane), code keeps its
/// monospace and scrolls sideways too. A Claude session shows its transcript (prompts, replies as Markdown, one line per
/// tool call); any other terminal shows its text with the tables it prints found and drawn. Newest at the bottom.
struct FormattedPaneView: View {
    /// The Table toggle's tooltip (pane header and session tabs).
    static let tooltip = "Show this session formatted: text wraps, tables are real tables you can scroll"
    @ObservedObject var feed: FormattedFeed
    let t: ThemeTokens
    let scale: CGFloat
    let onBack: () -> Void
    @State private var atBottom = true

    var body: some View {
        VStack(spacing: 0) {
            bar
            Rectangle().fill(t.separator.color).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if feed.items.isEmpty {
                            Text("Nothing to show yet.").ui(12.5).foregroundStyle(t.text2.color)
                        }
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, item in row(item) }
                        Color.clear.frame(height: 1).id("end")
                            .onAppear { atBottom = true }
                            .onDisappear { atBottom = false }
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { DispatchQueue.main.async { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: feed.version) { _, _ in
                    if atBottom { DispatchQueue.main.async { proxy.scrollTo("end", anchor: .bottom) } }
                }
            }
        }
        .foregroundStyle(t.text.color)
        .background(t.terminal.background.color)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Formatted view of the session")
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells").font(.system(size: 11, weight: .semibold)).foregroundStyle(t.accentText.color)
            Text("Formatted view").ui(12, .semibold).foregroundStyle(t.text.color)
            Text(feed.source == .transcript ? "from the Claude transcript, read-only" : "from the terminal text, read-only")
                .ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "terminal").font(.system(size: 10, weight: .semibold))
                    Text("Back to live").ui(11.5, .semibold)
                }
                .foregroundStyle(t.text.color)
                .padding(.vertical, 3).padding(.horizontal, 9)
                .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separatorStrong.color))
                .contentShape(Rectangle())
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Back to the live terminal (Esc while this view has the keyboard)")
            .accessibilityLabel("Back to the live terminal")
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(t.surface2.color)
    }

    /// Long terminal text in pieces of 80 lines, so the lazy stack only lays out what is on screen.
    private var rows: [FormattedItem] {
        feed.items.flatMap { item -> [FormattedItem] in
            guard case .text(let s) = item else { return [item] }
            let lines = s.components(separatedBy: "\n")
            guard lines.count > 80 else { return [item] }
            return stride(from: 0, to: lines.count, by: 80).map { .text(lines[$0..<min($0 + 80, lines.count)].joined(separator: "\n")) }
        }
    }

    @ViewBuilder private func row(_ item: FormattedItem) -> some View {
        switch item {
        case .prompt(let s):
            VStack(alignment: .leading, spacing: 6) {
                Text("You").ui(10.5, .semibold, mono: true).foregroundStyle(t.text2.color)
                blocks(MarkdownDoc.parse(s))
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.separator.color))
        case .reply(let b):
            blocks(b)
        case .tool(let s):
            HStack(spacing: 6) {
                Text("▸").ui(11, mono: true).foregroundStyle(t.text3.color)
                Text(s).ui(11.5, mono: true).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.middle)
            }
        case .text(let s):
            Text(s).font(.system(size: 12.5 * scale, design: .monospaced)).lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .table(let header, let aligns, let rows):
            MarkdownBlockView(block: .table(header: header, alignments: aligns, rows: rows), path: "", t: t, scale: scale, depth: 0)
        }
    }

    private func blocks(_ b: [MarkdownBlock]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(b.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, path: "", t: t, scale: scale, depth: 0)
            }
        }
    }
}

/// Holds the Table view in a pane. Taking the keyboard lets Esc go back to the live terminal (the terminal itself
/// keeps Esc whenever it has the keyboard: it belongs to the agent).
final class FormattedHostView: NSHostingView<AnyView> {
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}
