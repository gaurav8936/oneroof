import AppKit
import SwiftUI
import OneRoofCore

/// What the v2 Search adds to today's palette items.
struct V2SearchOptions {
    /// Observed so Learn's answers appear once its index has loaded (it loads in the background on first use).
    var model: AppModel
    /// Learn's best answers for the text (BEST ANSWER, A10.2).
    var best: (String) -> [PaletteItem]
    /// More Learn pages for the text (LEARN, A10.5).
    var learn: (String) -> [PaletteItem]
    /// The selected session ⌘↩ sends to, when it has a live agent.
    var sendTarget: String?
    var send: (String) -> Void
}

/// Search ⌘K in the v2 window (handover A10.2 and A10.5): today's palette sources — views, actions, windows,
/// decisions, Roof windows, themes, sessions, objectives, projects, the selected repo's files (up to 4,000), skills —
/// plus Learn, grouped by source under small headers, Best answer first. ↑↓ move, ↩ opens, ⌘↩ sends the typed text to
/// the selected session, Esc closes.
struct V2SearchPalette: View {
    let items: [PaletteItem]
    let options: V2SearchOptions
    @Binding var query: String
    let close: () -> Void
    @ObservedObject private var model: AppModel
    /// Groups opened with "Show all n" (every match of that source, as 0.5's flat list could reach).
    @State private var expanded: Set<String> = []
    @State private var index = 0

    init(items: [PaletteItem], options: V2SearchOptions, query: Binding<String>, close: @escaping () -> Void) {
        self.items = items; self.options = options; _query = query; self.close = close; self.model = options.model
    }
    @FocusState private var focused: Bool

    /// Header order (A10.5).
    static let order = ["Best answer", "Views", "Actions", "Windows", "Decisions", "Roof windows", "Theme", "Sessions",
                        "Objectives", "Projects", "Repo files", "Skills", "Learn"]

    static func group(_ i: PaletteItem) -> String {
        if i.title.hasPrefix("Roof window:") { return "Roof windows" }
        switch i.kind {
        case "View": return "Views"
        case "Action": return "Actions"
        case "Window": return "Windows"
        case "Decision": return "Decisions"
        case "Theme": return "Theme"
        case "Session": return "Sessions"
        case "Objective": return "Objectives"
        case "Project": return "Projects"
        case "File": return "Repo files"
        case "Skill": return "Skills"
        case "Learn": return "Learn"
        case "Listen", "Read": return "Best answer"
        default: return "Actions"
        }
    }

    /// Groups in order, each capped so every source stays visible; with no text, the first items of each source.
    private var sections: [(String, [PaletteItem], Int)] {
        _ = model.learnItems.count   // redraw when Learn loads
        var scored: [(PaletteItem, Int)]
        if query.isEmpty {
            scored = items.map { ($0, 0) }
        } else {
            scored = items.compactMap { i in Fuzzy.score(query, i.title + " " + i.subtitle).map { (i, $0 + (Fuzzy.score(query, i.title) ?? 0)) } }
            scored.sort { $0.1 > $1.1 }
        }
        var by: [String: [PaletteItem]] = [:]
        if query.count >= 3 {
            by["Best answer"] = options.best(query)
            let bestIds = Set(by["Best answer"]!.map(\.title))
            by["Learn"] = options.learn(query).filter { !bestIds.contains($0.title) }
        }
        var total: [String: Int] = [:]
        for (i, _) in scored {
            let g = Self.group(i)
            total[g, default: 0] += 1
            if expanded.contains(g) || by[g, default: []].count < (query.isEmpty ? 3 : 5) { by[g, default: []].append(i) }
        }
        return Self.order.compactMap { g in by[g].flatMap { $0.isEmpty ? nil : (g, $0, max(total[g] ?? 0, $0.count)) } }
    }

    var body: some View {
        let s = sections
        let flat = s.flatMap(\.1)
        VStack(spacing: 0) {
            TextField("Search, or ask how do I…", text: $query)
                .textFieldStyle(.plain).font(.system(size: 16)).focused($focused)
                .padding(.horizontal, 16).padding(.vertical, 13)
                .onChange(of: query) { _, _ in index = 0; expanded = [] }
                .onSubmit { run(flat) }
                .onKeyPress(.downArrow) { index = min(index + 1, max(flat.count - 1, 0)); return .handled }
                .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command), options.sendTarget != nil else { return .ignored }
                    send(); return .handled
                }
                .onExitCommand(perform: close)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if flat.isEmpty {
                            Text(query.isEmpty ? "Type to search." : "Nothing matches \u{201C}\(query)\u{201D}.")
                                .font(.system(size: 12.5)).foregroundStyle(.secondary).padding(16)
                        }
                        ForEach(s, id: \.0) { g, rows, total in
                            Text(g.uppercased()).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
                                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 3)
                            ForEach(rows) { item in
                                let i = flat.firstIndex { $0.id == item.id } ?? 0
                                row(item, on: i == index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { index = i; run(flat) }
                                    .id(item.id)
                            }
                            if total > rows.count {
                                Button { expanded.insert(g) } label: {
                                    Text("Show all \(total) \(g.lowercased())").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color.accentColor)
                                }
                                .buttonStyle(.plain).padding(.horizontal, 42).padding(.vertical, 3)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .onChange(of: index) { _, i in if flat.indices.contains(i) { proxy.scrollTo(flat[i].id) } }
            }
            .frame(height: 380)
            Divider()
            Text("↩ open · ⌘↩ send to \(options.sendTarget ?? "a session") · grouped by source: views, actions, windows, decisions, Roof windows, themes, sessions, objectives, projects, repo files (selected repo, up to 4,000), skills, Learn")
                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 640)
        .background(.regularMaterial)
        .onAppear { focused = true }
    }

    private func row(_ item: PaletteItem, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).frame(width: 16).foregroundStyle(.secondary)
            (Text(item.title).font(.system(size: 13, weight: .semibold))
             + Text(item.subtitle.isEmpty ? "" : "  " + item.subtitle).font(.system(size: 12)).foregroundColor(.secondary))
                .lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            Text(item.kind).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(on ? Color.accentColor.opacity(0.18) : .clear)
    }

    private func run(_ flat: [PaletteItem]) {
        guard flat.indices.contains(index) else { return }
        let item = flat[index]
        close()
        DispatchQueue.main.async { item.run() }
    }

    /// ⌘↩: the typed text goes to the selected session as its next message (refused while it is busy).
    private func send() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, options.sendTarget != nil else { return }
        close()
        DispatchQueue.main.async { options.send(text) }
    }
}
