import AppKit
import SwiftUI
import OneRoofCore

/// The terminal text Wall tiles show: the last lines of each live session, read from roofd every 3 s while the Wall
/// is on screen (thumbnails, not live terminals: roofd lets one terminal show a session, and a window has it).
@MainActor final class V2WallFeed: ObservableObject {
    @Published var lines: [String: [String]] = [:]
    private var timer: Timer?
    private var busy = false
    /// The sessions on the wall (only those are read).
    var ids: [String] = []

    deinit { timer?.invalidate() }

    func start(_ model: AppModel) {
        refresh(model)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh(model) } }
        timer?.tolerance = 3 * 0.1   // LAB-1323: let the system batch wake-ups
    }
    func stop() { timer?.invalidate(); timer = nil }

    private func refresh(_ model: AppModel) {
        guard !busy else { return }   // the last read is still out (roofd slow): skip this tick
        let wanted = Set(ids)
        let panes = model.sessionItems.compactMap { i -> (String, String)? in
            guard wanted.contains(i.id), i.liveAgent != nil, let p = i.paneId ?? i.liveAgent else { return nil }
            return (i.id, p)
        }
        let r = model.runtime
        busy = true
        DispatchQueue.global(qos: .utility).async {
            var out: [String: [String]] = [:]
            for (id, pane) in panes {
                let text = (try? r.read(pane: pane, lines: 40)) ?? ""
                out[id] = Array(text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.suffix(8))
            }
            DispatchQueue.main.async { [weak self] in self?.lines = out; self?.busy = false }
        }
    }
}

/// Wall (handover A4.2, NEW-3): every window's live sessions on one page, grouped by window — 10 tiles from 1440 pt,
/// 15 from 2400 pt. A tile shows the session, its window, its state, the Right now line and its last terminal lines;
/// clicking it opens that window at Single on that session. Rail and dock stay; no composer on tiles.
struct V2WallPage: View {
    /// LAB-1338: captions, feed, chapters and subagents redraw this view (they left AppModel).
    @ObservedObject var engineState = EngineState.shared
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var controller: MainWindowController
    @StateObject private var feed = V2WallFeed()

    private var tiles: [(WindowState, BoardItem)] {
        model.windows.flatMap { w in model.items(in: w).filter { $0.liveAgent != nil }.map { (w, $0) } }
    }

    var body: some View {
        GeometryReader { g in
            let cap = g.size.width >= 2400 ? 15 : 10
            let all = tiles
            let shown = Array(all.prefix(cap))
            let _ = { feed.ids = shown.map(\.1.id) }()
            let cols = max(1, min(5, Int(g.size.width / 280)))
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("All windows").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                    Text("\(model.windows.count) window\(model.windows.count == 1 ? "" : "s") · \(model.sessionItems.count) sessions · \(shown.count) on the wall"
                         + (all.count > shown.count ? " · \(all.count - shown.count) more (open their window)" : ""))
                        .ui(12.5).foregroundStyle(t.text2.color)
                    Spacer()
                    Button { win.layout = .single; controller.v2Page = nil } label: { Text("‹ Single").ui(12, .semibold).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain).help("Back to this window (⌃⌥⌘1, Esc)")
                }
                if shown.isEmpty {
                    Text("No live sessions in any window. Sessions show here as soon as they run.").ui(13).foregroundStyle(t.text2.color)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    let rows = max(1, Int(ceil(Double(shown.count) / Double(cols))))
                    let h = max(150, (g.size.height - 60 - CGFloat(rows - 1) * 10) / CGFloat(rows))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: cols), spacing: 10) {
                        ForEach(shown, id: \.1.id) { w, item in tile(w, item).frame(height: h) }
                    }
                }
            }
            .padding(14)
        }
        .background(t.window.color)
        .onAppear { feed.start(model) }
        .onDisappear { feed.stop() }
    }

    private func tile(_ w: WindowState, _ item: BoardItem) -> some View {
        let term = model.themes.terminal.tokens
        let cap = model.caption(for: item)
        let selected = w.id == win.id && win.selectedId == item.id
        return Button { open(w, item) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle().fill(t.statusColor(item.status).color).frame(width: 7, height: 7)
                    Text(item.session.name).ui(12, .semibold).foregroundStyle(term.text.color).lineLimit(1)
                    Text(w.name).ui(11).foregroundStyle(term.text3.color).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(item.status.label).ui(11, .semibold).foregroundStyle(t.statusColor(item.status).color).lineLimit(1)
                }
                if !cap.text.isEmpty { Text(cap.text).ui(11.5).foregroundStyle(term.accent.color).lineLimit(1) }
                ForEach(Array((feed.lines[item.id] ?? []).enumerated()), id: \.offset) { _, l in
                    Text(l).ui(11, mono: true).foregroundStyle(term.text.color.opacity(0.9)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(term.terminal.background.color))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(selected ? t.accent.color : Color.clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open \(item.session.name) in \(w.name)")
        .accessibilityLabel("\(item.session.name), \(w.name), \(item.status.label)")
    }

    /// Opens the tile's window at Single on its session (this window too).
    private func open(_ w: WindowState, _ item: BoardItem) {
        win.layout = .single
        controller.v2Page = nil
        let target = (NSApp.delegate as? AppDelegate)?.openWindow(for: w)
        w.selectedId = item.id
        target?.win.layout = .single
        if w.place != .sessions { w.open(.sessions) } else if w.centre != .workspace { model.show(.workspace, in: w) }
    }
}
