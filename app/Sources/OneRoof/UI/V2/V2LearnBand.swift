import SwiftUI
import OneRoofCore

// LAB-1233 · Learn › a band (L1) and a programme, as drawn in One Roof Learn.dc.html.

/// One card in a list: ▶ · title · subtitle · badge · length.
struct LearnCardRow: View {
    let slug: String
    let audio: LearnAudio
    @ObservedObject var player: CoursePlayer
    var queue: [String] = []
    var number: String? = nil
    var badge: String? = nil
    let open: () -> Void
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        let c = deck.cards[slug]
        let here = audio.playingSlug == slug
        HStack(spacing: 12) {
            if let number {
                Text(number).font(.system(size: 22, weight: .bold)).foregroundStyle(t.accent.color).frame(width: 40, alignment: .leading)
            } else {
                LearnRoundPlay(playing: here && player.playing) { audio.toggle(slug, then: queue.isEmpty ? [slug] : Array(queue.drop { $0 != slug })) }
                    .frame(width: 30)
            }
            Button(action: open) {
                if number != nil {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c?.title ?? slug).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color)
                        Text(c?.subtitle ?? "").font(.system(size: 12)).foregroundStyle(t.text2.color).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    (Text(c?.title ?? slug).font(.system(size: 14, weight: .semibold)).foregroundColor(t.text.color)
                     + Text(" · " + (c?.subtitle ?? "")).font(.system(size: 13)).foregroundColor(t.text2.color))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            Text(badge ?? "\(c?.scenes ?? 0) scenes").font(.system(size: 11)).foregroundStyle(t.text3.color).frame(width: number != nil ? 120 : 140, alignment: .leading)
            Text(LearnDeck.minutes(c?.estSeconds ?? 0)).font(.system(size: 12)).foregroundStyle(t.text3.color).frame(width: 60, alignment: .trailing)
        }
        .padding(.horizontal, number != nil ? 8 : 6).padding(.vertical, number != nil ? 12 : 7)
        .background(RoundedRectangle(cornerRadius: 6).fill(here ? t.selection.color : Color.clear))
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }
}

struct LearnBandPage: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        let b = deck.band(id: nav.band)
        let list = deck.lists[b.id] ?? []
        let key = b.key.filter { deck.cards[$0] != nil }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 40) { intro(b, list).frame(maxWidth: .infinity, alignment: .leading); bandPosts(b).frame(width: posts.isEmpty ? 0 : 420) }
            LearnDial(deck: deck, tuned: audio.tuned, only: b.id) { k in nav.slug = k; audio.play(k, then: audio.bandFrom(k)) }
                .padding(.horizontal, 22).padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.display.fill.color))
                .padding(.top, 24)
            group("Start here", "the four cards to hear first", "\(key.count) cards", key, list)
            ForEach(b.tracks, id: \.self) { tr in
                let ks = list.filter { deck.cards[$0]?.track == tr && !b.key.contains($0) }
                if !ks.isEmpty {
                    group(LearnDeck.label(tr), deck.tracks[tr]?.intro ?? "", "\(ks.count) cards", ks, list, marked: nav.focusTrack == tr)
                        .id(LearnRadioRoute.anchor(track: tr))
                }
            }
        }
        .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 48)
        .frame(maxWidth: 1360, alignment: .leading)
    }

    private func intro(_ b: DeckBand, _ list: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnKicker(text: "Band \(b.n) · \(b.zone)")
            Text(b.title).font(.system(size: 72, weight: .bold)).tracking(-2).padding(.top, 6).padding(.bottom, 8).foregroundStyle(t.text.color)
            Text(b.sub + ".").font(.system(size: 18, weight: .medium)).foregroundStyle(t.text.color).padding(.bottom, 6)
            Text(b.def).font(.system(size: 15)).foregroundStyle(t.text2.color).frame(maxWidth: 600, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                LearnPillPlay(label: "Play the band", big: true) { if let f = list.first { audio.play(f, then: list) } }
                Text("\(list.count) cards on this band · \(b.tracks.count) tracks").font(.system(size: 12)).foregroundStyle(t.text3.color)
            }
            .padding(.top, 16)
        }
    }

    @ViewBuilder private func bandPosts(_ b: DeckBand) -> some View {
        let mine = b.posts.compactMap { s in posts.first { $0.slug == s } }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(mine) { p in
                let st = LearnPosts.state(p, in: posts, today: LearnPostRow.today)
                Button { nav.openPost(p.slug) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        LearnKicker(text: (p.series == "Agentic engineering" ? "Series" : "Field notes") + " · " + st.label, size: 10)
                        Text(p.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.toolbar.color))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// `marked`: the track an "On this band" chip opened the page at (LAB-1247), drawn with an accent rule.
    private func group(_ label: String, _ intro: String, _ meta: String, _ ks: [String], _ queue: [String], marked: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    (Text(label).font(.system(size: 18, weight: .bold)).foregroundColor(t.text.color)
                     + Text(intro.isEmpty ? "" : " · " + intro).font(.system(size: 13)).foregroundColor(t.text2.color)).lineLimit(1)
                    Spacer()
                    Text(meta).font(.system(size: 12)).foregroundStyle(t.text3.color)
                }
                .padding(.bottom, 6)
                Rectangle().fill(marked ? t.accent.color : t.separatorStrong.color).frame(height: marked ? 2 : 1)
            }
            ForEach(ks, id: \.self) { k in
                LearnCardRow(slug: k, audio: audio, player: player, queue: queue) { nav.openCard(k) }
            }
        }
        .padding(.top, 28)
    }
}

struct LearnPathPage: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        if let pa = deck.paths.first(where: { $0.id == nav.path }) ?? deck.paths.first {
            let ks = pa.slugs.filter { deck.cards[$0] != nil }
            let crosses = ks.map { deck.band(of: $0).title }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            VStack(alignment: .leading, spacing: 0) {
                LearnKicker(text: "Programme · \(ks.count) cards · \(ks.reduce(0) { $0 + (deck.cards[$1]?.estSeconds ?? 0) } / 60) min")
                Text(pa.title).font(.system(size: 48, weight: .bold)).tracking(-1.4).foregroundStyle(t.text.color).padding(.top, 6).padding(.bottom, 8)
                Text(pa.why).font(.system(size: 17)).foregroundStyle(t.text2.color).padding(.bottom, 6)
                Text("Crosses \(crosses.joined(separator: ", ")). Plays in order, then stops.").font(.system(size: 13)).foregroundStyle(t.text3.color).padding(.bottom, 18)
                LearnPillPlay(label: "Play the programme", big: true) { if let f = ks.first { audio.play(f, then: ks) } }.padding(.bottom, 18)
                ForEach(Array(ks.enumerated()), id: \.offset) { i, k in
                    let b = deck.band(of: k)
                    LearnCardRow(slug: k, audio: audio, player: player, queue: ks, number: "\(i + 1)", badge: "Band \(b.n) · \(b.title)") { nav.openCard(k) }
                }
            }
            .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 64)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }
}
