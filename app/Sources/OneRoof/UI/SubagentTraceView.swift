import SwiftUI
import OneRoofCore

/// Subagents (⇧⌘A): sessions with subagents on the left; on the right the selected session's trace — the parent
/// and each subagent as a timeline bar (depth with ├ └ │), and a detail card for the selected node: what it was asked,
/// what it is doing now, what it touched. Claude subagents are exact (transcript sidechains); others are "inferred".
struct SubagentTraceView: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @State private var session: String?
    @State private var node: String?
    @State private var minutes: Double = 14
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private func running(_ id: String) -> Int { (model.subagents[id] ?? []).filter { $0.ended == nil }.count }

    private var sessions: [BoardItem] {
        let withSubs: [BoardItem] = model.items.filter { !(model.subagents[$0.id] ?? []).isEmpty }
        return withSubs.sorted { running($0.id) > running($1.id) }
    }

    private var current: BoardItem? {
        let list = sessions
        let want = session ?? win.traceFocus
        return list.first { $0.id == want } ?? list.first
    }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 270)
            Rectangle().fill(t.separator.color).frame(width: 1)
            Group {
                if let s = current { trace(s) } else { empty }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(t.window.color)
        }
        .onReceive(timer) { tick = $0 }
    }

    // MARK: List

    private var list: some View {
        let running = model.subagents.values.joined().filter { $0.ended == nil }.count
        let inSessions = model.subagents.filter { $0.value.contains { $0.ended == nil } }.count
        return VStack(alignment: .leading, spacing: 4) {
            Text("Subagents").ui(22, .semibold).foregroundStyle(t.text.color).padding(.top, 18)
            Text("\(running) running in \(inSessions) session\(inSessions == 1 ? "" : "s")").ui(13).foregroundStyle(t.text2.color)
                .padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(sessions) { s in
                        let on = s.id == current?.id
                        Button { session = s.id; node = nil } label: {
                            HStack(alignment: .top, spacing: 8) {
                                AgentBadge(item: s, size: 22, status: false)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.session.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                                    Text(model.window(model.workspaceId(of: s))?.name ?? "").ui(11.5).foregroundStyle(t.text3.color)
                                }
                                Spacer()
                                Text("\(model.subagents[s.id]?.count ?? 0)").ui(12).foregroundStyle(t.text2.color)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .background(t.sidebar.color)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No subagents running").ui(20, .semibold).foregroundStyle(t.text.color)
            Text("When a Claude session starts subagents (the Task tool), their trace shows here. Codex, Kimi and Gemini children are inferred from herdr panes.")
                .ui(13).foregroundStyle(t.text2.color).multilineTextAlignment(.center).frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Trace

    private func trace(_ s: BoardItem) -> some View {
        let subs = model.subagents[s.id] ?? []
        let start = min(s.session.launchedAt ?? subs.map(\.started).min() ?? tick, subs.map(\.started).min() ?? tick)
        let span = max(minutes * 60, tick.timeIntervalSince(start))
        let tokens = subs.reduce(0) { $0 + $1.tokens }
        let sel = subs.first { $0.id == node } ?? subs.first { $0.ended == nil } ?? subs.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AgentBadge(item: s, size: 26, status: false)
                Text(s.session.name).ui(20, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text("\(model.window(model.workspaceId(of: s))?.name ?? "") · \(s.account ?? s.session.agent.displayName) · \(subs.count) subagents · \(SubagentCard.tokens(tokens)) tokens")
                    .ui(13).foregroundStyle(t.text2.color).lineLimit(1)
                Spacer()
                Text("0 ——— \(Int(span / 60)) min").ui(12, mono: true).foregroundStyle(t.text3.color)
            }
            .padding(.horizontal, 26).frame(height: 60)
            Hairline()
            GeometryReader { g in
                let barW = g.size.width - 330 - 52
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Text("AGENT").ui(11, .semibold).tracking(0.6).foregroundStyle(t.text3.color).frame(width: 330, alignment: .leading)
                            ZStack(alignment: .leading) {
                                ForEach(Array(stride(from: 0.0, through: span / 60, by: 2)), id: \.self) { m in
                                    Text("\(Int(m))m").ui(11, mono: true).foregroundStyle(t.text3.color)
                                        .offset(x: barW * CGFloat(m * 60 / span))
                                }
                            }
                            .frame(width: barW, alignment: .leading)
                        }
                        .frame(height: 34)
                        Hairline()
                        row(name: s.session.name, mono: false, badge: AgentMark(agent: s.session.agent, account: s.account),
                            line: [s.session.model?.capitalized, "parent"].compactMap { $0 }.joined(separator: " · "),
                            prefix: "", from: start, to: s.status.isLive ? nil : model.lastActiveDate(s), running: s.status == .running,
                            start: start, span: span, barW: barW, selected: false, inferred: false) {}
                        ForEach(Array(subs.enumerated()), id: \.element.id) { i, sub in
                            let last = i == subs.count - 1 || subs[(i + 1)...].first { $0.depth <= sub.depth }.map { $0.depth < sub.depth } == true
                            row(name: sub.name, mono: true, badge: AgentMark(agent: s.session.agent, account: s.account),
                                line: [sub.model, sub.inferred ? "inferred" : nil, SubagentCard.tokens(sub.tokens) + " tokens"].compactMap { $0 }.joined(separator: " · "),
                                prefix: String(repeating: "│ ", count: max(0, sub.depth - 1)) + (last ? "└" : "├"),
                                from: sub.started, to: sub.ended, running: sub.ended == nil, start: start, span: span, barW: barW,
                                selected: sub.id == sel?.id, inferred: sub.inferred) { node = sub.id }
                                .contextMenu {
                                    Button("Ask the parent to stop \(sub.name)") { model.askToStop(sub, in: s) }
                                }
                        }
                        if let sel { detail(sel, parent: s).padding(.top, 18) }
                    }
                    .padding(.horizontal, 26).padding(.vertical, 10)
                }
            }
        }
        .gesture(MagnificationGesture().onChanged { v in minutes = min(60, max(1, minutes / Double(v))) })
    }

    private func row(name: String, mono: Bool, badge: AgentMark, line: String, prefix: String, from: Date, to: Date?, running: Bool,
                     start: Date, span: Double, barW: CGFloat, selected: Bool, inferred: Bool, onTap: @escaping () -> Void) -> some View {
        let x = barW * CGFloat(max(0, from.timeIntervalSince(start)) / span)
        let end = (to ?? tick).timeIntervalSince(start)
        let w = max(6, barW * CGFloat(max(0, end) / span) - x)
        let fill: Color = running ? t.now.color.opacity(0.28) : badge.fill.color.opacity(0.22)
        return Button(action: onTap) {
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    if !prefix.isEmpty { Text(prefix).ui(13, mono: true).foregroundStyle(t.text3.color) }
                    AgentBadge(badge, size: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).ui(12.5, mono ? .regular : .medium, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                        Text(line).ui(11).foregroundStyle(t.text3.color).lineLimit(1)
                    }
                }
                .frame(width: 330, alignment: .leading)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill)
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(badge.fill.color, style: StrokeStyle(lineWidth: 1, dash: inferred ? [4, 3] : [])))
                        .frame(width: min(w, barW - x), height: 16)
                        .offset(x: x)
                }
                .frame(width: barW, alignment: .leading)
            }
            .frame(height: 46)
            .background(selected ? t.now.color.opacity(0.06) : .clear)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(running ? "running" : "finished")")
    }

    private func detail(_ sub: Subagent, parent: BoardItem) -> some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("\(sub.name) · asked by \(parent.session.name)")
                Text(sub.asked.isEmpty ? "—" : "\u{201C}" + sub.asked + "\u{201D}").ui(14).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                MicroLabel(sub.ended == nil ? "Right now · \(ageText(sub.started)) ago" : "Finished · \(ageText(sub.ended)) ago")
                Text(sub.caption.isEmpty ? "no caption yet" : sub.caption).ui(14, .medium).foregroundStyle(t.now.color).fixedSize(horizontal: false, vertical: true)
                Text("\(sub.model) · \(SubagentCard.tokens(sub.tokens)) tokens · \(ageText(sub.started, now: sub.ended ?? tick))").ui(12.5).foregroundStyle(t.text3.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel("Touched")
                if sub.touched.isEmpty { Text("Nothing yet").ui(12.5).foregroundStyle(t.text3.color) }
                ForEach(sub.touched, id: \.path) { f in
                    Button { model.openInViewer(f.path) } label: {
                        HStack {
                            Text((f.path as NSString).lastPathComponent).ui(12.5, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                            Spacer()
                            if f.added > 0 { Text("+\(f.added)").ui(12, mono: true).foregroundStyle(t.diffAddText.color) }
                            if f.removed > 0 { Text("−\(f.removed)").ui(12, mono: true).foregroundStyle(t.diffDelText.color) }
                            if f.read && f.added + f.removed == 0 { Text("read").ui(12, mono: true).foregroundStyle(t.text3.color) }
                        }
                    }.buttonStyle(.plain)
                }
                Button { model.reveal(parent); NotificationCenter.default.post(name: .rawStream, object: model.workspaceId(of: parent)) } label: {
                    Text("Open its raw stream ⌘R").ui(12.5).foregroundStyle(t.text2.color)
                }.buttonStyle(.plain).padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surface2.color))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separator.color))
    }
}

extension AppModel {
    /// S05.D.stop: no direct kill — ask the parent to stop the subagent (it decides), between turns only.
    func askToStop(_ sub: Subagent, in parent: BoardItem) {
        guard let agent = parent.liveAgent else { return }
        interrupt(parent)
        let r = runtime
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { try? r.submit(agent, text: "Stop subagent \(sub.name) and tell me where it got to.") }
    }
}
