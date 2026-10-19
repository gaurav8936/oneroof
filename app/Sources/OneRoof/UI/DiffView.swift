import AppKit
import SwiftUI
import OneRoofCore

/// Code review panel: the live diff of a repo since its last commit, in the centre viewer. Files on the
/// left, hunks on the right; each hunk can be reverted on its own or commented on, and the comment goes to the
/// session's agent when it is between turns (One Roof never types into a working agent).
struct DiffView: View {
    @ObservedObject var model: AppModel
    let repo: String
    let t: ThemeTokens
    @State private var snap: DiffSnapshot?
    @State private var selected: String?
    @State private var loading = false
    @State private var note: String?
    @State private var commenting: String?
    @State private var comment = ""
    @State private var confirmRevert: DiffHunk?
    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider().overlay(t.border.color)
            if let s = snap, let e = s.error {
                message("git could not read this repo: \(e)")
            } else if let s = snap, s.files.isEmpty {
                message("No changes since the last commit on \(s.branch).")
            } else if let s = snap {
                HSplitView {
                    fileList(s).frame(minWidth: 220, idealWidth: 280, maxWidth: 420)
                    hunks(s).frame(minWidth: 380)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { reload() }
        .confirmationDialog("Revert this hunk?", isPresented: Binding(get: { confirmRevert != nil }, set: { if !$0 { confirmRevert = nil } }),
                            presenting: confirmRevert) { h in
            Button("Revert", role: .destructive) { revert(h) }
            Button("Cancel", role: .cancel) {}
        } message: { h in
            Text("\(h.file) \(h.header.components(separatedBy: "@@").dropFirst().first.map { "@@\($0)@@" } ?? ""): the change is thrown away and cannot be undone from One Roof.")
        }
        .onReceive(tick) { _ in if commenting == nil { reload() } }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch").foregroundStyle(t.secondaryText.color)
            Text(snap?.branch ?? "…").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.text.color)
            if let s = snap {
                Text("\(s.files.count) files").font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                Text("+\(s.added)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Self.addInk)
                Text("−\(s.removed)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(Self.delInk)
            }
            if let note { Text(note).font(.system(size: 11)).foregroundStyle(t.secondaryText.color).lineLimit(1) }
            Spacer()
            if loading { ProgressView().controlSize(.small) }
            Button { reload() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).help("Refresh (also every 3 s)")
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(t.surface.color)
    }

    private func fileList(_ s: DiffSnapshot) -> some View {
        List(s.files, selection: $selected) { f in
            HStack(spacing: 6) {
                Text(Self.letter(f.change)).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Self.changeInk(f.change)).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text((f.path as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    Text((f.path as NSString).deletingLastPathComponent).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if f.added + f.removed > 0 {
                    Text("+\(f.added) −\(f.removed)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            .tag(f.path)
        }
    }

    @ViewBuilder private func hunks(_ s: DiffSnapshot) -> some View {
        let file = s.files.first { $0.path == selected } ?? s.files[0]
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(file.path).font(.system(size: 13, weight: .bold)).foregroundStyle(t.text.color)
                    if let o = file.oldPath { Text("from \(o)").font(.system(size: 11)).foregroundStyle(t.secondaryText.color) }
                    Spacer()
                    Button("Open file") { model.openInViewer(repo + "/" + file.path) }.controlSize(.small)
                }
                if file.hunks.isEmpty {
                    Text(file.change == .untracked ? "New file, not yet added to git." : file.change == .binary ? "Binary file changed." : "No text changes (mode or rename only).")
                        .font(.system(size: 12)).foregroundStyle(t.secondaryText.color)
                }
                ForEach(file.hunks) { h in hunkCard(h) }
            }
            .padding(14)
        }
    }

    private func hunkCard(_ h: DiffHunk) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(h.header).font(.system(size: 11, design: .monospaced)).foregroundStyle(t.secondaryText.color).lineLimit(1)
                Spacer()
                Button { commenting = h.id; comment = "" } label: { Label("Comment", systemImage: "text.bubble") }
                    .controlSize(.small).help("Send a review comment about this hunk to the session's agent")
                Button { confirmRevert = h } label: { Label("Revert", systemImage: "arrow.uturn.backward") }
                    .controlSize(.small).help("Undo this hunk (also its staged copy when that matches the file)")
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(t.surface.color)
            ForEach(Array(h.lines.enumerated()), id: \.offset) { _, l in lineRow(l) }
            if commenting == h.id { commentBox(h) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(t.border.color))
    }

    private func lineRow(_ l: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(l.oldNo.map(String.init) ?? "").frame(width: 40, alignment: .trailing)
            Text(l.newNo.map(String.init) ?? "").frame(width: 40, alignment: .trailing)
            Text(l.kind == .added ? " + " : l.kind == .removed ? " − " : "   ")
            Text(l.text.isEmpty ? " " : l.text).foregroundStyle(l.kind == .note ? t.secondaryText.color : t.text.color)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12, design: .monospaced))
        .foregroundStyle(t.secondaryText.color.opacity(0.7))
        .padding(.vertical, 1)
        .background(l.kind == .added ? Self.addInk.opacity(0.14) : l.kind == .removed ? Self.delInk.opacity(0.14) : .clear)
    }

    private func commentBox(_ h: DiffHunk) -> some View {
        let target = model.reviewTarget(repo: repo)
        return VStack(alignment: .leading, spacing: 6) {
            TextField("What should the agent change here?", text: $comment, axis: .vertical)
                .textFieldStyle(.roundedBorder).lineLimit(1...4)
            HStack {
                Text(target.map { "To \($0.session.name)" + ($0.status == .running ? " · busy, try when it is idle" : "") } ?? "No live agent session in this repo")
                    .font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                Spacer()
                Button("Cancel") { commenting = nil }
                Button("Send") {
                    note = model.sendReview(GitDiff.reviewMessage(comment, hunk: h), repo: repo)
                    commenting = nil
                }
                .disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty || target == nil || target?.status == .running)
            }
        }
        .padding(10)
        .background(t.surface.color)
    }

    private func message(_ s: String) -> some View {
        Text(s).font(.system(size: 13)).foregroundStyle(t.secondaryText.color).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() {
        guard !loading else { return }
        loading = true
        let r = repo
        DispatchQueue.global(qos: .userInitiated).async {
            let s = GitDiff.load(repo: r)
            DispatchQueue.main.async {
                if s != snap { snap = s }
                if let sel = selected, !s.files.contains(where: { $0.path == sel }) { selected = nil }
                if selected == nil { selected = s.files.first?.path }
                loading = false
            }
        }
    }

    private func revert(_ h: DiffHunk) {
        let r = repo
        DispatchQueue.global(qos: .userInitiated).async {
            let err = GitDiff.revert(h, repo: r)
            DispatchQueue.main.async { note = err.map { "Revert failed: \($0)" } ?? "Reverted a hunk in \(h.file)"; reload() }
        }
    }

    static let addInk = Color(red: 0.16, green: 0.62, blue: 0.36)
    static let delInk = Color(red: 0.84, green: 0.27, blue: 0.27)
    static func letter(_ c: FileDiff.Change) -> String {
        switch c { case .modified: "M"; case .added: "A"; case .deleted: "D"; case .renamed: "R"; case .binary: "B"; case .untracked: "U" }
    }
    static func changeInk(_ c: FileDiff.Change) -> Color {
        switch c { case .added, .untracked: addInk; case .deleted: delInk; case .renamed: .purple; default: .orange }
    }
}
