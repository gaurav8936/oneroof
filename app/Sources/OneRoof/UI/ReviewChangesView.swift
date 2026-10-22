import AppKit
import SwiftUI
import OneRoofCore

/// Review changes (⌥⌘R): the session's uncommitted diff — files on the left, the diff with "What {Agent} did" in
/// the middle, Checks · Artifacts · Commit on the right (Plan theme). Click a line number to comment; the comment goes
/// to the agent's next turn or into the session's notes. Commit never pushes.
struct ReviewChangesView: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @State private var snap: DiffSnapshot?
    @State private var file: String?
    @State private var commentLine: String?
    @State private var comment = ""
    @State private var sent: [String: String] = [:]
    @State private var sideBySide = false
    @State private var checks: [ReviewCheck] = []
    @State private var message = ""
    @State private var messageTouched = false
    @State private var moveTicket = true
    @State private var askHandoff = true
    @State private var status: String?
    @State private var confirmRevert: DiffHunk?
    @State private var hoverHunk: String?
    private let tick = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    private var repo: String { win.reviewRepo ?? model.selected?.session.repoPath ?? Workspace.projectsRoot }
    private var session: BoardItem? { model.reviewTarget(repo: repo) ?? model.selected }

    var body: some View {
        VStack(spacing: 0) {
            breadcrumb
            Hairline()
            if GitDiff.repoRoot(for: repo) == nil {
                note("\((repo as NSString).abbreviatingWithTildeInPath) is not in a git repo, so there is nothing to review. Pick a session that works in a repo.")
            } else if let s = snap, let e = s.error {
                note("git could not read this repo: " + (e.split(separator: "\n").first.map(String.init) ?? e))
            } else if let s = snap, s.files.isEmpty {
                note("No changes since the last commit on \(s.branch).")
            } else if let s = snap {
                HStack(spacing: 0) {
                    fileList(s).frame(width: 260)
                    Rectangle().fill(t.separator.color).frame(width: 1)
                    diffColumn(s).frame(maxWidth: .infinity)
                    checksColumn(s).frame(width: 340).themed(model.themes.plan, scale: win.textScale)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(t.window.color)
        .onAppear(perform: reload)
        .onChange(of: win.reviewRepo) { _, _ in snap = nil; file = nil; reload() }
        .onReceive(tick) { _ in if commentLine == nil { reload() } }
        .confirmationDialog("Revert this hunk?", isPresented: Binding(get: { confirmRevert != nil }, set: { if !$0 { confirmRevert = nil } }),
                            presenting: confirmRevert) { h in
            Button("Revert", role: .destructive) { revert(h) }
            Button("Cancel", role: .cancel) {}
        } message: { h in Text("\(h.file): the change is thrown away and cannot be undone from One Roof.") }
    }

    // MARK: Header

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Text(win.name + " ›").ui(13).foregroundStyle(t.text2.color)
            if let s = session { Text(s.session.name + " ›").ui(13).foregroundStyle(t.text2.color) }
            Text("Review changes").ui(14, .semibold).foregroundStyle(t.text.color)
            if let s = snap { Text("· \(Workspace.repoLabel(for: s.repo)) on \(s.branch)").ui(12.5).foregroundStyle(t.text3.color) }
            Spacer()
            Button { reload() } label: { Text("↻ Refresh").ui(12.5).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
            Toggle("Side by side", isOn: $sideBySide).toggleStyle(.switch).controlSize(.mini).ui(12)
                .keyboardShortcut("d", modifiers: [.command, .option])
            Button { model.show(.workspace, in: win) } label: { Text("Back to terminal ⌘L").ui(12.5).foregroundStyle(t.text2.color) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).frame(height: 44)
    }

    private func note(_ s: String) -> some View {
        VStack { Spacer(); Text(s).ui(14).foregroundStyle(t.text2.color); Spacer() }.frame(maxWidth: .infinity)
    }

    // MARK: Files

    private func fileList(_ s: DiffSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(s.files.count) FILES · +\(s.added) −\(s.removed)").ui(11, .semibold).tracking(0.5).foregroundStyle(t.text3.color)
                .padding(.horizontal, 16).padding(.vertical, 12)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(s.files) { f in
                        let on = f.path == currentFile(s)?.path
                        let comments = sent.keys.filter { $0.hasPrefix(f.path + ":") }.count
                        Button { file = f.path } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text((f.path as NSString).lastPathComponent).ui(12.5, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                                HStack(spacing: 6) {
                                    Text("+\(f.added)").ui(11.5, mono: true).foregroundStyle(t.diffAddText.color)
                                    Text("−\(f.removed)").ui(11.5, mono: true).foregroundStyle(t.diffDelText.color)
                                    if comments > 0 { Text("\(comments) comment\(comments == 1 ? "" : "s")").ui(11.5, mono: true).foregroundStyle(t.text3.color) }
                                    if f.change == .added || f.change == .untracked { Text("new").ui(11.5, mono: true).foregroundStyle(t.text3.color) }
                                    if f.change == .deleted { Text("deleted").ui(11.5, mono: true).foregroundStyle(t.text3.color) }
                                }
                            }
                            .padding(.vertical, 8).padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(f.path)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .background(t.sidebar.color)
    }

    private func currentFile(_ s: DiffSnapshot) -> FileDiff? { s.files.first { $0.path == file } ?? s.files.first }

    // MARK: Diff

    private func diffColumn(_ s: DiffSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                whatItDid.padding(20)
                Hairline()
                if let f = currentFile(s) {
                    HStack {
                        Text(f.path).ui(12, mono: true).foregroundStyle(t.text2.color)
                        Spacer()
                        if f.change != .deleted {
                            Button { model.openInViewer(s.repo + "/" + f.path) } label: { Text("Open file").ui(12).foregroundStyle(t.accentText.color) }
                                .buttonStyle(.plain)
                        }
                    }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(t.toolbar.color)
                    Hairline()
                    if f.hunks.isEmpty { Text(f.change == .binary ? "Binary file" : "No text changes").ui(13).foregroundStyle(t.text3.color).padding(20) }
                    ForEach(f.hunks) { h in hunk(h) }
                }
            }
        }
    }

    private var whatItDid: some View {
        let item = session
        let agentName = item.map { $0.account ?? $0.session.agent.displayName } ?? "the agent"
        let summary = item.flatMap { i in model.feed.first { $0.sessionId == i.id && $0.kind == "done" }?.text }
            ?? item.map { model.caption(for: $0).text } ?? "No session works in this repo; these are the uncommitted changes."
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let item { AgentBadge(item: item, size: 20, status: false) }
                Text("What \(agentName) did").ui(13.5, .semibold).foregroundStyle(t.text.color)
                Text("from the session summary").ui(12).foregroundStyle(t.text3.color)
            }
            Text(summary).ui(14).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hunk(_ h: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(h.header).ui(11.5, mono: true).foregroundStyle(t.text3.color).lineLimit(1)
                Spacer()
                if hoverHunk == h.id {
                    Button { confirmRevert = h } label: { Text("Revert hunk").ui(11.5).foregroundStyle(t.needsText.color) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 4)
            if sideBySide { sideBySideRows(h) } else {
                ForEach(Array(h.lines.enumerated()), id: \.offset) { _, l in
                    line(l, file: h.file)
                    if let n = l.newNo ?? l.oldNo, commentLine == "\(h.file):\(n)" { commentBox(file: h.file, line: n, hunk: h) }
                    if let n = l.newNo, let r = sent["\(h.file):\(n)"] { sentNote(r) }
                }
            }
        }
        .onHover { hoverHunk = $0 ? h.id : (hoverHunk == h.id ? nil : hoverHunk) }
    }

    private func line(_ l: DiffLine, file: String) -> some View {
        let (bg, sign, ink): (Color, String, Color) = {
            switch l.kind {
            case .added: return (t.diffAddFill.color, "+", t.diffAddText.color)
            case .removed: return (t.diffDelFill.color, "−", t.diffDelText.color)
            case .note: return (.clear, " ", t.text3.color)
            case .context: return (.clear, " ", t.text3.color)
            }
        }()
        return HStack(spacing: 0) {
            Button { if let n = l.newNo ?? l.oldNo { commentLine = "\(file):\(n)"; comment = "" } } label: {
                HStack(spacing: 0) {
                    Text(l.oldNo.map(String.init) ?? "").frame(width: 44, alignment: .trailing)
                    Text(l.newNo.map(String.init) ?? "").frame(width: 44, alignment: .trailing)
                }
                .ui(12, mono: true).foregroundStyle(t.text3.color)
            }
            .buttonStyle(.plain).help("Comment on this line")
            Text(sign).ui(12.5, .semibold, mono: true).foregroundStyle(ink).frame(width: 24)
            Text(l.text).ui(12.5, mono: true).foregroundStyle(t.text.color).lineLimit(1).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .background(bg)
    }

    private func sideBySideRows(_ h: DiffHunk) -> some View {
        var rows: [(DiffLine?, DiffLine?)] = []
        var dels: [DiffLine] = [], adds: [DiffLine] = []
        func flush() {
            for i in 0..<max(dels.count, adds.count) { rows.append((i < dels.count ? dels[i] : nil, i < adds.count ? adds[i] : nil)) }
            dels = []; adds = []
        }
        for l in h.lines {
            switch l.kind {
            case .removed: dels.append(l)
            case .added: adds.append(l)
            default: flush(); rows.append((l, l))
            }
        }
        flush()
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 0) {
                    half(r.0, old: true).frame(maxWidth: .infinity)
                    Rectangle().fill(t.separator.color).frame(width: 1)
                    half(r.1, old: false).frame(maxWidth: .infinity)
                }
                .frame(height: 22)
            }
        }
    }

    private func half(_ l: DiffLine?, old: Bool) -> some View {
        HStack(spacing: 6) {
            Text((old ? l?.oldNo : l?.newNo).map(String.init) ?? "").ui(12, mono: true).foregroundStyle(t.text3.color).frame(width: 40, alignment: .trailing)
            Text(l?.text ?? "").ui(12.5, mono: true).foregroundStyle(t.text.color).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
        .background(l?.kind == .added && !old ? t.diffAddFill.color : l?.kind == .removed && old ? t.diffDelFill.color : .clear)
    }

    private func commentBox(file: String, line: Int, hunk: DiffHunk) -> some View {
        let agentName = session.map { $0.account ?? $0.session.agent.displayName } ?? "agent"
        return VStack(alignment: .leading, spacing: 8) {
            Text("You · on line \(line)").ui(12.5, .semibold).foregroundStyle(t.text.color)
            TextField("Comment", text: $comment, axis: .vertical).textFieldStyle(.plain).ui(13.5).lineLimit(1...5)
            HStack(spacing: 8) {
                RoofButton("Send to \(agentName)", .primary) { send(file: file, line: line, hunk: hunk) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty || session?.liveAgent == nil)
                RoofButton("Save as note") { saveNote(file: file, line: line) }
                Text("Sends only while the agent is idle; while it works, save it as a note.").ui(12).foregroundStyle(t.text3.color)
                Spacer()
                Button { commentLine = nil } label: { Text("✕").ui(12).foregroundStyle(t.text3.color) }.buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.accent.color.opacity(0.4)))
        .padding(.leading, 106).padding(.trailing, 20).padding(.vertical, 6)
        .transition(.opacity)
    }

    private func sentNote(_ s: String) -> some View {
        Text(s).ui(11.5).foregroundStyle(t.text3.color).padding(.leading, 112).padding(.vertical, 3)
    }

    // MARK: Checks · Artifacts · Commit

    private func checksColumn(_ s: DiffSnapshot) -> some View {
        ChecksColumn(model: model, snap: s, session: session, checks: checks, message: $message, moveTicket: $moveTicket,
                     askHandoff: $askHandoff, status: status, commit: commit, askToFix: askToFix)
            .onAppear { prefillMessage() }
    }

    private func prefillMessage() {
        guard !messageTouched else { return }
        let s = session?.session
        let ws = s?.workstream.map { "[\($0.lowercased())] " } ?? ""
        let key = s?.ticket.map { $0 + " · " } ?? ""
        let summary = session.map { model.caption(for: $0).text.replacingOccurrences(of: "Done · ", with: "") } ?? "changes"
        message = key + ws + summary
    }

    // MARK: Actions

    private func reload() {
        let r = repo
        guard GitDiff.repoRoot(for: r) != nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let root = GitDiff.repoRoot(for: r) ?? r
            let s = GitDiff.load(repo: root)
            DispatchQueue.main.async { if s != snap { snap = s } }
        }
        loadChecks()
    }

    /// Checks come from the session's own output (S08 §1.6): build and test results it printed, never invented.
    private func loadChecks() {
        guard let pane = session?.paneId else { checks = []; return }
        let r = model.runtime
        DispatchQueue.global(qos: .utility).async {
            let text = (try? r.read(pane: pane, lines: 600)) ?? ""
            let c = ReviewCheck.read(text)
            DispatchQueue.main.async { checks = c }
        }
    }

    private func send(file: String, line: Int, hunk: DiffHunk) {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let s = session else { return }
        let msg = "Review comment on \(file):\(line): \(text)"
        let r = model.sendReview(msg, repo: s.session.repoPath)
        model.store?.save(ReviewComment(sessionId: s.id, path: file, line: line, text: text, sentAt: Date()))
        sent["\(file):\(line)"] = "sent " + Date().formatted(date: .omitted, time: .shortened) + " · " + r
        commentLine = nil
    }

    private func saveNote(file: String, line: Int) {
        let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let s = session else { return }
        model.update(s) { $0.notes += ($0.notes.isEmpty ? "" : "\n") + "\(file):\(line) — \(text)" }
        model.store?.save(ReviewComment(sessionId: s.id, path: file, line: line, text: text, savedAsNote: true))
        sent["\(file):\(line)"] = "saved as a note"
        commentLine = nil
    }

    private func revert(_ h: DiffHunk) {
        guard let root = snap?.repo else { return }
        DispatchQueue.global().async {
            let err = GitDiff.revert(h, repo: root)
            DispatchQueue.main.async { status = err.map { "Revert failed: \($0)" } ?? "Hunk reverted."; reload() }
        }
    }

    private func commit() {
        guard let root = snap?.repo else { return }
        let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { status = "Write a commit message first."; return }
        let s = session
        let move = moveTicket, handoff = askHandoff
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Foundations.run(GitDiff.git, ["-C", root, "add", "-A"], timeout: 20)
            let (rc, out) = Foundations.run(GitDiff.git, ["-C", root, "commit", "-m", msg], timeout: 60)
            DispatchQueue.main.async {
                if rc == 0 {
                    status = "Committed. Nothing was pushed."
                    if let s, move, s.session.ticket != nil { model.moveTickets(of: s, to: "In Review") }
                    if let s, handoff { model.askForHandoff(s) }
                } else {
                    status = "git commit failed: " + out.trimmingCharacters(in: .whitespacesAndNewlines).suffix(200)
                }
                reload()
            }
        }
    }

    private func askToFix(_ c: ReviewCheck) {
        guard let s = session, let agent = s.liveAgent else { return }
        let r = model.runtime
        let text = "The review check \"\(c.title)\" is not passing: \(c.detail). Please fix it."
        DispatchQueue.global().async { try? r.submit(agent, text: text) }
        status = "Asked \(s.session.name) to fix \(c.title)."
    }
}

/// One check from the session's output.
struct ReviewCheck: Identifiable, Equatable {
    enum Level { case ok, warn, fail }
    var id: String { title }
    var title: String
    var detail: String
    var level: Level

    /// Build and test results in an agent's terminal: swift/npm/pytest summaries.
    static func read(_ text: String) -> [ReviewCheck] {
        var out: [ReviewCheck] = []
        let lines = text.split(separator: "\n").map(String.init)
        if let l = lines.last(where: { $0.contains("Build complete!") }) {
            let time = l.range(of: #"\(([\d.]+)s\)"#, options: .regularExpression).map { String(l[$0]).trimmingCharacters(in: CharacterSet(charactersIn: "()")) } ?? ""
            out.append(ReviewCheck(title: "swift build", detail: time, level: .ok))
        } else if lines.contains(where: { $0.contains("error: ") && $0.contains(".swift:") }) {
            out.append(ReviewCheck(title: "swift build", detail: "compile errors", level: .fail))
        }
        if let c = CaptionEngine.testCounts(in: text) {
            out.append(ReviewCheck(title: "tests", detail: "\(c.passed) of \(c.total)", level: c.passed == c.total ? .ok : .fail))
        }
        if let l = lines.last(where: { $0.range(of: #"\d+ failed"#, options: .regularExpression) != nil }) {
            out.append(ReviewCheck(title: "failing tests", detail: l.trimmingCharacters(in: .whitespaces), level: .fail))
        }
        return out
    }
}

/// The right column of Review changes (Plan theme).
private struct ChecksColumn: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let snap: DiffSnapshot
    let session: BoardItem?
    let checks: [ReviewCheck]
    @Binding var message: String
    @Binding var moveTicket: Bool
    @Binding var askHandoff: Bool
    let status: String?
    var commit: () -> Void
    var askToFix: (ReviewCheck) -> Void

    var body: some View {
        let agentName = session.map { $0.account ?? $0.session.agent.displayName } ?? "the agent"
        let images = snap.files.filter { ["png", "jpg", "jpeg"].contains(($0.path as NSString).pathExtension.lowercased()) && $0.change != .deleted }
        VStack(alignment: .leading, spacing: 10) {
            Text("Checks").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
            if checks.isEmpty { Text("No build or test results in the session's output yet.").ui(12.5).foregroundStyle(t.text3.color) }
            ForEach(checks) { c in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(c.level == .ok ? "✓" : c.level == .warn ? "!" : "✕").ui(13, .semibold)
                        .foregroundStyle((c.level == .ok ? t.statusDone : c.level == .warn ? t.now : t.needsText).color)
                    Text(c.title + (c.detail.isEmpty ? "" : " · " + c.detail)).ui(13).foregroundStyle(t.text.color).lineLimit(2)
                }
            }
            if !images.isEmpty {
                MicroLabel("Artifacts").padding(.top, 8)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(images.prefix(6)) { f in
                        let p = snap.repo + "/" + f.path
                        Button { model.openInViewer(p) } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let img = NSImage(contentsOfFile: p) { Image(nsImage: img).resizable().scaledToFill() }
                                else { t.card.color }
                                Text((f.path as NSString).lastPathComponent).ui(11).foregroundStyle(t.text.color).padding(6)
                                    .background(t.card.color.opacity(0.85))
                            }
                            .frame(height: 74).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            MicroLabel("Commit")
            TextEditor(text: $message).ui(12, mono: true).scrollContentBackground(.hidden)
                .padding(8).frame(height: 64)
                .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
                .foregroundStyle(t.text.color)
            if let keys = session?.session.allTickets.map(\.key), !keys.isEmpty {
                Toggle("Move \(keys.joined(separator: ", ")) to In Review", isOn: $moveTicket).ui(12.5)
            }
            Toggle("Ask \(agentName) to write the handoff", isOn: $askHandoff).ui(12.5).disabled(session?.liveAgent == nil)
            HStack(spacing: 8) {
                RoofButton("Commit ⌘↩", .primary, action: commit).keyboardShortcut(.return, modifiers: .command)
                if let bad = checks.first(where: { $0.level != .ok }) { RoofButton("Ask to fix \(bad.title)") { askToFix(bad) } }
            }
            if let status { Text(status).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
    }
}
