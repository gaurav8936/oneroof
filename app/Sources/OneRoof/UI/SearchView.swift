import AppKit
import SwiftUI
import OneRoofCore

/// Search in Workspace: text across the selected session's repo or every repo under ~/Projects, with
/// `git grep`. Results are grouped by file; a click opens the file in the viewer at that line.
struct SearchView: View {
    @ObservedObject var model: AppModel
    let t: ThemeTokens
    @State private var query = ""
    @State private var wholeWorkspace = true
    @State private var caseSensitive = false
    @State private var hits: [SearchHit] = []
    @State private var searching = false
    @State private var searched = ""
    @State private var generation = 0
    @FocusState private var focused: Bool

    private var repoOfSelection: String? {
        model.selected.flatMap { GitDiff.repoRoot(for: $0.session.repoPath) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(t.secondaryText.color)
                TextField("Search text in \(wholeWorkspace ? "every repo under ~/Projects" : "this session's repo")", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 14)).focused($focused)
                    .onSubmit { run() }
                if searching { ProgressView().controlSize(.small) }
                Picker("", selection: $wholeWorkspace) {
                    Text("Workspace").tag(true)
                    Text("This repo").tag(false)
                }
                .pickerStyle(.segmented).fixedSize().disabled(repoOfSelection == nil && !wholeWorkspace)
                Toggle("Aa", isOn: $caseSensitive).toggleStyle(.button).help("Match case")
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(t.surface.color)
            Divider().overlay(t.border.color)
            results
        }
        .onAppear {
            focused = true
            if repoOfSelection == nil { wholeWorkspace = true }
            if let s = model.searchSeed { model.searchSeed = nil; query = s; run() }
        }
        .onChange(of: query) { _, _ in debounce() }
        .onChange(of: wholeWorkspace) { _, _ in run() }
        .onChange(of: caseSensitive) { _, _ in run() }
    }

    @ViewBuilder private var results: some View {
        if searched.isEmpty {
            hint("Type at least two characters. Searches tracked and untracked files; .gitignore'd files and binaries are skipped.")
        } else if hits.isEmpty && !searching {
            hint("No matches for “\(searched)”.")
        } else {
            let groups = Dictionary(grouping: hits, by: \.path)
            let order = hits.map(\.path).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("\(hits.count)\(hits.count >= 500 ? "+" : "") matches in \(order.count) files")
                        .font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                    ForEach(order, id: \.self) { path in fileGroup(path, groups[path] ?? []) }
                }
                .padding(14)
            }
        }
    }

    private func fileGroup(_ path: String, _ hs: [SearchHit]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: FileKind.of(path).symbol).font(.system(size: 11)).foregroundStyle(t.secondaryText.color)
                Text((path as NSString).lastPathComponent).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(t.text.color)
                Text(path.replacingOccurrences(of: Workspace.projectsRoot + "/", with: "")).font(.system(size: 10.5))
                    .foregroundStyle(t.secondaryText.color).lineLimit(1).truncationMode(.middle)
            }
            ForEach(hs) { h in
                Button { model.openInViewer(h.path, line: h.line) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(h.line)").font(.system(size: 11, design: .monospaced)).foregroundStyle(t.secondaryText.color)
                            .frame(width: 44, alignment: .trailing)
                        highlighted(h.text).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The match in bold accent colour.
    private func highlighted(_ text: String) -> Text {
        let opts: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        guard !searched.isEmpty, let r = text.range(of: searched, options: opts) else { return Text(text).foregroundColor(t.text.color) }
        return Text(text[..<r.lowerBound]).foregroundColor(t.text.color)
            + Text(text[r]).foregroundColor(t.accent.color).bold()
            + Text(text[r.upperBound...]).foregroundColor(t.text.color)
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 12.5)).foregroundStyle(t.secondaryText.color).multilineTextAlignment(.center)
            .frame(maxWidth: 460).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func debounce() {
        generation += 1
        let g = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { if g == generation { run() } }
    }

    private func run() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { hits = []; searched = ""; return }
        generation += 1
        let g = generation
        let repos = wholeWorkspace ? WorkspaceSearch.repos() : repoOfSelection.map { [$0] } ?? WorkspaceSearch.repos()
        let cs = caseSensitive
        searching = true
        DispatchQueue.global(qos: .userInitiated).async {
            let r = WorkspaceSearch.search(q, repos: repos, caseSensitive: cs)
            DispatchQueue.main.async {
                guard g == generation else { return }
                hits = r; searched = q; searching = false
            }
        }
    }
}
