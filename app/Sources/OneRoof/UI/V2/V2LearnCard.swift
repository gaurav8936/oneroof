import AppKit
import SwiftUI
import OneRoofCore

// LAB-1233 · Learn › the card station (L2): Listen (scene by scene, in step with the narration), Transcript and the
// card's Skill file, with chapters, triggers, pairs, posts and what is next on the band down the right.

struct LearnCardStation: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        if let c = deck.cards[nav.slug] {
            let scenes = nav.scenes(c.slug, deck)
            let here = audio.playingSlug == c.slug
            let idx = max(0, min(scenes.count - 1, here ? player.index : nav.scene))
            HStack(alignment: .top, spacing: 32) {
                main(c, scenes, idx, here).frame(maxWidth: .infinity)
                LearnCardSide(nav: nav, player: player, audio: audio, posts: posts, card: c, scenes: scenes, idx: idx, here: here).frame(width: 320)
            }
            .padding(.horizontal, 40).padding(.top, 24).padding(.bottom, 48)
            .frame(maxWidth: 1360, alignment: .leading)
        }
    }

    private func main(_ c: DeckCard, _ scenes: [DeckScene], _ idx: Int, _ here: Bool) -> some View {
        let b = audio.deck.band(of: c.slug)
        let narrated = here || FileManager.default.fileExists(atPath: (audio.deck.htmlPath(c.slug) as NSString).deletingPathExtension + "_audio")
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Button { nav.openBand(b.id) } label: { LearnKicker(text: "Band \(b.n) · \(b.title) · \(LearnDeck.label(c.track))") }.buttonStyle(.plain)
                Spacer()
                Text("\(c.scenes) scenes · \(LearnDeck.minutes(c.estSeconds))" + (narrated ? " · narration bundled" : ""))
                    .font(.system(size: 12)).foregroundStyle(t.text3.color)
            }
            Text(c.title).font(.system(size: 48, weight: .bold)).tracking(-1.4).foregroundStyle(t.text.color).padding(.top, 6).padding(.bottom, 6)
            Text(c.subtitle.isEmpty ? c.description : c.subtitle).font(.system(size: 17)).foregroundStyle(t.text2.color).padding(.bottom, 16)
                .fixedSize(horizontal: false, vertical: true)
            tabs.padding(.bottom, 16)
            switch nav.tab {
            case "transcript": LearnTranscript(nav: nav, audio: audio, card: c, scenes: scenes, idx: idx)
            case "skill": LearnSkillFile(nav: nav, audio: audio, card: c)
            default: LearnListen(nav: nav, player: player, audio: audio, card: c, scenes: scenes, idx: idx, here: here)
            }
        }
    }

    private var tabs: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach([("listen", "Listen"), ("transcript", "Transcript"), ("skill", "Skill file")], id: \.0) { id, label in
                    let on = nav.tab == id
                    Button { nav.tab = id } label: {
                        Text(label).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(on ? t.text.color : t.text2.color)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(on ? t.accent.color : Color.clear).frame(height: 2) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            Rectangle().fill(t.separatorStrong.color).frame(height: 1)
        }
    }
}

/// Listen: the scene's panel (section, kicker, heading, the section's diagram with this scene's nodes lit, the lede and
/// points), scene dots, and the narration text under it.
struct LearnListen: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let card: DeckCard
    let scenes: [DeckScene]
    let idx: Int
    let here: Bool
    @Environment(\.theme) private var t

    var body: some View {
        let s = scenes.indices.contains(idx) ? scenes[idx] : nil
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    LearnKicker(text: "Scene \(idx + 1) of \(scenes.count) · \(s?.section ?? "")", color: t.text3.color)
                    Spacer()
                    LearnKicker(text: live, color: here ? t.accentText.color : t.text3.color)
                }
                if let s {
                    Text(s.kicker).font(.system(size: 12, weight: .semibold)).foregroundStyle(t.accentText.color).padding(.top, 18)
                    Text(s.heading).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(t.text.color)
                        .frame(maxWidth: 760, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    blocks(s).padding(.top, 20)
                }
                Spacer(minLength: 0)
                controls.padding(.top, 22)
            }
            .padding(.horizontal, 28).padding(.vertical, 26)
            .frame(maxWidth: .infinity, minHeight: 360, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(t.toolbar.color))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
            if let s, !s.narration.isEmpty {
                Text(s.narration).font(.system(size: 15)).lineSpacing(5).foregroundStyle(t.text.color)
                    .frame(maxWidth: 780, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                    .textSelection(.enabled)
            }
        }
    }

    private var live: String {
        if here { return player.playing ? "● Playing · \(LearnDeck.clock(player.elapsed)) / \(LearnDeck.clock(player.duration))" : "Paused" }
        return ""
    }

    @ViewBuilder private func blocks(_ s: DeckScene) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !s.nodes.isEmpty {
                LearnFlow(spacing: 10) {
                    ForEach(Array(s.nodes.enumerated()), id: \.offset) { _, n in
                        let lit = s.highlight.contains(n.id)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color)
                            if !n.sub.isEmpty { Text(n.sub).font(.system(size: 12)).foregroundStyle(t.text2.color) }
                        }
                        .frame(minWidth: 150, maxWidth: 260, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? t.selection.color : t.surface.color))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(lit ? t.accent.color : t.separator.color, lineWidth: 1))
                    }
                }
            }
            if !s.lede.isEmpty || !s.points.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !s.lede.isEmpty { Text(s.lede).font(.system(size: 14, weight: .medium)).foregroundStyle(t.text.color) }
                    ForEach(s.points, id: \.self) { p in Text("· " + p).font(.system(size: 13)).foregroundStyle(t.text2.color) }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) { Rectangle().fill(t.accent.color).frame(width: 2) }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            circle("chevron.left") { here ? player.previous() : (nav.scene = max(0, idx - 1)) }
            HStack(spacing: 4) {
                ForEach(0..<scenes.count, id: \.self) { i in
                    Button { here ? audio.play(card.slug, scene: i, then: audio.bandFrom(card.slug)) : (nav.scene = i) } label: {
                        RoundedRectangle(cornerRadius: 3).fill(i == idx ? t.accent.color : i < idx ? t.separatorStrong.color : t.control.color)
                            .frame(height: 5).frame(maxWidth: .infinity).contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain).help(scenes[i].kicker)
                }
            }
            circle("chevron.right") { here ? player.next() : (nav.scene = min(scenes.count - 1, idx + 1)) }
        }
    }

    private func circle(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.system(size: 12, weight: .semibold)).foregroundStyle(t.text.color)
                .frame(width: 30, height: 30).background(Circle().fill(t.surface.color)).overlay(Circle().strokeBorder(t.separatorStrong.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Lays children out left to right, wrapping (the scene's diagram boxes).
struct LearnFlow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 800
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(w, maxX), height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

struct LearnTranscript: View {
    @ObservedObject var nav: LearnNav
    let audio: LearnAudio
    let card: DeckCard
    let scenes: [DeckScene]
    let idx: Int
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(scenes.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .top, spacing: 14) {
                    Button { audio.play(card.slug, scene: i, then: audio.bandFrom(card.slug)) } label: {
                        Text(String(format: "%02d", i + 1)).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain).frame(width: 44, alignment: .leading).help("Play from here")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(s.section) · \(s.kicker)".uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(t.text3.color)
                        Text(s.heading).font(.system(size: 15, weight: .semibold)).foregroundStyle(t.text.color).padding(.top, 2).padding(.bottom, 4)
                        Text(s.narration.isEmpty ? "This scene has no narration in the bundled deck." : s.narration)
                            .font(.system(size: 14)).lineSpacing(4).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 6).fill(i == idx ? t.selection.color : Color.clear))
                .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
        }
        .textSelection(.enabled)
    }
}

struct LearnSkillFile: View {
    @ObservedObject var nav: LearnNav
    let audio: LearnAudio
    let card: DeckCard
    @Environment(\.theme) private var t
    @Environment(\.textScale) private var scale

    var body: some View {
        let path = audio.deck.skillPath(card.slug)
        VStack(alignment: .leading, spacing: 0) {
            Text(card.skill).font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text3.color).padding(.bottom, 10)
            if let s = nav.skill(card.slug, audio.deck) {
                VStack(spacing: 0) {
                    ForEach(Array(s.front.enumerated()), id: \.offset) { i, f in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(f.key).foregroundStyle(t.text3.color).frame(width: 140, alignment: .leading)
                            Text(f.value).foregroundStyle(t.text.color).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.system(size: 12, design: .monospaced)).padding(.vertical, 6)
                        .overlay(alignment: .bottom) { if i < s.front.count - 1 { Rectangle().fill(t.separator.color).frame(height: 1) } }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.toolbar.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color, lineWidth: 1))
                .padding(.bottom, 18)
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(MarkdownDoc.parse(s.body).enumerated()), id: \.offset) { _, b in
                        MarkdownBlockView(block: b, path: path, t: t, scale: scale, depth: 0)
                    }
                }
                .textSelection(.enabled)
            } else {
                Text("The bundled deck has no SKILL.md for this card.").font(.system(size: 14)).foregroundStyle(t.text2.color)
            }
        }
    }
}

/// The station's right column.
struct LearnCardSide: View {
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    let posts: [LearnPost]
    let card: DeckCard
    let scenes: [DeckScene]
    let idx: Int
    let here: Bool
    @Environment(\.theme) private var t

    var body: some View {
        let deck = audio.deck
        let band = deck.band(of: card.slug)
        let list = deck.lists[band.id] ?? []
        let at = list.firstIndex(of: card.slug) ?? 0
        let next = Array(list.dropFirst(at + 1).prefix(4))
        let pairs = (nav.skill(card.slug, deck)?.dependencies ?? []).filter { deck.cards[$0] != nil }
        let reads = band.posts.compactMap { s in posts.first { $0.slug == s } }
        let current = scenes.indices.contains(idx) ? scenes[idx].sectionIndex : -1
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                LearnRuleHeading(text: "Chapters")
                ForEach(Array(card.sections.enumerated()), id: \.offset) { i, sec in
                    let on = i == current
                    Button {
                        let first = scenes.firstIndex { $0.sectionIndex == i } ?? 0
                        if here { audio.play(card.slug, scene: first, then: audio.bandFrom(card.slug)) } else { nav.scene = first; nav.tab = "listen" }
                    } label: {
                        HStack(spacing: 8) {
                            Text(String(format: "%02d", i + 1)).font(.system(size: 11, design: .monospaced)).foregroundStyle(on ? t.accentText.color : t.text3.color).frame(width: 22, alignment: .leading)
                            Text(DeckSpec.clean(sec.title)).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundStyle(t.text.color).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(sec.scenes) scene\(sec.scenes == 1 ? "" : "s")").font(.system(size: 11)).foregroundStyle(t.text3.color)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? t.selection.color : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                LearnRuleHeading(text: "Say it in a session").padding(.bottom, 3)
                ForEach(card.triggers.prefix(4), id: \.self) { tr in
                    Text("\u{201C}\(tr)\u{201D}").font(.system(size: 12, design: .monospaced)).foregroundStyle(t.text.color)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(t.surface2.color))
                }
                (Text("Or send ") + Text("/\(card.slug)").font(.system(size: 11, design: .monospaced)) + Text(" to a live session with Use in a session."))
                    .font(.system(size: 11)).foregroundStyle(t.text3.color).padding(.top, 1)
            }
            if !pairs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    LearnRuleHeading(text: "Pairs with")
                    ForEach(pairs, id: \.self) { k in sideLink(deck.cards[k]?.title ?? k, nil) { nav.openCard(k) } }
                }
            }
            if !reads.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    LearnRuleHeading(text: "Read about it")
                    ForEach(reads) { p in
                        Button { nav.openPost(p.slug) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text((p.series == "Agentic engineering" ? "Series" : "Field notes") + " · " + LearnPosts.state(p, in: posts, today: LearnPostRow.today).label)
                                    .font(.system(size: 11)).foregroundStyle(t.text3.color)
                                Text(p.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !next.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    LearnRuleHeading(text: "Next on the \(band.title) band")
                    ForEach(next, id: \.self) { k in sideLink(deck.cards[k]?.title ?? k, LearnDeck.minutes(deck.cards[k]?.estSeconds ?? 0)) { nav.openCard(k) } }
                }
            }
        }
    }

    private func sideLink(_ title: String, _ trailing: String?, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack {
                Text(title).font(.system(size: 13, weight: trailing == nil ? .semibold : .medium)).foregroundStyle(t.text.color)
                Spacer()
                if let trailing { Text(trailing).font(.system(size: 11)).foregroundStyle(t.text3.color) }
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The card's header actions: Play in One Roof · Use in a session ▾ · Open in browser.
struct LearnCardActions: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: LearnNav
    @ObservedObject var player: CoursePlayer
    let audio: LearnAudio
    @State private var sessionsOpen = false
    @Environment(\.theme) private var t

    var body: some View {
        let slug = nav.slug
        let here = audio.playingSlug == slug
        HStack(spacing: 6) {
            Button { audio.toggle(slug, scene: here ? player.index : nav.scene, then: audio.bandFrom(slug)) } label: {
                HStack(spacing: 6) {
                    Image(systemName: here && player.playing ? "pause.fill" : "play.fill").font(.system(size: 9))
                    Text(here ? (player.playing ? "Pause" : "Resume") : "Play in One Roof")
                }
            }
            .buttonStyle(LearnChipStyle())
            Button { sessionsOpen.toggle() } label: { Text("Use in a session ▾") }
                .buttonStyle(LearnChipStyle())
                .popover(isPresented: $sessionsOpen, arrowEdge: .bottom) { sessions(slug) }
            Button { NSWorkspace.shared.open(URL(fileURLWithPath: audio.deck.htmlPath(slug))) } label: {
                HStack(spacing: 6) { Image(systemName: "safari").font(.system(size: 11)); Text("Open in browser") }
            }
            .buttonStyle(LearnChipStyle())
        }
    }

    private func sessions(_ slug: String) -> some View {
        let live = model.items.filter { $0.liveAgent != nil && $0.session.agent.isAgent }
        return VStack(alignment: .leading, spacing: 2) {
            Text("Type /\(slug) as the next message in").font(.system(size: 11)).foregroundStyle(t.text3.color).padding(.horizontal, 8).padding(.vertical, 4)
            if live.isEmpty {
                Text("No live agent session. Start one, then send the card to it.").font(.system(size: 12)).foregroundStyle(t.text2.color)
                    .padding(.horizontal, 8).padding(.vertical, 6)
            }
            ForEach(live) { i in
                Button {
                    sessionsOpen = false
                    if i.status == .running { nav.flash("\(i.session.name) is working; send /\(slug) when it is idle") }
                    else { model.sendSkill(slug, to: i); nav.flash("Sent /\(slug) to \(i.session.name)") }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(t.statusColor(i.status).color).frame(width: 7, height: 7)
                        Text(i.session.name).font(.system(size: 13)).foregroundStyle(t.text.color).frame(maxWidth: .infinity, alignment: .leading)
                        Text(i.status.rawValue.capitalized).font(.system(size: 11)).foregroundStyle(t.text3.color)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6).frame(minWidth: 280)
    }
}
