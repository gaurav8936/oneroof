import SwiftUI
import OneRoofCore

enum V2PlanTab: String, CaseIterable { case plan = "Plan", ticket = "Ticket", notes = "Notes", files = "Files", usage = "Usage" }

struct PlanFacts {
    var status: SessionStatus; var statusText: String; var title: String
    var agent: String; var repo: String; var startFolder: String; var oneMemory: Bool; var roofdId: String; var launched: String
    var stepReview: (title: String, asked: String, happened: String)?
    var project: String; var doneWhen: String; var stickers: [String]; var related: [String]
}

/// Replaces PlanPanelView: text tabs Plan · Ticket · Notes · Files · Usage (A3).
struct PlanInspector<Ticket: View, Notes: View, Files: View, Usage: View>: View {
    var facts: PlanFacts
    var tokens: V2Planes
    @State var tab: V2PlanTab = .plan
    var onStop: () -> Void
    @ViewBuilder var ticket: () -> Ticket
    @ViewBuilder var notes: () -> Notes
    @ViewBuilder var files: () -> Files
    @ViewBuilder var usage: () -> Usage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $tab) { ForEach(V2PlanTab.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    switch tab {
                    case .plan: plan
                    case .ticket: ticket()
                    case .notes: notes()
                    case .files: files()
                    case .usage: usage()
                    }
                }
            }
        }
        .font(.system(size: 12)).padding(12)
    }

    @ViewBuilder private var plan: some View {
        HStack {
            Label(facts.statusText, systemImage: "circle.fill").labelStyle(.titleAndIcon).foregroundStyle(StatusPalette.dot(facts.status).color).fontWeight(.semibold)
            Spacer()
            Button("Stop", action: onStop).controlSize(.small)
            Menu { V2SessionContextMenu() } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }
        Text(facts.title).font(.system(size: 15, weight: .bold))
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            row("Agent", facts.agent); row("Repo", facts.repo)
            GridRow { Text("Start folder").foregroundStyle(tokens.text2); Text(facts.startFolder + (facts.oneMemory ? " · ✓ one memory" : "")).foregroundStyle(facts.oneMemory ? Color(.systemGreen) : tokens.text) }
            row("roofd", facts.roofdId); row("Launched", facts.launched)
        }.font(.system(size: 11))
        if let r = facts.stepReview {
            VStack(alignment: .leading, spacing: 3) {
                HStack { Text("STEP REVIEW · latest").font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.text2); Spacer(); Toggle("", isOn: .constant(true)).toggleStyle(.switch).controlSize(.mini).labelsHidden() }
                Text(r.title).fontWeight(.semibold)
                section("WHAT WAS ASKED"); Text(r.asked)
                section("WHAT HAPPENED"); Text(r.happened)
                Text("By Claude (haiku), one call per step").font(.system(size: 9.5)).foregroundStyle(tokens.text3)
            }.padding(10).background(RoundedRectangle(cornerRadius: 9).fill(tokens.control))
        }
        section("PROJECT")
        HStack { Text(facts.project).font(.system(size: 12, design: .monospaced)); Spacer(); Text("Linear ▾") }.padding(7).background(RoundedRectangle(cornerRadius: 7).fill(tokens.control))
        section("OBJECTIVE · DONE WHEN")
        Text(facts.doneWhen).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 7).fill(tokens.control))
        section("STICKERS")
        FlowRow(items: facts.stickers + ["+ New"]) { Text($0).font(.system(size: 10.5)).padding(.horizontal, 8).padding(.vertical, 1).overlay(Capsule().stroke(tokens.separatorStrong)) }
        if !facts.related.isEmpty { Text("Related in Learn · " + facts.related.joined(separator: " · ")).font(.system(size: 11)).foregroundStyle(tokens.text2) }
    }

    private func row(_ k: String, _ v: String) -> some View { GridRow { Text(k).foregroundStyle(tokens.text2); Text(v) } }
    private func section(_ t: String) -> some View { Text(t).font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.text3) }
}

/// Usage tab content (A3.5).
struct UsageTab: View {
    var memory: String, cpu: String, processes: Int, peak: String, guardUsed: Double, guardText: String
    var tree: [(name: String, depth: Int, pid: Int, cpu: String, mem: String)]
    var tokens: V2Planes
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { stat("MEMORY", memory); stat("CPU", cpu); stat("PROCESSES", "\(processes)") }
            HStack { Text("Memory, last 10 minutes"); Spacer(); Text("peak \(peak)") }.font(.system(size: 10.5)).foregroundStyle(tokens.text2)
            Text("MEMORY GUARD").font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.text3)
            ProgressView(value: guardUsed)
            Text(guardText).font(.system(size: 10.5)).foregroundStyle(tokens.text2)
            Text("PROCESSES").font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.text3)
            ForEach(Array(tree.enumerated()), id: \.offset) { _, p in
                HStack { Text(p.name).padding(.leading, CGFloat(p.depth) * 8); Spacer(); Text("\(p.pid)").foregroundStyle(tokens.text3); Text(p.cpu).frame(width: 36, alignment: .trailing); Text(p.mem).bold().frame(width: 52, alignment: .trailing) }
                    .font(.system(size: 10.5, design: .monospaced))
            }
        }
    }
    private func stat(_ k: String, _ v: String) -> some View { VStack(alignment: .leading) { Text(k).font(.system(size: 9.5, weight: .bold)).foregroundStyle(tokens.text3); Text(v).font(.system(size: 16, weight: .bold)) }.frame(maxWidth: .infinity, alignment: .leading) }
}

/// Wrapping row of chips.
struct FlowRow<Content: View>: View {
    var items: [String]; @ViewBuilder var content: (String) -> Content
    var body: some View {
        // macOS 14: use Layout for real wrapping; a simple HStack wrap is enough for 8 stickers.
        ViewThatFits { HStack(spacing: 4) { ForEach(items, id: \.self, content: content) }
            VStack(alignment: .leading, spacing: 4) { HStack(spacing: 4) { ForEach(items.prefix(4), id: \.self, content: content) }; HStack(spacing: 4) { ForEach(items.dropFirst(4), id: \.self, content: content) } } }
    }
}
