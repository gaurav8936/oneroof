import SwiftUI
import OneRoofCore

enum SessionTab: String, CaseIterable { case terminal = "Terminal", files = "Files", changes = "Changes", subagents = "Subagents" }

/// Centre of a session: tabs + terminal card. `terminal` is the existing libghostty view (unchanged).
struct SessionCentre<Terminal: View, Files: View, Changes: View, Subagents: View>: View {
    var summary: V2SessionSummary
    var tokens: V2Planes
    var changesCount: Int
    var subagentsCount: Int
    var showTabs: Bool
    @State private var tab: SessionTab = .terminal
    @ViewBuilder var terminal: () -> Terminal
    @ViewBuilder var files: () -> Files
    @ViewBuilder var changes: () -> Changes
    @ViewBuilder var subagents: () -> Subagents

    var body: some View {
        VStack(spacing: 8) {
            if showTabs {
                HStack(spacing: 2) {
                    tabButton(.terminal, "Terminal"); tabButton(.files, "Files")
                    tabButton(.changes, "Changes \(changesCount)"); tabButton(.subagents, "Subagents \(subagentsCount)")
                    Button("+ Terminal") {}.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(tokens.text2).padding(.horizontal, 10)
                    Spacer()
                    Text("Split ⌘D · Raw ⌘R · Wrap").font(.system(size: 11)).foregroundStyle(tokens.text2)
                }
            }
            switch tab {
            case .terminal: TerminalCard(summary: summary, tokens: tokens, terminal: terminal)
            case .files: files()
            case .changes: changes()
            case .subagents: subagents()
            }
        }
        .padding(10)
    }

    private func tabButton(_ t: SessionTab, _ label: String) -> some View {
        Button(label) { tab = t }.buttonStyle(.plain).font(.system(size: 11.5, weight: tab == t ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(tab == t ? tokens.surface : .clear))
    }
}

/// The terminal card: You asked · Right now · Steps · chapters · live terminal · composer.
struct TerminalCard<Terminal: View>: View {
    var summary: V2SessionSummary
    var tokens: V2Planes
    @ViewBuilder var terminal: () -> Terminal
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    V2Caption("YOU ASKED · \(summary.askedAt)", tokens)
                    Text(summary.asked).font(.system(size: 13)).lineLimit(2)
                    V2Caption("RIGHT NOW", tokens).padding(.top, 6)
                    Text(summary.rightNow).font(.system(size: 12)).foregroundStyle(tokens.accentText).lineLimit(1)
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    V2Caption("STEPS · \(summary.steps.filter(\.done).count) OF \(summary.steps.count)", tokens)
                    ForEach(summary.steps) { s in
                        HStack(spacing: 6) {
                            Image(systemName: s.done ? "circle.fill" : "circle").font(.system(size: 8)).foregroundStyle(s.done ? Color(.systemGreen) : tokens.accentText)
                            Text(s.title).font(.system(size: 11)).lineLimit(1)
                        }
                    }
                }.frame(width: 250, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.vertical, 12).background(tokens.terminalHeader)
            ForEach(summary.steps.filter(\.done)) { s in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").foregroundStyle(Color(.systemGreen))
                    Text("\(s.id) · \(s.title)").fontWeight(.semibold)
                    Text(s.summary).foregroundStyle(tokens.terminalDim).lineLimit(1)
                    Spacer()
                    Text("\(s.calls) calls · \(s.age) ▸").foregroundStyle(tokens.terminalDim)
                }
                .font(.system(size: 11.5)).padding(.horizontal, 16).padding(.vertical, 6)
                .overlay(alignment: .top) { Rectangle().fill(.gray.opacity(0.25)).frame(height: 1) }
            }
            terminal().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(tokens.terminalText)
        .background(tokens.terminal)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 8)
    }
}

struct V2Caption: View {
    var text: String; var tokens: V2Planes
    init(_ t: String, _ k: V2Planes) { text = t; tokens = k }
    var body: some View { Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(tokens.terminalDim) }
}

/// Changes tab (A2.2): list of files with +/− and the selected diff.
struct ChangesView: View {
    struct File: Identifiable { var id: String { path }; var path: String; var added: Int; var removed: Int }
    var files: [File]; var tokens: V2Planes
    @State private var selected: String?
    var diff: (String) -> AnyView
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack { Text("\(files.count) changed files").bold(); Spacer(); Text("+\(files.map(\.added).reduce(0, +)) −\(files.map(\.removed).reduce(0, +))").foregroundStyle(tokens.text2) }.padding(10)
                List(files, selection: $selected) { f in
                    HStack { Text((f.path as NSString).lastPathComponent).fontWeight(.semibold); Spacer()
                        Text("+\(f.added)").foregroundStyle(Color(.systemGreen)); Text("−\(f.removed)").foregroundStyle(Color(.systemRed)) }
                        .font(.system(size: 11.5, design: .monospaced))
                }
                HStack { Button("Ask the agent to commit") {}.buttonStyle(.borderedProminent); Button("Discard…") {} }.padding(10)
            }.frame(width: 300)
            Divider()
            diff(selected ?? files.first?.path ?? "")
        }
        .background(tokens.surface).clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Subagents tab (A2.3).
struct SubagentsTab: View {
    struct Sub: Identifiable { var id: String; var title: String; var model: String; var tokensUsed: String; var age: String; var asked: String; var now: String; var running: Bool }
    var subs: [Sub]; var touched: [(String, String)]; var tokens: V2Planes
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 10) {
                ForEach(subs) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Circle().fill(s.running ? tokens.accent : Color(.systemGreen)).frame(width: 7, height: 7); Text(s.title).bold(); Spacer(); Text("\(s.model) · \(s.tokensUsed) · \(s.age)").font(.system(size: 11)).foregroundStyle(tokens.text3) }
                        Text("Asked: ").bold() + Text(s.asked).foregroundColor(tokens.text2)
                        Text(s.running ? "Doing: " : "Done: ").bold() + Text(s.now)
                    }
                    .font(.system(size: 12)).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface))
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("FILES TOUCHED").font(.system(size: 10, weight: .semibold)).foregroundStyle(tokens.text3)
                ForEach(touched, id: \.0) { f in HStack { Text(f.0).font(.system(size: 11.5, design: .monospaced)); Spacer(); Text(f.1).foregroundStyle(tokens.text3) } }
                Text("Trace ▸ opens every call each subagent made.").foregroundStyle(tokens.text2).padding(.top, 10)
                Spacer()
            }
            .font(.system(size: 12)).padding(12).frame(width: 260).background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface))
        }
    }
}
