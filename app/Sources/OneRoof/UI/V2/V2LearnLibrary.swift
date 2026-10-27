import AppKit
import SwiftUI
import OneRoofCore

// LAB-1233 · Learn › Writing, the post reader and All cards (the map, and "How do I…" search), as drawn in
// One Roof Learn.dc.html. Posts come from the blog hub (BlogHub, cached) and the owner's Learn folders
// (LearnPosts); the app ships none.

struct LearnWritingPage: View {
    @ObservedObject var nav: LearnNav
    let posts: [LearnPost]
    @Environment(\.theme) private var t

    var body: some View {
        let series = posts.filter { $0.series == "Agentic engineering" }
        let notes = posts.filter { $0.series != "Agentic engineering" }
        VStack(alignment: .leading, spacing: 0) {
            LearnKicker(text: "Broadcast schedule")
            Text("Writing").font(.system(size: 48, weight: .bold)).tracking(-1.4).foregroundStyle(t.text.color).padding(.top, 6)
                .padding(.bottom, posts.isEmpty ? 20 : 6)
            if posts.isEmpty { LearnNoPosts() } else { LearnPostsSource(posts: posts).padding(.bottom, 20) }
            ForEach([("Agentic engineering", "\(series.count) parts", series), ("Field notes", "case studies", notes)], id: \.0) { label, meta, list in
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(label).font(.system(size: 18, weight: .bold)).foregroundStyle(t.text.color)
                            Spacer()
                            Text(meta).font(.system(size: 12)).foregroundStyle(t.text3.color)
                        }
                        .padding(.bottom, 6)
                        Rectangle().fill(t.separatorStrong.color).frame(height: 1)
                        ForEach(list) { p in LearnPostRow(post: p, all: posts) { nav.openPost(p.slug) } }
                    }
                    .padding(.bottom, 28)
                }
            }
        }
        .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 64)
        .frame(maxWidth: 1100, alignment: .leading)
    }
}

struct LearnPostReader: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    @Environment(\.theme) private var t
    @Environment(\.textScale) private var scale

    var body: some View {
        if let p = posts.first(where: { $0.slug == nav.post }) {
            let deck = audio.deck
            let series = posts.filter { $0.series == "Agentic engineering" }
            let i = series.firstIndex(of: p)
            let bands = LearnDeck.bands.filter { $0.posts.contains(p.slug) }
            let band0 = bands.first ?? LearnDeck.fallbackBand
            let cards = (bands.isEmpty ? LearnDeck.bands : bands).flatMap(\.key).reduce(into: [String]()) { if deck.cards[$1] != nil && !$0.contains($1) { $0.append($1) } }.prefix(6)
            HStack(alignment: .top, spacing: 40) {
                toc(p).frame(width: 200)
                article(p, i, series.count, bands).frame(maxWidth: 740)
                side(band0, Array(cards)).frame(width: 300)
            }
            .padding(.horizontal, 40).padding(.top, 32).padding(.bottom, 64)
            .frame(maxWidth: 1360, alignment: .leading)
        } else {
            LearnNoPosts().padding(40).frame(maxWidth: 740, alignment: .leading)
        }
    }

    private func toc(_ p: LearnPost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnRuleHeading(text: "In this post")
            ForEach(p.sections, id: \.self) { h in
                Text(h).font(.system(size: 12)).foregroundStyle(t.text2.color).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
        }
    }

    private func article(_ p: LearnPost, _ i: Int?, _ of: Int, _ bands: [DeckBand]) -> some View {
        let blocks = FileParseCache.value(p.file, kind: "markdown", parse: MarkdownDoc.parse).filter {   // LAB-1332
            if case .code(let lang, _) = $0, lang.hasPrefix("gg-") { return false }      // site-only diagram and chart blocks
            if case .heading(_, let text, _) = $0, text == "Links" { return false }
            return true
        }
        let series = posts.filter { $0.series == "Agentic engineering" }
        let prev = i.flatMap { $0 > 0 ? series[$0 - 1] : nil }
        let next = i.flatMap { $0 + 1 < series.count ? series[$0 + 1] : nil }
        return VStack(alignment: .leading, spacing: 0) {
            LearnKicker(text: (i.map { "Agentic engineering · Part \($0 + 1) of \(of)" } ?? "Field notes") + " · "
                        + (bands.isEmpty ? "All bands" : bands.map(\.title).joined(separator: ", ")))
            Text(p.title).font(.system(size: 46, weight: .bold)).tracking(-1.4).foregroundStyle(t.text.color).padding(.top, 8).padding(.bottom, 12)
                .fixedSize(horizontal: false, vertical: true)
            if !p.subtitle.isEmpty {
                Text(p.subtitle).font(.system(size: 18)).lineSpacing(4).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Text(LearnPostReader.fullDate(p.date))
                Text("\(p.minutes) min read")
                Text(p.published ? "Published" : "Scheduled · " + LearnPostRow.day(p.date)).fontWeight(.semibold)
                    .foregroundStyle(p.published ? t.text3.color : t.accentText.color)
                Spacer(minLength: 0)
                if let web = URL(string: p.canonical), !p.canonical.isEmpty {
                    Button { NSWorkspace.shared.open(web) } label: { Text("Open on the web ↗").foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain).help(p.canonical)
                }
            }
            .font(.system(size: 12)).foregroundStyle(t.text2.color)
            .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            .padding(.top, 20).padding(.bottom, 24)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in MarkdownBlockView(block: b, path: p.file, t: t, scale: scale * 1.15, depth: 0) }
            }
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                let s = url.absoluteString
                if s.hasPrefix("/blog/") { nav.openPost(String(s.dropFirst(6))); return .handled }
                return .systemAction
            })
            HStack(spacing: 10) {
                if let prev { around("← Previous in the series", prev) } else { Spacer().frame(maxWidth: .infinity) }
                if let next { around("Next in the series →", next) } else { Spacer().frame(maxWidth: .infinity) }
            }
            .padding(.top, 32)
        }
    }

    private func around(_ dir: String, _ p: LearnPost) -> some View {
        Button { nav.openPost(p.slug) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(dir).font(.system(size: 11)).foregroundStyle(t.text3.color)
                Text(p.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.toolbar.color))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func side(_ band: DeckBand, _ cards: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnRuleHeading(text: "Hear it on the \(band.title) band")
            ForEach(cards, id: \.self) { k in
                HStack(spacing: 10) {
                    LearnRoundPlay(playing: audio.playingSlug == k && player.playing, size: 24) { audio.toggle(k) }
                    Button { nav.openCard(k) } label: {
                        Text(audio.deck.cards[k]?.title ?? k).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Text(LearnDeck.minutes(audio.deck.cards[k]?.estSeconds ?? 0)).font(.system(size: 11)).foregroundStyle(t.text3.color)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
            Button { nav.openBand(band.id) } label: { Text("Open the band →").font(.system(size: 12)).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain).padding(.vertical, 10)
        }
    }

    /// "24 Oct 2026".
    static func fullDate(_ s: String) -> String {
        guard let d = LearnPosts.day(s) else { return s }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - All cards · the map

struct LearnLibraryPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    @Environment(\.theme) private var t

    struct Block: Identifiable { var id: String; var name: String; var raw: String; var question: String; var intro: String; var kicker: String; var cards: [String]; var start: Bool }
    struct Column: Identifiable { var id: String { head }; var head: String; var sub: String; var count: Int; var grow: Int; var blocks: [Block] }

    private var columns: [Column] {
        let deck = audio.deck
        if nav.lens == "kind" {
            return LearnDeck.kinds.map { kd in
                let bl = kd.tracks.compactMap { tr -> Block? in
                    guard let track = deck.tracks[tr] else { return nil }
                    let n = LearnDeck.trackNames[tr]
                    return Block(id: "kind:" + tr, name: n?.name ?? LearnDeck.label(tr), raw: "track · " + tr, question: n?.question ?? "", intro: track.intro,
                                 kicker: kd.title.uppercased(), cards: track.cards.filter { deck.cards[$0] != nil }, start: false)
                }
                let n = bl.reduce(0) { $0 + $1.cards.count }
                return Column(head: kd.title, sub: kd.sub, count: n, grow: max(1, Int((Double(n) / 25).rounded())), blocks: bl)
            }
        }
        return LearnDeck.bands.map { b in
            let list = deck.lists[b.id] ?? []
            let start = Block(id: b.id + ":start", name: "Start here", raw: "curated", question: "The four cards to hear first on this band", intro: b.def,
                              kicker: "BAND \(b.n) · \(b.title.uppercased())", cards: b.key.filter { deck.cards[$0] != nil }, start: true)
            let rest = b.tracks.compactMap { tr -> Block? in
                let ks = list.filter { deck.cards[$0]?.track == tr && !b.key.contains($0) }
                guard !ks.isEmpty else { return nil }
                let n = LearnDeck.trackNames[tr]
                return Block(id: b.id + ":" + tr, name: n?.name ?? LearnDeck.label(tr), raw: "track · " + tr, question: n?.question ?? "",
                             intro: deck.tracks[tr]?.intro ?? "", kicker: "BAND \(b.n) · \(b.title.uppercased())", cards: ks, start: false)
            }
            return Column(head: "\(b.n) \(b.title)", sub: b.sub, count: list.count, grow: 1, blocks: [start] + rest)
        }
    }

    var body: some View {
        let deck = audio.deck
        let q = nav.query.trimmingCharacters(in: .whitespaces)
        // A question ("how do I run two agents at once") rarely has every word in one card: then the best-ranked cards light up.
        let exact: [String] = q.isEmpty ? [] : deck.search(q)
        let hits: [String] = q.isEmpty || !exact.isEmpty ? exact : deck.bestCards(for: q, limit: 12)
        let lq = q.lowercased()
        let postHits = q.isEmpty ? [] : posts.filter { ([$0.title, $0.subtitle, $0.summary] + $0.tags).joined(separator: " ").lowercased().contains(lq) }
        let cols = columns
        let sel = cols.flatMap(\.blocks).first { $0.id == nav.libSel }
        // LAB-1253: By folder lists the skills folder as packaged (search still lights the band map).
        let folders = nav.lens == "folder" && q.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    LearnKicker(text: "All cards · The map")
                    Text(q.isEmpty ? "Everything, at a glance" : "\u{201C}\(q)\u{201D}").font(.system(size: 44, weight: .bold)).tracking(-1.3)
                        .foregroundStyle(t.text.color).padding(.top, 6).padding(.bottom, 4)
                    Text(q.isEmpty ? "\(deck.count) cards. " + (nav.lens == "loop" ? "Grouped by when they matter in the work."
                                                               : nav.lens == "folder" ? "Laid out the way the skills folder is on disk." : "Grouped by what kind of thing they are.")
                         : "\(hits.count) of \(deck.count) cards light up · \(postHits.count) posts")
                        .font(.system(size: 14)).foregroundStyle(t.text2.color)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) { lenses; if !folders { legend } }
            }
            reader(hits.count, q, folders: folders).padding(.top, 18)
            if folders {
                LearnFolderView(model: model, nav: nav, player: player, audio: audio) { folderIntro }.padding(.top, 16)
            } else {
                HStack(alignment: .top, spacing: 24) { map(cols, hits, q).frame(maxWidth: .infinity); panel(sel, hits, postHits, q).frame(width: 380) }
                .padding(.top, 16)
            }
        }
        .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 64)
        .frame(maxWidth: 1440, alignment: .leading)
    }

    private var lenses: some View {
        HStack(spacing: 2) {
            ForEach([("loop", "By band"), ("kind", "By kind"), ("folder", "By folder")], id: \.0) { id, label in
                let on = nav.lens == id
                Button { nav.lens = id; nav.libSel = nil } label: {
                    Text(label).font(.system(size: 12, weight: on ? .semibold : .regular)).foregroundStyle(t.text.color)
                        .padding(.horizontal, 12).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 5).fill(on ? t.surface.color : Color.clear).shadow(color: on ? t.text.color.opacity(0.12) : .clear, radius: 1, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2).background(RoundedRectangle(cornerRadius: 7).fill(t.control.color))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(t.accent.color).frame(width: 12, height: 12); Text("start here") }
            HStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 3).fill(t.control.color).frame(width: 12, height: 12)
                    .overlay(alignment: .bottom) { Rectangle().fill(t.text3.color).frame(height: 6) }.clipShape(RoundedRectangle(cornerRadius: 3))
                Text("bar = length")
            }
            HStack(spacing: 5) { RoundedRectangle(cornerRadius: 3).fill(t.control.color).frame(width: 12, height: 12).overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(t.text.color, lineWidth: 2)); Text("playing") }
        }
        .font(.system(size: 11)).foregroundStyle(t.text2.color)
    }

    private func reader(_ n: Int, _ q: String, folders: Bool = false) -> some View {
        let d = t.display
        // By folder (LAB-1253_3): the row under the pointer, else the card playing.
        let hc = (nav.hover ?? (folders ? audio.playingSlug : nil)).flatMap { audio.deck.cards[$0] }
        let kick: String = {
            guard let hc else { return folders ? "HOVER A ROW" : q.isEmpty ? "HOVER A SQUARE" : "\(n) MATCHES LIT" }
            let b = audio.deck.band(of: hc.slug)
            return "BAND \(b.n) · \((LearnDeck.trackNames[hc.track]?.name ?? hc.track).uppercased()) · \(LearnDeck.minutes(hc.estSeconds).uppercased())"
        }()
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(kick).font(.system(size: 11, design: .monospaced)).tracking(0.6).foregroundStyle(d.accent.color)
            Text(hc?.title ?? (folders ? "Each skill folder is one card" : q.isEmpty ? "Each square is one card" : "Everything else is dimmed")).font(.system(size: 14, weight: .semibold)).foregroundStyle(d.text.color)
            Text(hc.map { $0.subtitle.isEmpty ? $0.description : $0.subtitle }
                 ?? (folders ? "Click a folder to list it, click a file to read it, double-click a skill to open the card."
                     : q.isEmpty ? "Click a block to list it, click a square to open the card." : "Matches are listed on the right."))
                .font(.system(size: 13)).foregroundStyle(d.mute.color).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(d.fill.color))
    }

    private func map(_ cols: [Column], _ hits: [String], _ q: String) -> some View {
        let lit = Set(hits)
        return HStack(alignment: .top, spacing: 12) {
            ForEach(cols) { col in
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(col.head).font(.system(size: 17, weight: .bold)).foregroundStyle(t.text.color)
                            Spacer()
                            Text("\(col.count) cards").font(.system(size: 11)).foregroundStyle(t.text3.color)
                        }
                        Text(col.sub).font(.system(size: 12)).foregroundStyle(t.text2.color)
                    }
                    .padding(.horizontal, 2).padding(.bottom, 10)
                    Rectangle().fill(t.separatorStrong.color).frame(height: 1)
                    ForEach(col.blocks) { bk in block(bk, lit, q).padding(.top, 10) }
                }
                .padding(12)
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.toolbar.color))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
                .layoutPriority(Double(col.grow))
            }
        }
        .onHover { if !$0 { nav.hover = nil } }
    }

    private func block(_ bk: Block, _ lit: Set<String>, _ q: String) -> some View {
        let on = nav.libSel == bk.id
        let deck = audio.deck
        return VStack(alignment: .leading, spacing: 7) {
            Button { nav.libSel = on ? nil : bk.id } label: {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(bk.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
                        Spacer()
                        Text("\(bk.cards.count)").font(.system(size: 11)).foregroundStyle(t.text3.color)
                    }
                    Text(bk.question).font(.system(size: 11)).foregroundStyle(t.text2.color).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            LearnFlow(spacing: 3) {
                ForEach(bk.cards, id: \.self) { k in
                    let c = deck.cards[k]
                    let secs = CGFloat(c?.estSeconds ?? 0)
                    let ring: Color = audio.playingSlug == k ? t.text.color : nav.hover == k ? t.accent.color : .clear
                    Button { nav.openCard(k) } label: {
                        RoundedRectangle(cornerRadius: 4).fill(bk.start ? t.accent.color : t.control.color)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(bk.start ? t.onAccent.color.opacity(0.75) : t.text3.color).frame(height: (3 + min(12, secs / 40)).rounded())
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(ring, lineWidth: 2))
                            .frame(width: 18, height: 18)
                            .opacity(q.isEmpty || lit.contains(k) ? 1 : 0.18)
                    }
                    .buttonStyle(.plain)
                    .onHover { if $0 { nav.hover = k } }
                    .help("\(c?.title ?? k) · \(LearnDeck.minutes(c?.estSeconds ?? 0))")
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? t.selection.color : t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(on ? t.accent.color : t.separator.color, lineWidth: 1))
    }

    @ViewBuilder private func panel(_ sel: Block?, _ hits: [String], _ postHits: [LearnPost], _ q: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !q.isEmpty { search(hits, postHits) }
            else if let sel { selected(sel) }
            else { intro }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
    }

    var intro: some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnKicker(text: "How the map reads", color: t.text3.color, size: 10)
            Text("Every square is one card. Columns are the four bands of the dial, in the order work happens. Each block inside answers one question in plain words; the small grey name is the track it ships under.")
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.bottom, 12)
            ForEach(LearnDeck.bands) { b in
                Button { nav.lens = "loop"; nav.libSel = b.id + ":start" } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(b.n).font(.system(size: 11, design: .monospaced)).foregroundStyle(t.accentText.color).frame(width: 28, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(b.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
                            Text(b.sub).font(.system(size: 12)).foregroundStyle(t.text2.color)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Hover a square to read it. Click a block to list it here. Click a square to open the card.")
                .font(.system(size: 12)).foregroundStyle(t.text3.color).padding(.top, 10)
        }
    }

    /// LAB-1274 · By folder's panel with nothing selected: how the table reads (By band / By kind keep `intro`).
    var folderIntro: some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnKicker(text: "How the table reads", color: t.text3.color, size: 10)
            Text("This is the deck's skills folder as it ships inside One Roof. Each row under it is a folder: a track first, then one folder per skill, holding the card, its skill file, its scenes and its narration.")
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.bottom, 12)
            ForEach([("Name", "The folder or file. ▸ opens a folder in place."),
                     ("What it is", "The track's plain name, the card's title, or what a file is for."),
                     ("Band", "The band of the dial a track's cards play on. Click it to open the band."),
                     ("Size", "Skills in a track, minutes of a card, clips of narration.")], id: \.0) { k, v in
                HStack(alignment: .top, spacing: 8) {
                    Text(k.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(t.accentText.color)
                        .frame(width: 84, alignment: .leading)
                    Text(v).font(.system(size: 12)).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
            Text("Click a folder to open it and list it here. Click a file to read it here. Double-click a skill to open its card.")
                .font(.system(size: 12)).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
        }
    }

    private func selected(_ b: Block) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LearnKicker(text: b.kicker, size: 10)
                Spacer()
                Button { nav.libSel = nil } label: { Text("Close").font(.system(size: 12)).foregroundStyle(t.text3.color) }.buttonStyle(.plain)
            }
            Text(b.name).font(.system(size: 26, weight: .bold)).tracking(-0.5).foregroundStyle(t.text.color).padding(.top, 4).padding(.bottom, 2)
            Text(b.question).font(.system(size: 14)).foregroundStyle(t.text.color).padding(.bottom, 4)
            Text(b.intro).font(.system(size: 12)).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
            HStack(spacing: 8) {
                LearnPillPlay(label: "Play all \(b.cards.count)") { if let f = b.cards.first { audio.play(f, then: b.cards) } }
                Text(b.raw).font(.system(size: 11, design: .monospaced)).foregroundStyle(t.text3.color)
            }
            .padding(.bottom, 8)
            cardList(b.cards, queue: b.cards, subtitle: true)
        }
    }

    private func search(_ hits: [String], _ postHits: [LearnPost]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            LearnKicker(text: "How do I…", size: 10)
            Text("\(hits.count) cards · \(postHits.count) posts").font(.system(size: 22, weight: .bold)).foregroundStyle(t.text.color).padding(.top, 4).padding(.bottom, 8)
            ForEach(postHits) { p in
                Button { nav.openPost(p.slug) } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Post · " + LearnPosts.state(p, in: posts, today: LearnPostRow.today).label).font(.system(size: 11)).foregroundStyle(t.accentText.color)
                        Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t.selection.color))
                }
                .buttonStyle(.plain).padding(.bottom, 6)
            }
            cardList(hits, queue: [], subtitle: false)
        }
    }

    private func cardList(_ ks: [String], queue: [String], subtitle: Bool) -> some View {
        let deck = audio.deck
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(ks, id: \.self) { k in
                    let c = deck.cards[k]
                    let b = deck.band(of: k)
                    HStack(alignment: .top, spacing: 8) {
                        LearnRoundPlay(playing: audio.playingSlug == k && player.playing, size: 22) { audio.toggle(k, then: queue.isEmpty ? [k] : Array(queue.drop { $0 != k })) }
                        Button { nav.openCard(k) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c?.title ?? k).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color)
                                Text(subtitle ? (c?.subtitle ?? "") : "Band \(b.n) · \(LearnDeck.trackNames[c?.track ?? ""]?.name ?? LearnDeck.label(c?.track ?? ""))")
                                    .font(.system(size: subtitle ? 12 : 11)).foregroundStyle(subtitle ? t.text2.color : t.text3.color).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Text(LearnDeck.minutes(c?.estSeconds ?? 0)).font(.system(size: 11)).foregroundStyle(t.text3.color)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(audio.playingSlug == k ? t.selection.color : Color.clear))
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                }
            }
        }
        .frame(maxHeight: 520)
    }
}
