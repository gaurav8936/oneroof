import AppKit
import SwiftUI
import OneRoofCore

/// Command palette (⌘P): one search over views, actions, sessions, objectives, files in the
/// selected session's repo and skills. ↑/↓ to move, Return to run, Esc to close.
struct PaletteItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let kind: String
    let run: () -> Void
}

enum Fuzzy {
    /// Subsequence match score (higher is better); nil when the query's letters don't all appear in order.
    static func score(_ query: String, _ text: String) -> Int? {
        let q = Array(query.lowercased()), t = Array(text.lowercased())
        guard !q.isEmpty else { return 0 }
        var qi = 0, score = 0, last = -2
        for (i, c) in t.enumerated() where qi < q.count && c == q[qi] {
            score += (i == last + 1 ? 6 : 1) + (i == 0 || t[i - 1] == " " || t[i - 1] == "/" || t[i - 1] == "-" ? 8 : 0)
            last = i; qi += 1
        }
        return qi == q.count ? score - t.count / 12 : nil
    }
}

struct CommandPalette: View {
    let items: [PaletteItem]
    let close: () -> Void
    @State private var query: String

    /// `query`: text to start with (the v2 session column's search box passes what was typed).
    init(items: [PaletteItem], query: String = "", close: @escaping () -> Void) {
        self.items = items; self.close = close; _query = State(initialValue: query)
    }
    @State private var index = 0
    @FocusState private var focused: Bool

    var results: [PaletteItem] {
        guard !query.isEmpty else { return Array(items.prefix(60)) }
        return items.compactMap { i in Fuzzy.score(query, i.title + " " + i.subtitle).map { (i, $0 + (Fuzzy.score(query, i.title) ?? 0)) } }
            .sorted { $0.1 > $1.1 }.prefix(60).map(\.0)
    }

    var body: some View {
        let r = results
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("Search actions, sessions, objectives, files, skills…", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                    .onChange(of: query) { _, _ in index = 0 }
                    .onSubmit { run(r) }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(r.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onExitCommand(perform: close)
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(r.enumerated()), id: \.element.id) { i, item in
                            HStack(spacing: 10) {
                                Image(systemName: item.symbol).frame(width: 18).foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                Spacer()
                                Text(item.kind).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(i == index ? Color.accentColor.opacity(0.2) : .clear)
                            .contentShape(Rectangle())
                            .onTapGesture { index = i; run(r) }
                            .id(i)
                        }
                    }
                }
                .onChange(of: index) { _, i in proxy.scrollTo(i) }
            }
            .frame(height: 380)
        }
        .frame(width: 640)
        .background(.regularMaterial)
        .onAppear { focused = true }
    }

    private func run(_ r: [PaletteItem]) {
        guard r.indices.contains(index) else { return }
        let item = r[index]
        close()
        DispatchQueue.main.async { item.run() }
    }
}

/// The floating panel that hosts the palette over the main window.
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    static var current: PalettePanel?

    static func show(over window: NSWindow?, items: [PaletteItem], query: String = "") {
        current?.close()
        let p = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        let host = NSHostingView(rootView: CommandPalette(items: items, query: query, close: { PalettePanel.current?.close(); PalettePanel.current = nil })
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
        p.contentView = host
        if let w = window {
            let f = w.frame
            p.setFrameOrigin(NSPoint(x: f.midX - 320, y: f.maxY - 140 - 440))
        } else { p.center() }
        p.makeKeyAndOrderFront(nil)
        current = p
    }

    override func resignKey() {
        super.resignKey()
        guard !SelfTest.isActive else { return }   // a test copy is never the active app
        close()
        if PalettePanel.current === self { PalettePanel.current = nil }
    }
}
