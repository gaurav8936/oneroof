import AppKit
import SwiftUI
import OneRoofCore

/// The deck's catalog (content/catalog.json): suits → tracks → cards, read in place.
struct DeckCatalog {
    struct Track: Identifiable { var id: String; var suit: String; var emoji: String; var intro: String; var cards: [String] }
    struct Suit: Identifiable { var id: String; var symbol: String; var label: String; var tracks: [String] }
    var version = ""
    var tracks: [Track] = []
    var suits: [Suit] = []

    static func load(deck: String?) -> DeckCatalog {
        guard let deck, let d = FileManager.default.contents(atPath: deck + "/content/catalog.json"),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return DeckCatalog() }
        var c = DeckCatalog()
        c.version = j["version"] as? String ?? ""
        c.tracks = (j["tracks"] as? [[String: Any]] ?? []).compactMap { t in
            guard let id = t["id"] as? String else { return nil }
            return Track(id: id, suit: t["suit"] as? String ?? "", emoji: t["emoji"] as? String ?? "", intro: t["intro"] as? String ?? "",
                         cards: t["cards"] as? [String] ?? [])
        }
        c.suits = (j["suits"] as? [[String: Any]] ?? []).compactMap { s in
            guard let id = s["id"] as? String else { return nil }
            return Suit(id: id, symbol: s["symbol"] as? String ?? "", label: s["label"] as? String ?? id, tracks: s["tracks"] as? [String] ?? [])
        }
        return c
    }
}

/// Learn › Radio and All cards (handover A12.2, NEW-8): the Agentic Engineering deck as bands (its tracks) you tune
/// into — the now-playing panel drives today's player (it keeps playing while you work), each band lists its narrated
/// cards with ▶ and Open; All cards is the whole deck by suit and band. Pages (today's Learn) stays the default view.
struct V2LearnRadio: View {
    @ObservedObject var model: AppModel
    @ObservedObject var player: CoursePlayer
    var map: Bool
    var open: (String) -> Void
    @State private var band: String?
    /// Read once when the view appears (it is 190 KB; the player publishes twice a second while playing).
    @State private var catalog = DeckCatalog()
    var t: ThemeTokens { model.themes.centre.tokens }
    /// Deck cards as Learn items, by track (section "Agentic Engineering · <track>").
    private var cards: [String: [LearnItem]] {
        Dictionary(grouping: model.learnItems.filter { $0.section.hasPrefix("Agentic Engineering · ") }) {
            String($0.section.dropFirst("Agentic Engineering · ".count))
        }
    }

    var body: some View {
        let cat = catalog, byTrack = cards
        let total = byTrack.values.reduce(0) { $0 + $1.count }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("AGENTIC ENGINEERING" + (cat.version.isEmpty ? "" : " · EDITION \(cat.version)") + " · SHIPS WITH THIS BUILD")
                        .font(.system(size: 10.5, weight: .heavy)).tracking(0.6).foregroundStyle(t.accent.color)
                    Spacer()
                    Text("\(total) CARDS").font(.system(size: 10.5, weight: .heavy)).tracking(0.6).foregroundStyle(t.secondaryText.color)
                }
                if total == 0 {
                    Text("The narrated deck is not in this build. Learn's pages still have the field manual and skills.")
                        .font(.system(size: 13)).foregroundStyle(t.secondaryText.color)
                } else if map {
                    allCards(cat, byTrack)
                } else {
                    radio(cat, byTrack)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(t.window.color)
        .onAppear {
            model.loadLearn()
            if catalog.tracks.isEmpty { catalog = DeckCatalog.load(deck: AEFolder.deckRoot(model.settings.agenticEngineering.path)) }
        }
    }

    // MARK: Radio

    @ViewBuilder private func radio(_ cat: DeckCatalog, _ byTrack: [String: [LearnItem]]) -> some View {
        let bands = cat.tracks.filter { !(byTrack[$0.id] ?? []).isEmpty }
        let current = band ?? bands.first?.id
        HStack(alignment: .bottom) {
            (Text("Everything about building with agents, on one dial. ").foregroundColor(t.text.color)
             + Text("Tune in.").foregroundColor(t.accent.color))
                .font(.system(size: 40, weight: .heavy)).tracking(-1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
            Text("Short narrated cards, each one also a skill your agents run. It keeps playing while you work, and any card can go straight into a session.")
                .font(.system(size: 12.5)).foregroundStyle(t.secondaryText.color).frame(width: 260, alignment: .leading)
        }
        nowPlaying(byTrack[current ?? ""] ?? [])
        // The dial: every band, with its card count.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(bands) { b in
                let on = b.id == current
                Button { band = b.id } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\((byTrack[b.id] ?? []).count) cards").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(t.secondaryText.color)
                        Text(b.id.replacingOccurrences(of: "-", with: " ").capitalized).font(.system(size: 14, weight: .bold)).foregroundStyle(t.text.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? t.accent.color.opacity(0.22) : t.card.color))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? t.accent.color : Color.clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .help(b.intro)
            }
        }
        if let b = bands.first(where: { $0.id == current }) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ON THIS BAND · " + b.intro).font(.system(size: 10.5, weight: .heavy)).tracking(0.4).foregroundStyle(t.secondaryText.color)
                ForEach(byTrack[b.id] ?? [], id: \.id) { c in cardRow(c) }
            }
        }
    }

    private func nowPlaying(_ band: [LearnItem]) -> some View {
        let term = model.themes.terminal.tokens
        let playing = player.pageId != nil
        return HStack(spacing: 16) {
            VStack(spacing: 10) {
                Button {
                    if playing { player.toggle() }
                    else if let first = band.first(where: { $0.audio }) { player.play(pageId: first.id, title: first.title, tracks: first.tracks()) }
                } label: { Image(systemName: player.playing ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 44, height: 36) }
                .buttonStyle(.borderedProminent)
                .disabled(!playing && !band.contains { $0.audio })
                .help(playing ? "Play / pause" : "Tune in: play this band's first narrated card")
                HStack(spacing: 6) {
                    Button("\(String(format: "%g", player.rate))×") { player.rate = player.rate >= 2 ? 0.75 : min(2, player.rate + 0.25) }
                        .help("Speed 0.75–2×")
                    Button { player.next() } label: { Image(systemName: "forward.end.fill") }.disabled(!playing).help("Next part")
                }
                Text("KEEPS PLAYING WHILE YOU WORK").font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundStyle(t.secondaryText.color)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(playing ? (player.playing ? "PLAYING" : "PAUSED") + " · PART \(player.index + 1) OF \(player.tracks.count)" : "NOT PLAYING")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced)).foregroundStyle(term.text3.color)
                Text(playing ? player.pageTitle : "Pick a band, then press play").font(.system(size: 22, weight: .bold)).foregroundStyle(term.accent.color)
                if playing, player.tracks.indices.contains(player.index) {
                    Text(player.tracks[player.index].title).font(.system(size: 12.5)).foregroundStyle(term.text2.color)
                    ProgressView(value: player.elapsed, total: max(player.duration, 1)).tint(term.accent.color)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(term.terminal.background.color))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.card.color))
    }

    private func cardRow(_ c: LearnItem) -> some View {
        HStack(spacing: 10) {
            Button { if player.pageId == c.id { player.toggle() } else { player.play(pageId: c.id, title: c.title, tracks: c.tracks()) } } label: {
                Image(systemName: player.pageId == c.id && player.playing ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 18))
            }
            .buttonStyle(.plain).disabled(!c.audio).help(c.audio ? "Listen" : "No narration")
            VStack(alignment: .leading, spacing: 1) {
                Text(c.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
                Text(c.summary).font(.system(size: 11.5)).foregroundStyle(t.secondaryText.color).lineLimit(1)
            }
            Spacer()
            Button("Open") { open(c.id) }.controlSize(.small).help("The card page: transcript, diagram and skill file")
        }
        .padding(.vertical, 5)
    }

    // MARK: All cards

    @ViewBuilder private func allCards(_ cat: DeckCatalog, _ byTrack: [String: [LearnItem]]) -> some View {
        Text("All cards").font(.system(size: 28, weight: .heavy)).foregroundStyle(t.text.color)
        ForEach(cat.suits) { s in
            VStack(alignment: .leading, spacing: 10) {
                Text("\(s.symbol) \(s.label)").font(.system(size: 13, weight: .bold)).foregroundStyle(t.text.color)
                ForEach(s.tracks, id: \.self) { tid in
                    let list = byTrack[tid] ?? []
                    if !list.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tid.replacingOccurrences(of: "-", with: " ").capitalized + " · \(list.count)")
                                .font(.system(size: 10.5, weight: .heavy)).tracking(0.4).foregroundStyle(t.secondaryText.color)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 6)], alignment: .leading, spacing: 6) {
                                ForEach(list, id: \.id) { c in
                                    Button { open(c.id) } label: {
                                        Text(c.title).font(.system(size: 12)).foregroundStyle(t.text.color).lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 8).padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(t.card.color))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
