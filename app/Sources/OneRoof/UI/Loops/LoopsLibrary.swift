import AppKit
import SwiftUI
import OneRoofCore

// LAB-2294 · 7h Library (definitions) (handover 09-7h.png, pages/7h-library): every loop with the same columns whoever made
// it (LOOP origin · by | KIND · subtype | WATCHES / DOES | WHEN | MAY ACT BY | STATE), kind tabs with counts, search and
// state chips with "n of N", and HOW IT'S SET UP for the selected loop with the actions its state allows (How it's doing ›,
// Edit or Edit the file, Duplicate, Set up, Turn on with 3 trial runs, Set kind). The Gallery (kinds, what each produces,
// a real sample, Start from this) stays one button away. Real data: LoopBoard.rows (the kit's on/off and mode),
// LoopStore's loops (goal, act, file), LoopSetup (needs setup with the key, LP-11).

struct LoopsLibrary: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    @State private var state: LoopsV7Setup.LibraryState?
    @State private var gallery = false
    @State private var confirmOn: String?
    @State private var setKind: [String]?
    @State private var width: CGFloat = 1100
    @FocusState private var searchFocused: Bool

    static let loopW: CGFloat = 178, kindW: CGFloat = 132, whenW: CGFloat = 104, actW: CGFloat = 86, stateW: CGFloat = 118

    private var filter: Binding<LoopFilter> { nav.filter("7h") }

    var body: some View {
        let all = libraryRows
        let shown = LoopsV7Setup.ordered(LoopsV7Setup.filter(all, query: filter.wrappedValue.query, family: filter.wrappedValue.family, state: state))
        let sel = shown.first { $0.id == nav.librarySelected } ?? shown.first
        VStack(alignment: .leading, spacing: 12) {
            kindTabs(all)
            filterRow(shown: shown.count, all: all.count)
            if gallery {
                ScrollView {
                    LoopGalleryView(board: board, openLoop: actions.openLoop, startFrom: actions.startFrom).padding(.bottom, 8)
                }
                .defaultScrollAnchor(.top)
                .accessibilityLabel("Loop gallery")
            } else {
                HStack(alignment: .top, spacing: 16) {
                    table(shown, selected: sel?.id)
                    if let sel, width >= 860 {
                        ScrollView { setupPanel(sel) }.frame(width: 340)
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .alert(confirmOn.map { "Turn on \(board.row($0)?.name ?? $0)?" } ?? "", isPresented: Binding(get: { confirmOn != nil }, set: { if !$0 { confirmOn = nil } }),
               presenting: confirmOn) { id in
            Button("Turn on, in trial") { turnOn(id); confirmOn = nil }
            Button("Cancel", role: .cancel) { confirmOn = nil }
        } message: { id in
            Text(turnOnMessage(id))
        }
        .sheet(item: Binding(get: { setKind.map { LoopSetKindRequest(ids: $0) } }, set: { setKind = $0?.ids })) { r in
            LoopSetKindSheet(board: board, ids: r.ids) { setKind = nil }.themed(t.name)
        }
    }

    // MARK: Rows from the board

    private var libraryRows: [LoopsV7Setup.LibraryRow] {
        let byId = Dictionary(board.loops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return board.rows.map { r in
            let l = byId[r.id]
            let needs: Bool = { if case .notConfigured = board.setup[r.id] { return true }; return false }()
            return LoopsV7Setup.libraryRow(r, loop: l, act: l?.act, needsSetup: needs, kitKnown: board.kitKnown,
                                           oneRoofTrial: oneRoofTrial(r, l), file: l.flatMap(Self.file))
        }
    }

    /// One Roof's engine has no shadow mode: a loop of its own is labelled trial for its first 3 runs (LP-12, label only).
    private func oneRoofTrial(_ r: LoopRow, _ l: Loop?) -> Bool {
        guard r.engine == .oneRoof, r.on, let l else { return false }
        let since = (board.runsByLoop[r.id] ?? []).filter { (LoopRun7.date($0.started) ?? .distantPast) >= l.createdAt }.count
        return LoopsV7Setup.oneRoofTrial(on: true, runsSinceCreated: since)
    }

    /// The file a loop is defined in: a kit file's .loop.yaml, a built-in's file in the kit, One Roof's loop.json.
    static func file(_ l: Loop) -> String? {
        if let f = l.specFile { return f }
        if l.origin == .builtIn {
            let p = LoopBuiltIns.defaultRepoPath() + "/kit/loops/\(l.id).loop.yaml"
            return FileManager.default.fileExists(atPath: p) ? p : nil
        }
        return LoopStore().folder(l.id) + "/loop.json"
    }

    // MARK: Kind tabs and the filter row

    private func kindTabs(_ all: [LoopsV7Setup.LibraryRow]) -> some View {
        HStack(spacing: 22) {
            ForEach(LoopsV7Setup.kindCounts(all), id: \.id) { k in
                let on = (filter.wrappedValue.family ?? "all") == k.id
                Button { filter.wrappedValue.family = k.id == "all" ? nil : k.id } label: {
                    HStack(spacing: 5) {
                        Text(k.title).ui(14, on ? .semibold : .medium).foregroundStyle((on ? t.text : t.text2).color)
                        Text("\(k.count)").ui(12.5, .medium).foregroundStyle(t.text2.color)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) { Rectangle().fill(on ? t.text.color : .clear).frame(height: 2).offset(y: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(k.title), \(k.count) loops" + (on ? ", selected" : ""))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }

    private func filterRow(shown: Int, all: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text3.color).accessibilityHidden(true)
                TextField("Search loops, what they watch, their files…", text: filter.query)
                    .textFieldStyle(.plain).ui(13).focused($searchFocused)
                    .accessibilityLabel("Search loops")
                Button("", action: { searchFocused = true }).keyboardShortcut("f", modifiers: .command).frame(width: 0, height: 0).opacity(0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10).frame(height: 30).frame(maxWidth: 320)
            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separatorStrong.color))
            stateChip("Any state", on: state == nil) { state = nil }
            ForEach(LoopsV7Setup.LibraryState.allCases, id: \.self) { s in
                stateChip(s.label, on: state == s) { state = state == s ? nil : s }
            }
            Spacer(minLength: 8)
            RoofButton(gallery ? "‹ Definitions" : "Gallery") { gallery.toggle() }
                .help("The kinds of loops, what each produces, a real sample of each, and Start from this")
            Text(LoopsV7Setup.countLine(shown: shown, all: all)).ui(12.5).foregroundStyle(t.text2.color)
                .accessibilityLabel("\(shown) of \(all) loops shown")
        }
    }

    private func stateChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ui(12.5, .semibold).foregroundStyle((on ? t.onAccent : t.text).color)
                .padding(.vertical, 4).padding(.horizontal, 11)
                .background(Capsule().fill(on ? t.text.color : .clear))
                .overlay(Capsule().strokeBorder((on ? t.text : t.separatorStrong).color, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(radius: 12))
        .accessibilityLabel("State " + title + (on ? ", selected" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: The table

    private func table(_ rows: [LoopsV7Setup.LibraryRow], selected: String?) -> some View {
        LoopCard(padding: 0, shadow: false) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    head("Loop").frame(width: Self.loopW, alignment: .leading)
                    head("Kind").frame(width: Self.kindW, alignment: .leading)
                    head("Watches / does").frame(maxWidth: .infinity, alignment: .leading)
                    head("When").frame(width: Self.whenW, alignment: .leading)
                    head("May act by").frame(width: Self.actW, alignment: .leading)
                    head("State").frame(width: Self.stateW, alignment: .leading)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                Rectangle().fill(t.separator.color).frame(height: 1)
                if rows.isEmpty {
                    HStack(spacing: 10) {
                        Text(LoopsV7Setup.emptyLine(query: filter.wrappedValue.query, family: filter.wrappedValue.family, state: state))
                            .ui(13).foregroundStyle(t.text2.color)
                        RoofButton("Clear", .plain) { filter.wrappedValue = LoopFilter(); state = nil }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                                if i > 0 { Rectangle().fill(t.separator.color.opacity(0.6)).frame(height: 1).padding(.horizontal, 8) }
                                row(r, selected: r.id == selected)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .defaultScrollAnchor(.top)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func head(_ s: String) -> some View { LoopLabel(s) }

    private func row(_ r: LoopsV7Setup.LibraryRow, selected: Bool) -> some View {
        Button { nav.librarySelected = r.id } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail)
                    Text(r.originLine).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                }
                .frame(width: Self.loopW, alignment: .leading)
                LoopLibraryKindTag(family: r.family, words: r.kindWords).frame(width: Self.kindW, alignment: .leading)
                Text(r.watches).ui(12.5).foregroundStyle(t.text.color).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(r.when).ui(12.5).foregroundStyle(t.text.color).lineLimit(2).frame(width: Self.whenW, alignment: .leading)
                Text(r.mayAct).ui(12.5).foregroundStyle(t.text.color).lineLimit(1).frame(width: Self.actW, alignment: .leading)
                LoopLibraryStateChip(label: r.stateLabel, tone: r.tone).frame(width: Self.stateW, alignment: .leading)
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .hoverHighlight(selected: selected)
        .padding(.horizontal, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.name), \(r.originLine), \(r.kindWords), \(r.watches), \(r.when), may act by \(r.mayAct), \(r.stateLabel)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: How it's set up

    private func setupPanel(_ r: LoopsV7Setup.LibraryRow) -> some View {
        let l = board.loops.first { $0.id == r.id }
        let missing: [String] = { if case .notConfigured(let m) = board.setup[r.id] { return m }; return [] }()
        return VStack(alignment: .leading, spacing: 10) {
            MicroLabel("How it's set up")
            VStack(alignment: .leading, spacing: 3) {
                Text(r.name).ui(TypeScale.title - 2, .bold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text([r.kindWords, r.originLine, r.stateLabel].joined(separator: " · ")).ui(12.5).foregroundStyle(t.text2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            section("Goal", r.goal.isEmpty ? "No goal written." : r.goal)
            section("When · who runs it", LoopsV7Setup.whoRuns(when: r.when, engine: r.engine))
            section("May act by", LoopsV7Setup.mayActSentence(r.mayAct))
            if !missing.isEmpty {
                Hairline()
                VStack(alignment: .leading, spacing: 4) {
                    LoopLabel("Needs setup")
                    ForEach(missing, id: \.self) { m in
                        Text(m).ui(12.5).foregroundStyle(LoopLook.tone(.needsYou, theme: t.name).text.color).fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
            if let f = r.file {
                Hairline()
                VStack(alignment: .leading, spacing: 3) {
                    LoopLabel("File")
                    Text((f as NSString).abbreviatingWithTildeInPath).ui(12, mono: true).foregroundStyle(t.text.color)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let l { panelActions(r, l, needsSetup: !missing.isEmpty) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.text.color, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How \(r.name) is set up")
    }

    private func section(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Hairline()
            LoopLabel(label).padding(.top, 4)
            Text(text).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    @ViewBuilder private func panelActions(_ r: LoopsV7Setup.LibraryRow, _ l: Loop, needsSetup: Bool) -> some View {
        let editable = LoopsV7Setup.kindEdit(l)
        LoopsWrap(spacing: 8) {
            RoofButton("How it's doing ›", .primary) { actions.openLoop(r.id) }
                .help("This loop now: its runs, rounds and results")
            if case .oneRoof = editable {
                RoofButton("Edit") { nav.open(.edit(id: r.id, name: r.name)) }
            } else if let f = r.file {
                RoofButton("Edit the file") { model.openInViewer(f) }
                    .help(l.origin == .builtIn ? "The kit's file for this loop (the kit owns it: copy it as yours to change it)" : "The kit owns this loop's file: change it there")
            }
            RoofButton(l.origin == .builtIn ? "Duplicate as mine" : "Duplicate") { actions.startFrom(l) }
                .help("Start from this: a new loop of yours with its settings, in New loop")
            if needsSetup {
                RoofButton("Set up") { openSetup(r.id) }
                    .help("Open the kit's config at this loop's settings")
            } else if !r.on && (r.engine == .oneRoof || board.kitKnown) {
                RoofButton("Turn on (\(LoopsV7Setup.trialRuns) trial runs)") { confirmOn = r.id }
            }
            if case .builtIn = editable {} else if LoopKinds.kind(l.kind) == nil {
                RoofButton("Set kind…") { setKind = [r.id] }
                    .help(LoopsV7Setup.suggestionLine(l) ?? "Give it a kind so it shows in that lane")
            }
        }
    }

    private func openSetup(_ id: String) {
        guard let cfg = board.aeConfigPath else { model.openInViewer(LoopBuiltIns.defaultRepoPath()); return }
        let key = board.setupItems.first { $0.loop == id && $0.key != nil }?.key ?? "loops.settings.\(id)"
        let line = (try? String(contentsOfFile: cfg, encoding: .utf8)).flatMap { LoopsV7Setup.configLine(key, in: $0) }
        model.openInViewer(cfg, line: line)
    }

    private func turnOnMessage(_ id: String) -> String {
        if board.row(id)?.engine == .kit {
            return "The kit turns it on (`\(KitLoops.command("on", id).dropFirst().joined(separator: " "))`): it adds the loop to its config and its launchd schedule, and starts with \(LoopsV7Setup.trialRuns) trial nights that only say what they would do. It asks before going live."
        }
        return "One Roof turns it on; roofd runs it on its schedule. One Roof's engine has no shadow mode yet: its first \(LoopsV7Setup.trialRuns) runs are labelled trial and work only on the loop's own branch. Nothing leaves it until you approve."
    }

    private func turnOn(_ id: String) {
        if board.row(id)?.engine == .kit { board.turnOnKit(id) } else { board.resume(id) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() }
    }
}

// MARK: - Pieces

/// "Watch · Sentinel" in the kind's colour (kind colours only for kind names and tags).
struct LoopLibraryKindTag: View {
    @Environment(\.theme) private var t
    let family: String
    let words: String
    var body: some View {
        let k = LoopLook.kind(family, theme: t.name)
        Text(words).ui(11, .semibold).foregroundStyle(k.text.color).lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(k.fill.color))
            .fixedSize()
            .accessibilityLabel("Kind: " + words)
    }
}

/// "on · live", "on · trial", "on · failing", "off", "needs setup" in its state colour; off outlined.
struct LoopLibraryStateChip: View {
    @Environment(\.theme) private var t
    let label: String
    let tone: LoopLook.Tone
    var body: some View {
        let p = LoopLook.tone(tone, theme: t.name)
        Text(label).ui(11, .semibold).foregroundStyle(p.text.color).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(p.fill.color))
            .overlay { if tone == .off { Capsule().strokeBorder(t.separatorStrong.color, lineWidth: 1) } }
            .fixedSize()
            .accessibilityLabel("State: " + label)
    }
}

/// Buttons that wrap onto a second line when the panel is narrow.
struct LoopsWrap: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW { y += line + spacing; x = 0; line = 0 }
            x += sz.width + spacing; line = max(line, sz.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, line: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > b.minX && x + sz.width > b.maxX { y += line + spacing; x = b.minX; line = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; line = max(line, sz.height)
        }
    }
}
