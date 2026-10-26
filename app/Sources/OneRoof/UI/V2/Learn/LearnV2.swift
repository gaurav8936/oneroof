import SwiftUI
import OneRoofCore

/// Learn v2 (A12): bands → tracks → cards, card station, post reader. Rebuilt from One Roof Learn.dc.html.
/// Uses the existing LearnItem index (LearnIndex.build), CoursePlayer and PlayerBar.
enum LearnBand: String, CaseIterable, Identifiable {
    case context, loops, evidence, procedure
    var id: String { rawValue }
    var number: String { ["01", "02", "03", "04"][LearnBand.allCases.firstIndex(of: self)!] }
    var title: String { rawValue.capitalized }
    var subtitle: String {
        switch self {
        case .context: return "What the agent knows at the first prompt"
        case .loops: return "A unit of work with a stop condition"
        case .evidence: return "Proof the unit is done"
        case .procedure: return "What the next session inherits"
        }
    }
    var tracks: [String] {
        switch self {
        case .context: return ["foundations", "vault", "influences"]
        case .loops: return ["rhythms", "pipeline", "model-craft", "modality"]
        case .evidence: return ["ship", "debug", "safety"]
        case .procedure: return ["doctrine", "comms", "infra", "play"]
        }
    }
    /// Curated start-here cards; they belong to this band even when their track is elsewhere.
    var startHere: [String] {
        switch self {
        case .context: return ["context-as-structure", "knowledge-notes", "docs-phonebook", "the-2x2-map"]
        case .loops: return ["loops-first", "done-when", "feedback-loop", "orchestration"]
        case .evidence: return ["evidence-check", "test-first", "smoke-prod", "audit-trail"]
        case .procedure: return ["compounding-instincts", "gotcha-log", "decision-record", "spawn-doctrine"]
        }
    }
    static let plainTrackNames: [String: String] = ["foundations": "Big ideas", "vault": "Notes & memory", "influences": "People worth hearing", "rhythms": "Daily loops", "pipeline": "Ticket to merged PR", "model-craft": "Working with models", "modality": "Beyond text", "ship": "Shipping", "debug": "Debugging", "safety": "Guardrails", "doctrine": "How we work", "comms": "Messages & channels", "infra": "Dev environment", "play": "Walkthroughs"]
}

struct LearnV2: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: CoursePlayer
    var tokens: V2Planes
    @State private var band: LearnBand = .loops
    @State private var openCard: LearnItem?
    @State private var tab = "Radio"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Learn").bold(); Text("Agentic Engineering · \(tab)").foregroundStyle(tokens.text2)
                Spacer()
                Picker("", selection: $tab) { ForEach(["Radio", "Writing", "All cards"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
            }.padding(.horizontal, 20).padding(.vertical, 8)
            Divider()
            ScrollView {
                if let c = openCard { CardStation(item: c, player: player, tokens: tokens) { openCard = nil } }
                else if tab == "Radio" { radio } else { allCards }
            }
            if player.pageId != nil { Divider(); PlayerBar(player: player, tokens: model.themes.centre.tokens, onOpenPage: nil) }
        }
        .onAppear { model.loadLearn() }
    }

    private var radio: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Everything about building with agents, on one dial. ").font(.system(size: 48, weight: .bold)) + Text("Tune in.").font(.system(size: 48, weight: .bold)).foregroundColor(tokens.accent)
            HStack(spacing: 10) {
                ForEach(LearnBand.allCases) { b in
                    Button { band = b } label: {
                        VStack(alignment: .leading) { Text("\(b.number) · \(items(in: b).count)").font(.system(size: 11, design: .monospaced)); Text(b.title).font(.system(size: 17, weight: .bold)) }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(b == band ? tokens.terminal : tokens.control))
                            .foregroundStyle(b == band ? tokens.terminalText : tokens.text)
                    }.buttonStyle(.plain)
                }
            }
            Text(band.subtitle).font(.system(size: 17, weight: .medium))
            ForEach(items(in: band)) { i in
                HStack { Button { player.play(pageId: i.id, title: i.title, tracks: i.tracks()) } label: { Image(systemName: "play.circle") }.buttonStyle(.plain)
                    Text(i.title).bold(); Text(i.summary).foregroundStyle(tokens.text2).lineLimit(1); Spacer() }
                    .contentShape(Rectangle()).onTapGesture { openCard = i }
            }
        }.padding(40)
    }

    private var allCards: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(LearnBand.allCases) { b in
                Text("\(b.number) \(b.title)").font(.system(size: 18, weight: .bold))
                ForEach(b.tracks, id: \.self) { t in
                    Text(LearnBand.plainTrackNames[t] ?? t).font(.system(size: 13, weight: .semibold)) + Text("  track · \(t)").foregroundColor(tokens.text3)
                    FlowRow(items: model.learnItems.filter { $0.section.hasSuffix("· " + t) }.map(\.title)) { Text($0).font(.system(size: 11)).padding(4).background(RoundedRectangle(cornerRadius: 4).fill(tokens.control)) }
                }
            }
        }.padding(40)
    }

    private func items(in b: LearnBand) -> [LearnItem] {
        model.learnItems.filter { i in b.tracks.contains { i.section.hasSuffix("· " + $0) } || b.startHere.contains((i.path as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? "") }
    }
}

/// V2Card station: Listen · Transcript · Skill file. The scene player is the card's generated html (WebPage), unchanged.
struct CardStation: View {
    var item: LearnItem; @ObservedObject var player: CoursePlayer; var tokens: V2Planes; var close: () -> Void
    @State private var tab = "Listen"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("‹ Back", action: close).buttonStyle(.link)
            Text(item.title).font(.system(size: 40, weight: .bold)); Text(item.summary).foregroundStyle(tokens.text2)
            HStack { Button("Play in One Roof") { player.play(pageId: item.id, title: item.title, tracks: item.tracks()) }.buttonStyle(.borderedProminent); Button("Use in a session ▾") {} }
            Picker("", selection: $tab) { ForEach(["Listen", "Transcript", "Skill file"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden().fixedSize()
            switch tab {
            case "Skill file": MarkdownPage(path: (item.path as NSString).deletingLastPathComponent + "/SKILL.md").frame(minHeight: 400)
            default: WebPage(path: item.path, root: item.root, blocked: { LearnExclusions.isExcluded($0) }, pageScript: LearnExclusions.hideLinksScript).frame(minHeight: 460)
            }
        }.padding(32)
    }
}
