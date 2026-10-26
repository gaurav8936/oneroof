import SwiftUI
import OneRoofCore

private struct V2Card<C: View>: View {
    var tokens: V2Planes; @ViewBuilder var content: () -> C
    var body: some View { content().background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface)).overlay(RoundedRectangle(cornerRadius: 12).stroke(tokens.separator)) }
}

/// Home (A5) — replaces OverviewView.
struct HomeView: View {
    struct V2FeedEvent: Identifiable { var id = UUID(); var kind: String; var who: String; var time: String; var what: String; var whereText: String }
    var summary: String; var windows: [(V2WindowRef, [V2SessionRow])]; var feed: [V2FeedEvent]; var tokens: V2Planes
    @State private var feedTab = "Feed"
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("All windows").font(.system(size: 26, weight: .bold)); Text(summary).foregroundStyle(tokens.text2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(windows, id: \.0.id) { w, rows in
                        V2Card(tokens: tokens) {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack { Circle().fill(w.color).frame(width: 9, height: 9); Text(w.name).bold(); Spacer(); Text("\(w.count)").foregroundStyle(tokens.text3) }.padding(10)
                                ForEach(rows.prefix(4)) { r in HStack { V2AgentBadge(text: r.badge, color: r.badgeColor, status: r.status, ring: tokens.surface, size: 18); VStack(alignment: .leading) { Text(r.title).bold().lineLimit(1); Text(r.statusLine).font(.system(size: 10.5)).foregroundStyle(tokens.text2) } }.padding(.horizontal, 10).padding(.vertical, 5) }
                            }
                        }
                    }
                }
                HStack { Button("+ New work item") {}; Button("+ New objective") {} }
                Spacer()
            }
            V2Card(tokens: tokens) {
                VStack(alignment: .leading, spacing: 0) {
                    Picker("", selection: $feedTab) { ForEach(["Feed", "Agents", "Objectives", "Projects", "Foundations"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden().padding(10)
                    HStack { Text("What's happening").bold(); Spacer(); Menu("Mute") { Button("Mute this window") {} }.fixedSize() }.padding(.horizontal, 12)
                    List(feed) { e in VStack(alignment: .leading, spacing: 1) { HStack { Text(e.kind).bold().foregroundStyle(Color(.systemGreen)); Text(e.who); Spacer(); Text(e.time).font(.system(size: 10, design: .monospaced)).foregroundStyle(tokens.text3) }; Text(e.what); Text(e.whereText).font(.system(size: 10.5)).foregroundStyle(tokens.text3) } }
                        .listStyle(.plain)
                }
            }.frame(width: 340)
        }.font(.system(size: 12)).padding(16)
    }
}

/// Needs you (A6) — replaces DecisionsView.
struct NeedsYouView: View {
    struct V2Decision: Identifiable { var id: String; var session: String; var command: String; var why: String; var touches: String; var risk: String; var ifNo: String; var age: String }
    var queue: [V2Decision]; var decidedToday: Int; var rulesLearned: Int; var tokens: V2Planes
    var onAllow: (String) -> Void; var onAlways: (String) -> Void; var onDeny: (String) -> Void; var onReply: (String, String) -> Void
var onStep: (Int) -> Void = { _ in }
    @State private var current: String?; @State private var reply = ""
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Needs you").font(.system(size: 22, weight: .bold)) + Text("  \(queue.count)").foregroundColor(tokens.text3)
                ForEach(queue) { d in VStack(alignment: .leading) { HStack { Text(d.session).bold(); Spacer(); Text(d.age).foregroundStyle(tokens.text3) }; Text(d.command).foregroundStyle(tokens.text2).lineLimit(1) }.padding(10).background(RoundedRectangle(cornerRadius: 10).fill(d.id == shown?.id ? tokens.control : tokens.surface)).onTapGesture { current = d.id } }
                Spacer(); Text("Earlier today · \(decidedToday) decided · \(rulesLearned) rules learned").font(.system(size: 11)).foregroundStyle(tokens.text2)
            }.frame(width: 300)
            if let d = shown {
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(d.session) wants to run a command").font(.system(size: 16, weight: .bold))
                    Text(d.command).font(.system(size: 12, design: .monospaced)).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(tokens.terminal)).foregroundStyle(tokens.terminalText)
                    Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow { Text("Why").foregroundStyle(tokens.text2); Text(d.why) }
                        GridRow { Text("Touches").foregroundStyle(tokens.text2); Text(d.touches) }
                        GridRow { Text("Risk").foregroundStyle(tokens.text2); Text(d.risk).bold() }
                        GridRow { Text("If you say no").foregroundStyle(tokens.text2); Text(d.ifNo) }
                    }
                    HStack {
                        Button("Allow once ↩") { onAllow(d.id) }.buttonStyle(.borderedProminent).keyboardShortcut(KeymapV2.allowOnce.swiftUI)
                        Button("Always allow this") { onAlways(d.id) }
                        Button("Deny esc", role: .destructive) { onDeny(d.id) }.keyboardShortcut(KeymapV2.deny.swiftUI)
                        TextField("Reply with instructions…", text: $reply).onSubmit { onReply(d.id, reply); reply = "" }
                        Button("Next decision ⌘]") { onStep(1) }.buttonStyle(.plain).keyboardShortcut(KeymapV2.nextDecision.swiftUI)
                        Button("") { onStep(-1) }.buttonStyle(.plain).keyboardShortcut(KeymapV2.previousDecision.swiftUI).frame(width: 0)
                    }
                    Text("Nothing is approved for you. ↩ allow once · esc deny · ⌘] next · ⌘[ previous").font(.system(size: 11)).foregroundStyle(tokens.text3)
                    Spacer()
                }.padding(22).background(RoundedRectangle(cornerRadius: 14).fill(tokens.surface))
            } else {
                VStack(spacing: 6) { Text("Nothing waiting.").font(.system(size: 20, weight: .bold)); Text("Agents will ask here, with their reasons.").foregroundStyle(tokens.text2); Text("\(decidedToday) decided today").font(.system(size: 11)).foregroundStyle(tokens.text3) }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.font(.system(size: 12.5)).padding(16)
    }
    private var shown: V2Decision? { queue.first { $0.id == current } ?? queue.first }
}

/// Work (A7) — projects + roadmap, with Board as a view.
struct V2WorkView<Board: View>: View {
    struct Project: Identifiable { var id: String; var team: String; var title: String; var state: String }
    struct Ticket: Identifiable { var id: String; var kind: String; var title: String; var state: String; var phase: String }
    var projects: [Project]; var tickets: [Ticket]; var progress: (done: Int, total: Int); var tokens: V2Planes
    var onPlan: (Ticket) -> Void
    @ViewBuilder var board: () -> Board
    @State private var selected: String?; @State private var showBoard = false; @State private var showDone = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            List(selection: $selected) {
                ForEach(Dictionary(grouping: projects, by: \.team).sorted { $0.key < $1.key }, id: \.key) { team, ps in
                    Section(team) { ForEach(ps) { p in HStack { VStack(alignment: .leading) { Text(p.id).font(.system(size: 10.5, weight: .semibold, design: .monospaced)); Text(p.title).font(.system(size: 11)).foregroundStyle(tokens.text2).lineLimit(1) }; Spacer(); Text(p.state).font(.system(size: 10)).padding(.horizontal, 7).background(Capsule().fill(tokens.control)) }.tag(p.id) } }
                }
            }.frame(width: 290)
            VStack(alignment: .leading, spacing: 10) {
                Picker("", selection: $showBoard) { Text("Projects").tag(false); Text("Board ⌘B").tag(true) }.pickerStyle(.segmented).labelsHidden().fixedSize()
                if showBoard { board() } else {
                    Text(selected ?? projects.first?.id ?? "").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(tokens.accentText)
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))).frame(width: 180)
                    Text("\(progress.done) of \(progress.total) tickets done · Linear ↗").foregroundStyle(tokens.text2)
                    Toggle("Show done", isOn: $showDone)
                    ForEach(Dictionary(grouping: tickets, by: \.phase).sorted { $0.key < $1.key }, id: \.key) { phase, ts in
                        Text(phase).bold().padding(.top, 6)
                        ForEach(ts.filter { showDone || $0.state != "Done" }) { t in
                            HStack { Text(t.id).font(.system(size: 10.5, design: .monospaced)).frame(width: 70, alignment: .leading); Text(t.kind).font(.system(size: 10)).padding(.horizontal, 7).background(Capsule().fill(tokens.control)); Text(t.title).lineLimit(1); Spacer(); Text(t.state).foregroundStyle(Color(.systemOrange)); Button { onPlan(t) } label: { Image(systemName: "play.fill") }.buttonStyle(.plain).help("Plan a session from this ticket") }
                        }
                    }
                }
                Spacer()
            }
        }.font(.system(size: 12)).padding(16)
    }
}

/// Machine (A8) — replaces ResourcesView.
struct MachineView: View {
    struct AppUse: Identifiable { var id: String { name }; var name: String; var detail: String; var cpu: String; var memory: String; var share: Double; var canQuit: Bool }
    struct SessionUse: Identifiable { var id: String { title }; var title: String; var cpu: String; var memory: String; var guardUsed: Double; var guardText: String }
    var meters: [(String, String, String)]; var apps: [AppUse]; var sessions: [SessionUse]; var tokens: V2Planes
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Machine").font(.system(size: 26, weight: .bold))
            HStack(spacing: 10) { ForEach(meters, id: \.0) { m in VStack(alignment: .leading) { Text(m.0).font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.text3); Text(m.1).font(.system(size: 22, weight: .bold)); Text(m.2).font(.system(size: 11)).foregroundStyle(tokens.text2) }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface)) } }
            HStack(alignment: .top, spacing: 12) {
                List(apps) { a in HStack { Text(a.name).bold(); Text(a.detail).font(.system(size: 10.5)).foregroundStyle(tokens.text3); Spacer(); ProgressView(value: a.share).frame(width: 90); Text(a.cpu).frame(width: 44, alignment: .trailing); Text(a.memory).bold().frame(width: 56, alignment: .trailing); if a.canQuit { Button("Quit") {}.buttonStyle(.borderless) } }.font(.system(size: 11.5, design: .monospaced)) }
                List(sessions) { s in VStack(alignment: .leading) { HStack { Text(s.title).bold().lineLimit(1); Spacer(); Text("\(s.cpu) · \(s.memory)").font(.system(size: 11, design: .monospaced)) }; HStack { ProgressView(value: s.guardUsed); Text(s.guardText).font(.system(size: 10.5)).foregroundStyle(tokens.text3) } } }.frame(width: 420)
            }
            Text("roofd warns at 1.0 GB and ends a session at 2.0 GB.").font(.system(size: 11)).foregroundStyle(tokens.text2)
        }.font(.system(size: 12)).padding(16)
    }
}

/// Loops (A9).
struct V2LoopsView: View {
    struct LoopRow: Identifiable { var id: String { name }; var name: String; var detail: String; var when: String; var fence: String; var result: String }
    var loops: [LoopRow]; var tonight: Int; var lastNight: [String]; var tokens: V2Planes; var onSchedule: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Loops").font(.system(size: 26, weight: .bold))
                Text("Work that runs on its own, inside fences, and reports back. Loops can't push to protected branches or mark work Done.").foregroundStyle(tokens.text2)
                ForEach(loops) { l in HStack { VStack(alignment: .leading) { Text(l.name).bold(); Text(l.detail).font(.system(size: 11)).foregroundStyle(tokens.text2) }; Spacer(); Text(l.when).frame(width: 160, alignment: .leading); Text(l.fence).frame(width: 150, alignment: .leading); Text(l.result).padding(.horizontal, 8).background(Capsule().fill(tokens.control)) }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface)) }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Tonight").font(.system(size: 15, weight: .bold)); Text("\(tonight) scheduled.").foregroundStyle(tokens.text2)
                Button("+ Schedule a session", action: onSchedule)
                Divider(); Text("LAST NIGHT").font(.system(size: 10, weight: .bold)).foregroundStyle(tokens.text3)
                ForEach(lastNight, id: \.self) { Text($0) }
                Spacer()
            }.padding(14).frame(width: 300).background(RoundedRectangle(cornerRadius: 12).fill(tokens.surface))
        }.font(.system(size: 12)).padding(16)
    }
}
