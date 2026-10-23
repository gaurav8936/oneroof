import AppKit
import SwiftUI
import OneRoofCore

/// Editor: text and code open here; Markdown and HTML open formatted in the viewer and here in Source mode (LAB-479,
/// LAB-480); images, folders and search keep the v0.1 viewer. Tabs ·
/// claim banner · NSTextView editor with gutter (line numbers, attribution, breakpoints), syntax colours and problem
/// lines · run dock (a real libghostty terminal) · inspector (Outline · Problems · Git · Plan, On this file).
/// No LSP. Saving waits while another session's step claims the file.
struct EditorView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState

    init(model: AppModel, win: WindowState) {
        self.model = model
        self.win = win
        self.state = EditorState.of(win.id)
        if let p = win.viewerPath, FileKind.of(p) == .text { state.open(p) }
    }

    var body: some View {
        let path = win.viewerPath ?? ""
        let kind = FileKind.of(path)
        Group {
            if DocumentRoute.opensInEditor(kind.core, mode: state.mode(for: path)) {
                EditorBody(model: model, win: win, state: state, path: path)
            } else {
                FileViewer(model: model, path: path,
                           onSource: DocumentRoute.hasPreview(kind.core) ? { state.setMode(.source, for: path) } : nil,
                           unsaved: state.isDirty(path) ? state.texts[path] : nil)
            }
        }
        .onAppear { if kind == .text { state.open(path) } }
        .onChange(of: win.viewerPath) { _, p in if let p, FileKind.of(p) == .text { state.open(p) } }
    }
}

/// Per-window editor state: open tabs, unsaved text, breakpoints, run dock.
final class EditorState: ObservableObject {
    @Published var tabs: [String] = []
    @Published var texts: [String: String] = [:]
    @Published var saved: [String: String] = [:]
    @Published var breakpoints: [String: Set<Int>] = [:]
    @Published var sourceMode: Set<String> = []
    @Published var problems: [String: [Problem]] = [:]
    @Published var queuedSave: String?
    @Published var dockOpen = true
    @Published var runs: [DockRun] = []
    @Published var dockTab: String?
    @Published var inspectorTab = "outline"
    @Published var askFor: AskRequest?

    struct DockRun: Identifiable, Equatable {
        var id: String
        var title: String
        var command: String
        var cwd: String
    }

    struct AskRequest: Identifiable {
        var id = UUID()
        var path: String
        var from: Int
        var to: Int
        var text: String
    }

    private static var all: [String: EditorState] = [:]
    static func of(_ id: String) -> EditorState {
        if let s = all[id] { return s }
        let s = EditorState()
        all[id] = s
        return s
    }

    func open(_ path: String) {
        guard !path.isEmpty else { return }
        if !tabs.contains(path) { tabs.append(path) }
        if texts[path] == nil {
            let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            texts[path] = text
            saved[path] = text
        }
    }

    func isDirty(_ path: String) -> Bool { texts[path] != saved[path] }

    /// Markdown and HTML: Preview (formatted, the default) or Source (this editor).
    func mode(for path: String) -> ViewerMode { sourceMode.contains(path) ? .source : .preview }

    func setMode(_ m: ViewerMode, for path: String) {
        if m == .source { sourceMode.insert(path); open(path) } else { sourceMode.remove(path) }
    }

    func close(_ path: String) {
        sourceMode.remove(path)
        tabs.removeAll { $0 == path }
        if !isDirty(path) { texts[path] = nil; saved[path] = nil }
    }

    func write(_ path: String) -> String? {
        guard let t = texts[path] else { return nil }
        do { try t.write(toFile: path, atomically: true, encoding: .utf8); saved[path] = t; return nil }
        catch { return "\(error.localizedDescription)" }
    }
}

private struct EditorBody: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState
    let path: String
    @State private var status: String?
    @State private var dockHeight: CGFloat = 250

    var claim: FileClaim? { model.fileClaims.blockingClaim(for: path, me: nil) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                tabBar
                if let c = claim { claimBanner(c) }
                CodeEditor(model: model, state: state, path: path, theme: t.name, line: win.viewerLine)
                    .id(path)
                if state.dockOpen {
                    RunDock(model: model, win: win, state: state, height: $dockHeight)
                        .frame(height: dockHeight)
                        .themed(.midnight, scale: win.textScale)
                }
                if let status {
                    Text(status).ui(11.5).foregroundStyle(t.text2.color).padding(.horizontal, 12).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading).background(t.toolbar.color)
                }
            }
            Rectangle().fill(t.separator.color).frame(width: 1)
            EditorInspector(model: model, win: win, state: state, path: path)
                .frame(width: 300)
                .themed(model.themes.plan, scale: win.textScale)
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveFile)) { n in
            guard (n.object as? String) == win.id else { return }
            save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .runFile)) { n in
            guard let a = n.object as? [String], a.first == win.id else { return }
            run(debug: a.count > 1 && a[1] == "debug")
        }
        .onReceive(NotificationCenter.default.publisher(for: .askAboutSelection)) { n in
            guard (n.object as? String) == win.id else { return }
            NotificationCenter.default.post(name: .editorAsk, object: path)
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in flushQueuedSave() }
        .sheet(item: $state.askFor) { req in AskAgentSheet(model: model, request: req) { state.askFor = nil }.themed(t.name) }
        .onAppear(perform: loadProblems)
    }

    // MARK: Tabs

    private var tabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(state.tabs, id: \.self) { p in
                        let on = p == path
                        Button { win.show(path: p) } label: {
                            HStack(spacing: 6) {
                                Text((p as NSString).lastPathComponent).ui(12.5, on ? .semibold : .regular).foregroundStyle(on ? t.text.color : t.text2.color)
                                if state.isDirty(p) { Circle().fill(t.text.color).frame(width: 6, height: 6).accessibilityLabel("unsaved") }
                                Button { state.close(p); if on { if let n = state.tabs.last { win.show(path: n) } else { model.show(.workspace, in: win) } } } label: {
                                    Text("✕").ui(9).foregroundStyle(t.text3.color)
                                }.buttonStyle(.plain)
                            }
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(on ? t.surface.color : .clear)
                            .overlay(alignment: .top) { if on { Rectangle().fill(t.accent.color).frame(height: 2) } }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(t.separator.color).frame(width: 1, height: 34)
                    }
                }
            }
            Spacer()
            if DocumentRoute.hasPreview(FileKind.of(path).core) {
                Segmented(options: [(ViewerMode.preview, "Preview"), (.source, "Source")],
                          selection: Binding(get: { state.mode(for: path) }, set: { state.setMode($0, for: path) }))
                    .help("Preview shows the page formatted; Source edits it")
                    .padding(.trailing, 10)
            }
            Text("Split editor ⌘\\").ui(11.5).foregroundStyle(t.text3.color).padding(.trailing, 12)
        }
        .frame(height: 34)
        .background(t.toolbar.color)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func claimBanner(_ c: FileClaim) -> some View {
        let item = model.item(c.sessionId)
        let mark = item.map { AgentMark(agent: $0.session.agent, account: $0.account) } ?? .claude1
        let who = item.map { $0.account ?? $0.session.agent.displayName } ?? "An agent"
        return HStack(spacing: 8) {
            AgentBadge(mark, size: 18)
            (Text("\(who) has claimed this file").fontWeight(.semibold).foregroundColor(t.text.color)
             + Text(" · \(item?.session.name ?? "")" + (c.step.map { " · step \($0)" } ?? "")).foregroundColor(t.text2.color))
                .ui(12.5).lineLimit(1)
            Spacer()
            Text(state.queuedSave == path ? "Your save waits for this step" : "Your save waits for this step").ui(12.5).foregroundStyle(t.statusDone.color)
            Button { takeOver(c) } label: { Text("· Take over").ui(12.5, .semibold).foregroundStyle(t.statusDone.color) }.buttonStyle(.plain)
        }
        .padding(.vertical, 7).padding(.horizontal, 14)
        .background(mark.fill.color.opacity(0.08))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Save, run, take over

    private func save() {
        if claim != nil {
            state.queuedSave = path
            status = "Saved after the agent's step: your save waits until \(model.item(claim!.sessionId)?.session.name ?? "the agent") finishes it."
            return
        }
        status = state.write(path).map { "Save failed: \($0)" } ?? "Saved."
        loadProblems()
    }

    private func flushQueuedSave() {
        guard let q = state.queuedSave, model.fileClaims.blockingClaim(for: q, me: nil) == nil else { return }
        // The agent may have changed the file meanwhile: keep its version if it did, and say so.
        let disk = (try? String(contentsOfFile: q, encoding: .utf8)) ?? ""
        if disk != state.saved[q] {
            status = "\((q as NSString).lastPathComponent) changed while you waited; your edits are kept in the editor, not written. Review and save again."
            state.saved[q] = disk
        } else {
            status = state.write(q).map { "Save failed: \($0)" } ?? "Saved after the step."
        }
        state.queuedSave = nil
    }

    private func takeOver(_ c: FileClaim) {
        guard let item = model.item(c.sessionId), let agent = item.liveAgent else { return }
        model.interrupt(item)
        let r = model.runtime, p = path
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { try? r.submit(agent, text: "Pause edits to \(p); the owner is editing it.") }
        model.fileClaims.endSession(sessionId: c.sessionId)
        model.objectWillChange.send()
        status = "Asked \(item.session.name) to pause edits to this file."
    }

    private var repoRoot: String { GitDiff.repoRoot(for: path) ?? (path as NSString).deletingLastPathComponent }

    private func run(debug: Bool) {
        if state.isDirty(path) && claim == nil { _ = state.write(path) }
        guard let cfg = RunConfig.detect(file: path, repoRoot: repoRoot) else { status = "Nothing to run for this file."; return }
        let argv = debug ? (cfg.debug ?? cfg.run) : cfg.run
        var cmd = argv.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
        if debug, let bps = state.breakpoints[path], !bps.isEmpty, argv.contains("pdb") {
            // pdb breakpoints are typed on start (S07 §1.7), never injected into the file.
            cmd = "printf '" + bps.sorted().map { "b \(path):\($0)\\n" }.joined() + "c\\n' | " + cmd
        }
        let id = (debug ? "debug:" : "run:") + path
        let run = EditorState.DockRun(id: id + "#\(Date().timeIntervalSince1970)", title: (debug ? "Debug: " : "Run: ") + (path as NSString).lastPathComponent,
                                      command: cmd, cwd: cfg.cwd)
        state.runs.removeAll { $0.id.hasPrefix(id) }
        state.runs.append(run)
        state.dockTab = run.id
        state.dockOpen = true
    }

    private func loadProblems() {
        guard let cmd = Problems.command(for: path, repoRoot: repoRoot) else { return }
        let p = path, root = repoRoot
        DispatchQueue.global(qos: .utility).async {
            let (_, out) = Foundations.run(cmd.argv[0], Array(cmd.argv.dropFirst()), timeout: 20)
            let list: [Problem]
            switch cmd.tool {
            case "ruff": list = Problems.parseRuff(json: out)
            case "swiftlint": list = Problems.parseSwiftlint(json: out)
            default: list = Problems.parseTsc(text: out)
            }
            let mine = list.filter { $0.path == p || root + "/" + $0.path == p || p.hasSuffix("/" + $0.path) }
            DispatchQueue.main.async { state.problems[p] = mine }
        }
    }
}

extension Notification.Name {
    /// ▶ Run / Debug in the editor (object: [workspace id] or [workspace id, "debug"]).
    static let runFile = Notification.Name("oneroof.runFile")
    static let editorAsk = Notification.Name("oneroof.editorAsk")
}

// MARK: - The text view

/// NSTextView with a gutter: line numbers, attribution bar, breakpoints. Syntax colours from the in-house lexers.
struct CodeEditor: NSViewRepresentable {
    @ObservedObject var model: AppModel
    @ObservedObject var state: EditorState
    let path: String
    let theme: ThemeName
    var line: Int?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        layout.addTextContainer(container)
        let code = CodeTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), textContainer: container)
        code.autoresizingMask = [.width]
        code.minSize = NSSize(width: 0, height: 0)
        code.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        code.isVerticallyResizable = true
        code.isHorizontallyResizable = true
        scroll.hasHorizontalScroller = true
        scroll.documentView = code
        code.isRichText = false
        code.allowsUndo = true
        code.isAutomaticQuoteSubstitutionEnabled = false
        code.isAutomaticDashSubstitutionEnabled = false
        code.isAutomaticTextReplacementEnabled = false
        code.isAutomaticSpellingCorrectionEnabled = false
        code.textContainerInset = NSSize(width: 6, height: 8)
        code.delegate = context.coordinator
        code.onAsk = { [weak coordinator = context.coordinator] in coordinator?.ask() }
        code.string = state.texts[path] ?? ""
        let gutter = GutterView(scrollView: scroll, orientation: .verticalRuler)
        gutter.clientView = code
        gutter.onToggle = { [weak coordinator = context.coordinator] l in coordinator?.toggleBreakpoint(l) }
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        context.coordinator.text = code
        context.coordinator.gutter = gutter
        context.coordinator.restyle()
        if let line { context.coordinator.scroll(to: line) }
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.askNote(_:)), name: .editorAsk, object: nil)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        // The file's text arrives after the view is made (EditorState.open); fill it in unless the owner is typing.
        if let tv = context.coordinator.text, let text = state.texts[path], tv.string != text, tv.window?.firstResponder !== tv {
            tv.string = text
            if let line { context.coordinator.scroll(to: line) }
        }
        context.coordinator.restyle()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var text: CodeTextView?
        weak var gutter: GutterView?
        private var lastStyled: (String, ThemeName, Int)?
        init(_ p: CodeEditor) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = text else { return }
            parent.state.texts[parent.path] = tv.string
            restyle(force: true)
        }

        @objc func askNote(_ n: Notification) { if (n.object as? String) == parent.path { ask() } }

        func ask() {
            guard let tv = text else { return }
            let r = tv.selectedRange()
            let ns = tv.string as NSString
            let from = ns.substring(to: min(r.location, ns.length)).components(separatedBy: "\n").count
            let to = from + ns.substring(with: r).components(separatedBy: "\n").count - 1
            parent.state.askFor = EditorState.AskRequest(path: parent.path, from: from, to: max(from, to), text: ns.substring(with: r))
        }

        func toggleBreakpoint(_ line: Int) {
            var b = parent.state.breakpoints[parent.path] ?? []
            if b.contains(line) { b.remove(line) } else { b.insert(line) }
            parent.state.breakpoints[parent.path] = b
            gutter?.breakpoints = b
        }

        func scroll(to line: Int) {
            guard let tv = text else { return }
            let ns = tv.string as NSString
            var loc = 0
            for _ in 1..<max(1, line) {
                let r = ns.range(of: "\n", options: [], range: NSRange(location: loc, length: ns.length - loc))
                if r.location == NSNotFound { break }
                loc = r.location + 1
            }
            DispatchQueue.main.async {
                tv.scrollRangeToVisible(NSRange(location: loc, length: 0))
                tv.setSelectedRange(NSRange(location: loc, length: 0))
            }
        }

        /// Colours, problem lines and agent attribution. Recomputed when the text, theme or problem count changes.
        func restyle(force: Bool = false) {
            guard let tv = text, let storage = tv.textStorage else { return }
            let p = parent
            let tk = p.theme.tokens
            let problems = p.state.problems[p.path] ?? []
            let key = (tv.string, p.theme, problems.count)
            if !force, let l = lastStyled, l.0 == key.0, l.1 == key.1, l.2 == key.2 { return }
            lastStyled = key
            tv.backgroundColor = tk.surface.nsColor
            tv.insertionPointColor = tk.accent.nsColor
            tv.selectedTextAttributes = [.backgroundColor: tk.selection.over(tk.surface).nsColor]
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.35
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: tk.text.nsColor, .paragraphStyle: para], range: full)
            for tok in Lexer.tokens(tv.string, language: SourceLanguage.detect(path: p.path)) where tok.kind != .plain {
                let r = NSRange(location: tok.location, length: tok.length)
                guard NSMaxRange(r) <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: tk.syntax(tok.kind).nsColor, range: r)
                if tok.kind == .keyword {
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12.5, weight: .semibold), range: r)
                }
            }
            // Problem lines: now-tinted background (S07 §1.5).
            let ns = tv.string as NSString
            var lineStarts = [0]
            var i = 0
            while i < ns.length {
                let r = ns.range(of: "\n", options: [], range: NSRange(location: i, length: ns.length - i))
                if r.location == NSNotFound { break }
                lineStarts.append(r.location + 1)
                i = r.location + 1
            }
            for pr in problems where pr.line >= 1 && pr.line <= lineStarts.count {
                let start = lineStarts[pr.line - 1]
                let end = pr.line < lineStarts.count ? lineStarts[pr.line] : ns.length
                storage.addAttribute(.backgroundColor, value: tk.now.opacity(0.12).over(tk.surface).nsColor, range: NSRange(location: start, length: max(0, end - start)))
            }
            storage.endEditing()
            gutter?.tokens = tk
            gutter?.breakpoints = p.state.breakpoints[p.path] ?? []
            gutter?.problemLines = Set(problems.map(\.line))
            gutter?.agentLines = p.model.agentChangedLines(p.path)
            gutter?.needsDisplay = true
        }
    }
}

/// The text view: ⌘I asks an agent about the selection.
final class CodeTextView: NSTextView {
    var onAsk: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "i",
           window?.firstResponder === self {
            onAsk?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The gutter (S07 §1.5): 44 pt line numbers in text3, a 4 pt attribution bar (agent colour), red breakpoint dots.
final class GutterView: NSRulerView {
    var tokens = ThemeName.daylight.tokens
    var breakpoints: Set<Int> = []
    var problemLines: Set<Int> = []
    var agentLines: [Int: AgentMark] = [:]
    var onToggle: ((Int) -> Void)?

    override init(scrollView: NSScrollView?, orientation: NSRulerView.Orientation) {
        super.init(scrollView: scrollView, orientation: orientation)
        ruleThickness = 52
    }
    required init(coder: NSCoder) { fatalError("not supported") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        tokens.surface.nsColor.setFill(); bounds.fill()
        guard let tv = clientView as? NSTextView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let ns = tv.string as NSString
        let visible = tv.visibleRect
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        var line = ns.substring(to: chars.location).components(separatedBy: "\n").count
        var i = chars.location
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: tokens.text3.nsColor]
        let relative = convert(NSPoint.zero, from: tv)
        while i <= NSMaxRange(chars) && i <= ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: min(i, max(0, ns.length - 1)), length: 0))
            let g = lm.glyphRange(forCharacterRange: NSRange(location: lineRange.location, length: 0), actualCharacterRange: nil)
            var r = lm.lineFragmentRect(forGlyphAt: min(g.location, max(0, lm.numberOfGlyphs - 1)), effectiveRange: nil)
            r.origin.y += tv.textContainerInset.height + relative.y
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: 40 - size.width, y: r.minY + (r.height - size.height) / 2), withAttributes: attrs)
            if let m = agentLines[line] { m.fill.nsColor.setFill(); NSRect(x: 46, y: r.minY, width: 4, height: r.height).fill() }
            if breakpoints.contains(line) {
                StatusPalette.dot(.needsYou).nsColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: 4, y: r.midY - 4, width: 8, height: 8)).fill()
            }
            if problemLines.contains(line) { tokens.now.nsColor.setFill(); NSRect(x: 46, y: r.minY, width: 4, height: r.height).fill() }
            if NSMaxRange(lineRange) <= i { break }
            i = NSMaxRange(lineRange)
            line += 1
            if lineRange.length == 0 { break }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let tv = clientView as? NSTextView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let p = tv.convert(event.locationInWindow, from: nil)
        let idx = lm.characterIndex(for: NSPoint(x: 0, y: p.y - tv.textContainerInset.height), in: tc, fractionOfDistanceBetweenInsertionPoints: nil)
        let line = (tv.string as NSString).substring(to: min(idx, (tv.string as NSString).length)).components(separatedBy: "\n").count
        onToggle?(line)
        needsDisplay = true
    }
}

extension AppModel {
    /// Lines of a file changed by an agent's uncommitted edits (attribution bar): from the claims engine.
    func agentChangedLines(_ path: String) -> [Int: AgentMark] {
        guard let c = fileClaims.claim(for: path), let item = item(c.sessionId),
              let root = GitDiff.repoRoot(for: path) else { return [:] }
        let rel = String(path.dropFirst(root.count + 1))
        let snap = GitDiff.load(repo: root)
        guard let f = snap.files.first(where: { $0.path == rel }) else { return [:] }
        let mark = AgentMark(agent: item.session.agent, account: item.account)
        var out: [Int: AgentMark] = [:]
        for h in f.hunks { for l in h.lines where l.kind == .added { if let n = l.newNo { out[n] = mark } } }
        return out
    }
}

// MARK: - Run dock

/// Run dock (S07 §1.6): tabs for runs, the agent sessions in this repo, and a shell; each a real libghostty terminal.
private struct RunDock: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState
    @Binding var height: CGFloat

    var body: some View {
        let tabs = state.runs.map { ($0.id, $0.title) } + [("zsh", "zsh")]
        let current = state.dockTab ?? tabs.first?.0 ?? "zsh"
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(tabs, id: \.0) { id, title in
                    Button { state.dockTab = id } label: {
                        Text((id.hasPrefix("run") ? "▶ " : "") + title).ui(12.5, id == current ? .semibold : .regular)
                            .foregroundStyle(id == current ? t.text.color : t.text2.color)
                            .padding(.horizontal, 12).frame(height: 32)
                            .overlay(alignment: .top) { if id == current { Rectangle().fill(t.statusColor(.done).color).frame(height: 2) } }
                    }.buttonStyle(.plain)
                }
                ForEach(model.items.filter { $0.liveAgent != nil && $0.session.agent.isAgent && $0.session.repoPath == (win.viewerPath.flatMap { GitDiff.repoRoot(for: $0) } ?? "") }) { i in
                    Button { model.reveal(i) } label: {
                        HStack(spacing: 5) { StatusDot(status: i.status, size: 7); Text("\(i.account ?? "") · \(i.session.name)").ui(12.5).foregroundStyle(t.text2.color) }
                            .padding(.horizontal, 10)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { state.dockOpen = false } label: { Text("⌃` hide").ui(11.5).foregroundStyle(t.text3.color) }.buttonStyle(.plain)
                    .keyboardShortcut("`", modifiers: .control)
                    .padding(.trailing, 12)
            }
            .background(t.window.color)
            .overlay(alignment: .bottom) { Hairline() }
            .gesture(DragGesture().onChanged { v in height = min(600, max(120, height - v.translation.height)) })
            if let run = state.runs.first(where: { $0.id == current }) {
                DockTerminal(command: "/bin/zsh -lc " + Self.quote(run.command + "; echo; echo \"exit $?\"; exec /bin/zsh -l"), cwd: run.cwd).id(run.id)
            } else {
                DockTerminal(command: "/bin/zsh -l", cwd: (win.viewerPath.flatMap { GitDiff.repoRoot(for: $0) }) ?? Workspace.projectsRoot).id("zsh")
            }
        }
        .background(t.terminal.background.color)
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

/// A libghostty terminal running a command (not roofd: runs are the owner's own, not agent sessions).
private struct DockTerminal: NSViewRepresentable {
    let command: String
    let cwd: String
    func makeNSView(context: Context) -> TerminalSurfaceView {
        TerminalSurfaceView(command: command, workingDirectory: Workspace.isInsideProjects(cwd) ? cwd : Workspace.projectsRoot, theme: .midnight)
    }
    func updateNSView(_ v: TerminalSurfaceView, context: Context) {}
}

// MARK: - Inspector

private struct EditorInspector: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @ObservedObject var state: EditorState
    let path: String
    @State private var history: [String] = []

    var body: some View {
        let text = state.texts[path] ?? ""
        let problems = state.problems[path] ?? []
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                tab("outline", "Outline")
                tab("problems", "Problems \(problems.count)")
                tab("git", "Git")
                tab("plan", "Plan")
            }
            .padding(.horizontal, 16).padding(.top, 12)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    switch state.inspectorTab {
                    case "problems": problemList(problems)
                    case "git": gitList
                    case "plan": planTab
                    default: outline(text)
                    }
                    onThisFile
                }
                .padding(16)
            }
            Spacer(minLength: 0)
            Text("Select code and press ⌘I to ask any agent about it. The question goes to that agent's session with the file and lines attached.")
                .ui(12.5).foregroundStyle(t.text2.color)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .padding(16)
        }
        .background(t.window.color)
        .onAppear(perform: loadHistory)
        .onChange(of: path) { _, _ in loadHistory() }
    }

    private func tab(_ id: String, _ label: String) -> some View {
        Button { state.inspectorTab = id } label: {
            VStack(spacing: 6) {
                Text(label).ui(12.5, .semibold).foregroundStyle(state.inspectorTab == id ? t.text.color : t.text2.color)
                Rectangle().fill(state.inspectorTab == id ? t.accent.color : .clear).frame(height: 2)
            }.fixedSize()
        }.buttonStyle(.plain)
    }

    private func outline(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let items = Outline.items(text, language: SourceLanguage.detect(path: path))
            if items.isEmpty { Text("No symbols").ui(12.5).foregroundStyle(t.text3.color) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, o in
                Button { win.show(path: path, line: o.line) } label: {
                    Text((o.kind == .function ? "ƒ " : o.kind == .type ? "T " : o.kind == .section ? "# " : "") + o.name)
                        .ui(12.5, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                        .padding(.leading, CGFloat(o.depth) * 10).padding(.vertical, 3).padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private func problemList(_ problems: [Problem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if problems.isEmpty { Text("No problems found.").ui(12.5).foregroundStyle(t.text3.color) }
            ForEach(Array(problems.enumerated()), id: \.offset) { _, p in
                VStack(alignment: .leading, spacing: 6) {
                    (Text("\(p.severity == .error ? "E" : "W") · line \(p.line) ").fontWeight(.semibold).foregroundColor(t.now.color)
                     + Text((p.code.map { $0 + " " } ?? "") + p.message).foregroundColor(t.text.color))
                        .ui(12.5).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if let fix = Problems.quickFix(for: p, repoRoot: GitDiff.repoRoot(for: path) ?? "") {
                            RoofButton("Quick fix") {
                                DispatchQueue.global().async { _ = Foundations.run("/usr/bin/env", fix, timeout: 20) }
                            }
                        }
                        RoofButton("Ask agent ⌘I") {
                            state.askFor = EditorState.AskRequest(path: path, from: p.line, to: p.line, text: "\(p.tool) says: \(p.message)")
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.card.color))
                .onTapGesture { win.show(path: path, line: p.line) }
            }
        }
    }

    private var gitList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if history.isEmpty { Text("Not committed yet, or not in a git repo.").ui(12.5).foregroundStyle(t.text3.color) }
            ForEach(history, id: \.self) { h in Text(h).ui(12, mono: true).foregroundStyle(t.text.color).lineLimit(2) }
        }
    }

    @ViewBuilder private var planTab: some View {
        if let c = model.fileClaims.claim(for: path), let item = model.item(c.sessionId) {
            Text(item.session.name).ui(13, .semibold).foregroundStyle(t.text.color)
            Text(model.caption(for: item).text).ui(12.5).foregroundStyle(t.text2.color)
        } else {
            Text("No session is working on this file.").ui(12.5).foregroundStyle(t.text3.color)
        }
    }

    private var onThisFile: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel("On this file").padding(.top, 12)
            if let c = model.fileClaims.claim(for: path), let item = model.item(c.sessionId) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(AgentMark(agent: item.session.agent, account: item.account).fill.color).frame(width: 12, height: 12)
                    Text("\(item.account ?? item.session.agent.displayName) · editing now").ui(12.5).foregroundStyle(t.text.color)
                }
            }
            ForEach(history.prefix(3), id: \.self) { h in Text(h).ui(12).foregroundStyle(t.text2.color).lineLimit(1) }
            if state.isDirty(path) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(t.text3.color).frame(width: 12, height: 12)
                    Text("You · unsaved").ui(12.5).foregroundStyle(t.text.color)
                }
            }
        }
    }

    private func loadHistory() {
        let p = path
        DispatchQueue.global(qos: .utility).async {
            guard let root = GitDiff.repoRoot(for: p) else { return }
            let (_, out) = Foundations.run(GitDiff.git, ["-C", root, "log", "-n", "12", "--format=%s · %ar", "--", p], timeout: 5)
            let lines = out.split(separator: "\n").map(String.init)
            DispatchQueue.main.async { history = lines }
        }
    }
}

// MARK: - Ask an agent

private struct AskAgentSheet: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let request: EditorState.AskRequest
    var close: () -> Void
    @State private var target: String?
    @State private var question = ""

    var body: some View {
        let agents = model.items.filter { $0.liveAgent != nil && $0.session.agent.isAgent }
        let claimer = model.fileClaims.claim(for: request.path)?.sessionId
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask an agent about \((request.path as NSString).lastPathComponent):\(request.from)–\(request.to)").ui(15, .semibold).foregroundStyle(t.text.color)
            FieldMenu(title: model.item(target ?? claimer ?? agents.first?.id ?? "")?.session.name ?? "Pick a session") {
                ForEach(agents) { a in Button(a.session.name) { target = a.id } }
            }
            TextField("Question", text: $question, axis: .vertical).textFieldStyle(.plain).ui(13.5).lineLimit(2...6)
                .padding(8).background(RoundedRectangle(cornerRadius: Radius.field).fill(t.card.color))
            HStack {
                Spacer()
                RoofButton("Cancel", action: close).keyboardShortcut(.cancelAction)
                RoofButton("Send", .primary) {
                    guard let id = target ?? claimer ?? agents.first?.id, let item = model.item(id), let agent = item.liveAgent else { return }
                    let text = question + "\n@\(request.path):\(request.from)-\(request.to)"
                    let r = model.runtime
                    DispatchQueue.global().async { try? r.submit(agent, text: text) }
                    close()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || agents.isEmpty)
            }
        }
        .padding(20).frame(width: 480)
        .background(t.window.color)
        .onAppear { question = request.text.isEmpty ? "" : "" }
    }
}

/// Toolbar right side in the Editor: ▶ Run ⌘R · Debug ⇧⌘R · interpreter.
struct RunControls: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    var body: some View {
        let path = win.viewerPath ?? ""
        let cfg = FileKind.of(path) == .text ? RunConfig.detect(file: path, repoRoot: GitDiff.repoRoot(for: path) ?? (path as NSString).deletingLastPathComponent) : nil
        if let cfg {
            HStack(spacing: 6) {
                Button { NotificationCenter.default.post(name: .runFile, object: [win.id]) } label: {
                    Text("▶ Run ⌘R").ui(12.5, .semibold).foregroundStyle(AgentMark.ink.color)
                        .padding(.vertical, 5).padding(.horizontal, 11)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.statusColor(.done).color))
                }.buttonStyle(.plain)
                Button { NotificationCenter.default.post(name: .runFile, object: [win.id, "debug"]) } label: {
                    Text("Debug ⇧⌘R").ui(12.5, .semibold).foregroundStyle(t.text.color)
                        .padding(.vertical, 5).padding(.horizontal, 11)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.surface.color))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separatorStrong.color))
                }.buttonStyle(.plain).disabled(cfg.debug == nil)
                Text(cfg.label).ui(12, mono: true).foregroundStyle(t.text2.color)
                    .padding(.vertical, 5).padding(.horizontal, 9)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.control.color))
            }
        }
    }
}
